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
/// 坐标直接用 CLLocation 给的原值，**不做 GCJ-02 → WGS-84 转换**。
/// 这是真机验出来的：同时画「转换后」和「未转换」两个点，未转换的那个才落在真实位置上，
/// 说明 Mapbox 在这儿返回的底图跟 GCJ-02 是对齐的。转换反而会把狗头推偏几百米。
/// CoordinateTransform 因此暂时没人调，留着没删，见 docs/HANDOFF.md。
struct PanoraMapView: UIViewRepresentable {
    /// 轨迹点。少于 2 个就不画线。
    var route: [CLLocationCoordinate2D] = []
    /// 狗头 pin 位置，nil 就不画。
    var pin: CLLocationCoordinate2D?
    /// 尿尿图钉（niaoniao2），点尿尿时定位掉一颗。
    var peeSpots: [CLLocationCoordinate2D] = []
    /// 拉屎图钉（bianbian2），点拉屎时定位掉一颗。
    var poopSpots: [CLLocationCoordinate2D] = []
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
    /// 相机俯仰角（度）。0 = 纯俯视；大于 0 才能看出 3D 建筑物的高度。
    /// 只影响这一处的 setCamera，不影响 fitsRoute 那条包围盒计算路径（它没考虑 pitch）。
    var pitch: Double = 0
    /// 相机顶部内边距（pt）。P > 0 时中心会视觉上下移 P/2 ——
    /// 用来在「上方有 UI 遮挡」时把 pin 从几何正中挪开。
    var topPadding: CGFloat = 0

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

