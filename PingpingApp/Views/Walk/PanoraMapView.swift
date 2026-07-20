import SwiftUI
import CoreLocation
import UIKit
import MapboxMaps

/// 遛狗模块三张地图共用的 Mapbox 封装。
///
/// 为什么用 UIViewRepresentable 包命令式的 MapView，而不用 MapboxMaps 自带的 SwiftUI `Map`：
/// 命令式那套（PolylineAnnotationManager / PointAnnotationManager / setCamera）从 v10 到 v11
/// 基本没动；SwiftUI 那套的 Viewport / ViewAnnotation 在 11.x 各小版本之间改过签名。
/// 本地没 Mac 编译不了、一轮 CI 15 分钟，这里拿代码量换编译确定性。
///
/// 所有传进来的坐标都当成 GCJ-02（CLLocation 在国内给的就是它），
/// 内部统一转 WGS-84 再交给 Mapbox，见 CoordinateTransform。
struct PanoraMapView: UIViewRepresentable {
    /// 轨迹点。少于 2 个就不画线。
    var route: [CLLocationCoordinate2D] = []
    /// 狗头 pin 位置，nil 就不画。
    var pin: CLLocationCoordinate2D?
    /// 相机中心，nil 表示这轮不动相机。
    var center: CLLocationCoordinate2D?
    /// 缩放级别。16.5 ≈ 原来 MapKit 的 350m 视距，15 ≈ 800m。
    var zoom: Double = 16.5
    /// 点按「回到我的位置」时 +1，立刻重设相机、并清掉「用户刚摸过地图」的冷却。
    var recenterToken: Int = 0
    /// 关掉全部手势（纯展示卡用）。
    var interactive: Bool = true
    /// 真时忽略 center/zoom，改成把整条轨迹装进画面（总结页那张卡）。
    var fitsRoute: Bool = false
    /// 狗头渲染尺寸（pt）。
    var pinWidth: CGFloat = 44
    /// 用户手动拖动地图后，隔多久自动回正到 center。
    var recenterDelay: TimeInterval = 4
    /// 临时诊断：在**未做坐标转换**的原始位置上再画一个红点。
    /// 用来一轮定位「差几百米」到底是转换没生效、还是转反了。验完删掉这个参数和相关代码。
    var debugShowRawPin: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MapView {
        // 不用手动传 token：SDK 启动时自己读 Info.plist 里的 MBXAccessToken。
        let map = MapView(frame: .zero, mapInitOptions: MapInitOptions(styleURI: .dark))
        map.ornaments.options.scaleBar.visibility = .hidden
        map.ornaments.options.compass.visibility = .hidden
        // 左下角的 logo 和右下角的蓝圈 i（attribution）去不掉，别再试了：
        // 这两个的 .visibility 被 Mapbox 标了 @_spi，外部代码碰不到，编译期直接报
        // 「inaccessible due to '@_spi' protection level」。scaleBar / compass 的同名属性是公开的，
        // 唯独这两个不是 —— 因为使用条款要求署名必须可见，SDK 就在编译期焊死了。
        // 想让它们不那么显眼，合规的做法是调 position / margins 挪位置，不是藏。
        map.isUserInteractionEnabled = interactive

        let coord = context.coordinator
        coord.map = map
        coord.polylines = map.annotations.makePolylineAnnotationManager()
        coord.points = map.annotations.makePointAnnotationManager()
        coord.recenterDelay = recenterDelay

        if interactive {
            coord.attachInteractionWatchers(to: map)
        }

        // 保险丝：如果 annotation 是在样式加载完之前塞进去的，有可能被丢掉。
        // 这里延迟重放一次。本来该观察 mapboxMap.onStyleLoaded，但 v11 那套是 Signal，
        // 签名比命令式 API 新、手头又编译不了，先用这个零风险的兜底。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak coord] in
            coord?.replayAnnotations()
        }
        return map
    }

    func updateUIView(_ map: MapView, context: Context) {
        let coord = context.coordinator
        coord.recenterDelay = recenterDelay
        let wgs: [CLLocationCoordinate2D] = route.map(CoordinateTransform.gcj02ToWgs84)

        // 轨迹线：整条全量替换。点数量级就几百，比维护增量简单得多。
        var lines: [PolylineAnnotation] = []
        if wgs.count >= 2 {
            var line = PolylineAnnotation(lineCoordinates: wgs)
            line.lineColor = StyleColor(UIColor(Panora.lime))
            line.lineWidth = 5
            line.lineJoin = .round
            lines = [line]
        }

        // 狗头：dog_pin 的尖尖在图底边，iconAnchor = .bottom 等价于 MapKit 那版的 anchor: .bottom。
        // 图按 pinWidth 先缩好再交出去，比调 iconSize 好预测（iconSize 是相对原图分辨率的倍数）。
        var pins: [PointAnnotation] = []
        if let pin, let image = coord.pinImage(width: pinWidth) {
            var point = PointAnnotation(coordinate: CoordinateTransform.gcj02ToWgs84(pin))
            point.image = PointAnnotation.Image(image: image, name: "dog_pin")
            point.iconAnchor = .bottom
            pins.append(point)

            // 临时诊断用的红点：画在没转换过的原始坐标上。
            if debugShowRawPin, let dot = coord.rawDotImage() {
                var raw = PointAnnotation(coordinate: pin)
                raw.image = PointAnnotation.Image(image: dot, name: "raw_dot")
                raw.iconAnchor = .center
                pins.append(raw)
            }
        }

        coord.apply(lines: lines, pins: pins)

        if fitsRoute {
            // 只在点数变了才重套一次，不然每次 update 都重设相机。
            if wgs.count >= 2, coord.lastFittedCount != wgs.count {
                coord.lastFittedCount = wgs.count
                map.mapboxMap.setCamera(to: Self.fitCamera(for: wgs))
            }
            return
        }

        guard let center else { return }
        coord.desiredCenter = center
        coord.desiredZoom = zoom

        if coord.lastToken != recenterToken {
            // 点了「回到我的位置」：立刻回，并且清掉手动操作的冷却。
            coord.lastToken = recenterToken
            coord.lastInteraction = nil
            coord.applyCamera()
            return
        }

        // 中心没变就别动相机，否则任何无关的状态刷新都会把镜头拽回去。
        let changed: Bool = coord.lastAppliedCenter?.latitude != center.latitude
            || coord.lastAppliedCenter?.longitude != center.longitude
        guard changed else { return }

        if coord.isInUserControl {
            // 用户刚拖过地图，这轮先不抢镜头；等 4s 的定时器到点自己回正。
            coord.scheduleAutoRecenter()
        } else {
            coord.applyCamera()
        }
    }

    /// 自己算包围盒 + zoom，不用 Mapbox 的 camera(for:...)。
    /// 那个方法的参数列表在 11.x 里改过，这边只用 CameraOptions，编译风险最小。
    private static func fitCamera(for coords: [CLLocationCoordinate2D]) -> CameraOptions {
        let lats: [Double] = coords.map(\.latitude)
        let lons: [Double] = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return CameraOptions() }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        // z = log2(360 / 经度跨度)；纬度跨度按 cos(lat) 折算成等效经度跨度再取大的那个。
        let lonSpan: Double = max(maxLon - minLon, 0.0005)
        let shrink: Double = max(cos(center.latitude * .pi / 180), 0.1)
        let latSpan: Double = max((maxLat - minLat) / shrink, 0.0005)
        let span: Double = max(lonSpan, latSpan)
        let raw: Double = log2(360.0 / span)
        // -1 档留白，再钳进合理区间免得单点轨迹把 zoom 顶到天上。
        let zoom: Double = min(max(raw - 1.0, 2.0), 17.0)
        return CameraOptions(center: center, zoom: zoom)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var map: MapView?
        var polylines: PolylineAnnotationManager?
        var points: PointAnnotationManager?
        var lastFittedCount: Int = 0
        var lastAppliedCenter: CLLocationCoordinate2D?
        var lastToken: Int = -1

        var desiredCenter: CLLocationCoordinate2D?
        var desiredZoom: Double = 16.5
        var recenterDelay: TimeInterval = 4
        /// 用户最后一次碰地图的时间。nil = 没碰过 / 已经回正了。
        var lastInteraction: Date?
        private var recenterTimer: Timer?

        private var pendingLines: [PolylineAnnotation] = []
        private var pendingPins: [PointAnnotation] = []

        // MARK: 标注

        func apply(lines: [PolylineAnnotation], pins: [PointAnnotation]) {
            pendingLines = lines
            pendingPins = pins
            polylines?.annotations = lines
            points?.annotations = pins
        }

        /// 样式加载完之后重放一次，见 makeUIView 里的保险丝。
        func replayAnnotations() {
            polylines?.annotations = pendingLines
            points?.annotations = pendingPins
        }

        // MARK: 相机

        var isInUserControl: Bool {
            guard let lastInteraction else { return false }
            return Date().timeIntervalSince(lastInteraction) < recenterDelay
        }

        func applyCamera() {
            guard let map, let desiredCenter else { return }
            lastAppliedCenter = desiredCenter
            lastInteraction = nil
            recenterTimer?.invalidate()
            recenterTimer = nil
            let target = CoordinateTransform.gcj02ToWgs84(desiredCenter)
            map.mapboxMap.setCamera(to: CameraOptions(center: target, zoom: desiredZoom))
        }

        /// 手离开地图后 recenterDelay 秒自动回正。期间又碰了就重新计时。
        func scheduleAutoRecenter() {
            recenterTimer?.invalidate()
            recenterTimer = Timer.scheduledTimer(withTimeInterval: recenterDelay,
                                                 repeats: false) { [weak self] _ in
                self?.applyCamera()
            }
        }

        // MARK: 手势侦测

        /// 挂我们自己的 pan / pinch 识别器，只为记录「用户在操作地图」。
        /// 不用 Mapbox 的 GestureManagerDelegate：那是 v11 的新 API，这套纯 UIKit 的零编译风险。
        func attachInteractionWatchers(to map: MapView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(userTouchedMap(_:)))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(userTouchedMap(_:)))
            for g in [pan, pinch] as [UIGestureRecognizer] {
                g.delegate = self
                g.cancelsTouchesInView = false
                map.addGestureRecognizer(g)
            }
        }

        @objc private func userTouchedMap(_ g: UIGestureRecognizer) {
            lastInteraction = Date()
            // 手一松就开始倒计时；中途继续拖会不断刷新这个计时器。
            if g.state == .ended || g.state == .cancelled || g.state == .failed {
                scheduleAutoRecenter()
            }
        }

        /// 必须允许并行，否则会把 Mapbox 自己的拖动/缩放吃掉。
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        // MARK: 图片

        private var cachedPin: UIImage?
        private var cachedWidth: CGFloat = 0
        private var cachedDot: UIImage?

        /// 缩好的狗头缓存一份。每帧重绘一张位图没必要，而且换图会让 Mapbox 重传纹理。
        func pinImage(width: CGFloat) -> UIImage? {
            if let cachedPin, cachedWidth == width { return cachedPin }
            guard let original = UIImage(named: "dog_pin") else { return nil }
            let ratio: CGFloat = original.size.height / max(original.size.width, 1)
            let size = CGSize(width: width, height: width * ratio)
            let scaled = UIGraphicsImageRenderer(size: size).image { _ in
                original.draw(in: CGRect(origin: .zero, size: size))
            }
            cachedPin = scaled
            cachedWidth = width
            return scaled
        }

        /// 临时诊断用的红点，代码画的，不占资源文件。验完连同 debugShowRawPin 一起删。
        func rawDotImage() -> UIImage? {
            if let cachedDot { return cachedDot }
            let size = CGSize(width: 16, height: 16)
            let dot = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.systemRed.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
                UIColor.white.setStroke()
                ctx.cgContext.setLineWidth(2)
                ctx.cgContext.strokeEllipse(in: CGRect(x: 1, y: 1, width: 14, height: 14))
            }
            cachedDot = dot
            return dot
        }
    }
}
