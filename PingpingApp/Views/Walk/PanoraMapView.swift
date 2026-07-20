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
    /// 点按「回到我的位置」时 +1，用来强制重设一次相机（中心没变也要生效）。
    var recenterToken: Int = 0
    /// 静态卡用：关掉全部手势。
    var interactive: Bool = true
    /// 真时忽略 center/zoom，改成把整条轨迹装进画面（总结页那张卡）。
    var fitsRoute: Bool = false
    /// 狗头渲染尺寸（pt）。
    var pinWidth: CGFloat = 44

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MapView {
        // 不用手动传 token：SDK 启动时自己读 Info.plist 里的 MBXAccessToken。
        let map = MapView(frame: .zero, mapInitOptions: MapInitOptions(styleURI: .dark))
        map.ornaments.options.scaleBar.visibility = .hidden
        map.ornaments.options.compass.visibility = .hidden
        map.isUserInteractionEnabled = interactive
        // logo 和 attribution 按 Mapbox 使用条款必须保留，别去关它们。

        context.coordinator.polylines = map.annotations.makePolylineAnnotationManager()
        context.coordinator.points = map.annotations.makePointAnnotationManager()
        return map
    }

    func updateUIView(_ map: MapView, context: Context) {
        let coord = context.coordinator
        let wgs: [CLLocationCoordinate2D] = route.map(CoordinateTransform.gcj02ToWgs84)

        // 轨迹线：整条全量替换。点数量级就几百，比维护增量简单得多。
        if wgs.count >= 2 {
            var line = PolylineAnnotation(lineCoordinates: wgs)
            line.lineColor = StyleColor(UIColor(Panora.lime))
            line.lineWidth = 5
            line.lineJoin = .round
            coord.polylines?.annotations = [line]
        } else {
            coord.polylines?.annotations = []
        }

        // 狗头：dog_pin 的尖尖在图底边，iconAnchor = .bottom 等价于 MapKit 那版的 anchor: .bottom。
        // 图按 pinWidth 先缩好再交出去，比调 iconSize 好预测（iconSize 是相对原图分辨率的倍数）。
        if let pin, let image = coord.pinImage(width: pinWidth) {
            var point = PointAnnotation(coordinate: CoordinateTransform.gcj02ToWgs84(pin))
            point.image = PointAnnotation.Image(image: image, name: "dog_pin")
            point.iconAnchor = .bottom
            coord.points?.annotations = [point]
        } else {
            coord.points?.annotations = []
        }

        if fitsRoute {
            // 只在点数变了才重套一次，不然每次 update 都重设相机。
            if wgs.count >= 2, coord.lastFittedCount != wgs.count {
                coord.lastFittedCount = wgs.count
                map.mapboxMap.setCamera(to: Self.fitCamera(for: wgs))
            }
        } else if let center {
            // 中心没变且没点重定位按钮时不动相机，否则任何无关的状态刷新都会把镜头拽回去。
            let changed: Bool = coord.lastCenter?.latitude != center.latitude
                || coord.lastCenter?.longitude != center.longitude
            if changed || coord.lastToken != recenterToken {
                coord.lastCenter = center
                coord.lastToken = recenterToken
                let target = CoordinateTransform.gcj02ToWgs84(center)
                map.mapboxMap.setCamera(to: CameraOptions(center: target, zoom: zoom))
            }
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

    final class Coordinator {
        var polylines: PolylineAnnotationManager?
        var points: PointAnnotationManager?
        var lastFittedCount: Int = 0
        var lastCenter: CLLocationCoordinate2D?
        var lastToken: Int = -1

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
    }
}