        // 保险丝：如果 annotation 或 3D 建筑层是在样式加载完之前塞进去的，有可能被丢掉。
        // 这里延迟重放一次。本来该观察 mapboxMap.onStyleLoaded，但 v11 那套是 Signal，
        // 签名比命令式 API 新、手头又编译不了，先用这个零风险的兜底。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak map, weak coord] in
            coord?.replayAnnotations()
            if let map {
                // polylines 比 points 先创建、处在图层栈更靠底部，塞在它下面同时把轨迹线
                // 和狗头 pin 都留在楼的上层，避免走到楼旁边时 pin 被 3D 楼体遮住。
                let below: String? = coord?.polylines?.id ?? coord?.points?.id
                Self.add3DBuildings(to: map, belowLayerId: below)
            }
        }
        return map
    }

    /// 从 Dark 底图自带的 composite/building 源里抬起楼体。zoom < 14 不画（远处一片色块反而糊）。
    /// 光有这个楼是平的贴图，还得配合相机 pitch > 0 才看得出立体 —— pitch 0 时就是俯视屋顶。
    ///
    /// belowLayerId 是让 3D 楼落在这个 annotation 图层之下，保证狗头 pin / 轨迹线永远在楼上面。
    /// 传 nil 就走默认位置（栈顶）—— 会盖住 pin，但至少不会崩，是最后的兜底。
    private static func add3DBuildings(to map: MapView, belowLayerId: String?) {
        var layer = FillExtrusionLayer(id: "panora-3d-buildings", source: "composite")
        layer.sourceLayer = "building"
        layer.minZoom = 14
        layer.filter = Exp(.eq) {
            Exp(.get) { "extrude" }
            "true"
        }
        layer.fillExtrusionColor = .constant(StyleColor(UIColor(white: 0.32, alpha: 1)))
        layer.fillExtrusionHeight = .expression(Exp(.get) { "height" })
        layer.fillExtrusionBase = .expression(Exp(.get) { "min_height" })
        layer.fillExtrusionOpacity = .constant(0.85)
        // 优先按参考图层往下塞；参考图层不存在（或已被移除）就默认位置托底。
        // try? 吞掉「layer 已存在」/「样式未加载」这两种可恢复错误：
        // 前者是 SwiftUI 重建 View 时的正常场景，后者会在下一次 update 触达时自愈。
        do {
            if let belowLayerId {
                try map.mapboxMap.addLayer(layer, layerPosition: .below(belowLayerId))
            } else {
                try map.mapboxMap.addLayer(layer)
            }
        } catch {
            try? map.mapboxMap.addLayer(layer)
        }
    }

    func updateUIView(_ map: MapView, context: Context) {
        let coord = context.coordinator
        coord.recenterDelay = recenterDelay
        let wgs: [CLLocationCoordinate2D] = route

        // 轨迹线：整条全量替换。点数量级就几百，比维护增量简单得多。
        var lines: [PolylineAnnotation] = []
        if wgs.count >= 2 {
            // id 必须固定：AnnotationManager 按 id 做 diff，每帧换 UUID 会被当成「旧的删、新的加」，
            // 同一渲染帧内先移除再重建纹理 → 视觉上就是狗头和线跟着定位刷一下一下地闪。
            var line = PolylineAnnotation(id: "walk-route", lineCoordinates: wgs)
            line.lineColor = StyleColor(UIColor(Panora.lime))
            line.lineWidth = 5
            line.lineJoin = .round
            lines = [line]
        }

        // 顺序很重要：PointAnnotationManager 按数组顺序渲染，靠后的画在上面。
        // 狗头会走动，可能路过老的尿尿/拉屎图钉，重叠时要让狗盖住图钉 → 狗最后 append。
        var pins: [PointAnnotation] = []

        // 尿尿 / 拉屎图钉：跟狗头同大小（不再压小一号），底边锚点跟狗头一致。
        if let image = coord.spotImage(asset: "niaoniao2", width: pinWidth) {
            for (i, spot) in peeSpots.enumerated() {
                var point = PointAnnotation(id: "pee-\(i)", coordinate: spot)
                point.image = PointAnnotation.Image(image: image, name: "niaoniao2")
                point.iconAnchor = .bottom
                pins.append(point)
            }
        }
        if let image = coord.spotImage(asset: "bianbian2", width: pinWidth) {
            for (i, spot) in poopSpots.enumerated() {
                var point = PointAnnotation(id: "poop-\(i)", coordinate: spot)
                point.image = PointAnnotation.Image(image: image, name: "bianbian2")
                point.iconAnchor = .bottom
                pins.append(point)
            }
        }

        // 狗头：dog_pin 的尖尖在图底边，iconAnchor = .bottom 等价于 MapKit 那版的 anchor: .bottom。
        // 图按 pinWidth 先缩好再交出去，比调 iconSize 好预测（iconSize 是相对原图分辨率的倍数）。
        if let pin, let image = coord.pinImage(width: pinWidth) {
            var point = PointAnnotation(id: "dog-pin", coordinate: pin)
            point.image = PointAnnotation.Image(image: image, name: "dog_pin")
            point.iconAnchor = .bottom
            pins.append(point)
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
        coord.desiredPitch = pitch
        coord.desiredTopPadding = topPadding

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
        var desiredPitch: Double = 0
        var desiredTopPadding: CGFloat = 0
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
            // 只有真需要的时候才带 padding，避免误改到其他调用方的默认视觉。
            let padding: UIEdgeInsets? = desiredTopPadding > 0
                ? UIEdgeInsets(top: desiredTopPadding, left: 0, bottom: 0, right: 0)
                : nil
            map.mapboxMap.setCamera(to: CameraOptions(
                center: desiredCenter,
                padding: padding,
                zoom: desiredZoom,
                pitch: CGFloat(desiredPitch)
            ))
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

        /// 尿尿 / 拉屎图钉缓存，按 (asset, width) 分开留一份，理由同上。
        private var cachedSpots: [String: UIImage] = [:]

        func spotImage(asset: String, width: CGFloat) -> UIImage? {
            let key = "\(asset)@\(Int(width))"
            if let cached = cachedSpots[key] { return cached }
            guard let original = UIImage(named: asset) else { return nil }
            let ratio: CGFloat = original.size.height / max(original.size.width, 1)
            let size = CGSize(width: width, height: width * ratio)
            let scaled = UIGraphicsImageRenderer(size: size).image { _ in
                original.draw(in: CGRect(origin: .zero, size: size))
            }
            cachedSpots[key] = scaled
            return scaled
        }
    }
}
