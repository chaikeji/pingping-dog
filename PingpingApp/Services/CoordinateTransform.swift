import Foundation
import CoreLocation

/// 火星坐标（GCJ-02）→ 真实坐标（WGS-84）。
///
/// ⚠️ 目前**没有任何地方调用它**，是故意留着的。
/// 真机验证的结论跟下面这段推理相反：同时画「转换后」和「未转换」两个点，
/// 落在真实位置上的是**未转换**的那个 —— 说明 Mapbox 给这台设备的底图本来就跟 GCJ-02 对齐。
/// 所以 PanoraMapView 现在直接用 CLLocation 的原值。
/// 留着这个文件是因为这个结论跟 Mapbox 全球版的公开行为不一致，换区域/换 endpoint 可能又要用。
///
/// 为什么必须做：中国大陆境内 iOS 的 CLLocation 返回的是 GCJ-02 加偏坐标，
/// 而 Mapbox 的底图瓦片是 WGS-84。直接把 CLLocation 的经纬度丢给 Mapbox，
/// 狗头就会落在真实位置几百米外 —— 这正是之前那个「差 300m」的量级。
/// MapKit 之所以看着是对的，是因为苹果的中国底图也是 GCJ-02，两边偏一样多，抵消了；
/// 换成 Mapbox 就抵消不掉了，所以这个转换不是优化，是换图必带的。
///
/// 只在「交给 Mapbox 画」的那一刻转。存进 SwiftData 的轨迹点保持原样（GCJ-02），
/// 否则老记录和新记录的语义会对不上；距离计算用哪套坐标差异可忽略。
enum CoordinateTransform {
    private static let a: Double = 6_378_245.0          // 克拉索夫斯基椭球长半轴
    private static let ee: Double = 0.006_693_421_622_965_943

    /// 粗略国境盒子。境外（以及港澳台，它们本来就是 WGS-84）不加偏，原样返回。
    private static func isOutOfChina(lat: Double, lon: Double) -> Bool {
        lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271
    }

    static func gcj02ToWgs84(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(c),
              !isOutOfChina(lat: c.latitude, lon: c.longitude) else { return c }
        let (dLat, dLon) = offset(lat: c.latitude, lon: c.longitude)
        // 严格说偏移量该在 WGS-84 点上算，这里在 GCJ 点上算是一阶近似。
        // 误差量级几米，画轨迹足够；要更准得迭代，不值当。
        return CLLocationCoordinate2D(latitude: c.latitude - dLat, longitude: c.longitude - dLon)
    }

    private static func offset(lat: Double, lon: Double) -> (Double, Double) {
        let x: Double = lon - 105.0
        let y: Double = lat - 35.0
        var dLat: Double = transformLat(x: x, y: y)
        var dLon: Double = transformLon(x: x, y: y)
        let radLat: Double = lat / 180.0 * .pi
        let s: Double = sin(radLat)
        let magic: Double = 1 - ee * s * s
        let sqrtMagic: Double = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        return (dLat, dLon)
    }

    // 下面两个是 GCJ-02 的公开经验多项式。式子拆成多行 += 并且每步都写死 Double，
    // 是为了别让 Swift 类型检查器在一个长表达式上超时（这仓库里踩过）。
    private static func transformLat(x: Double, y: Double) -> Double {
        var ret: Double = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y
        ret += 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(x: Double, y: Double) -> Double {
        var ret: Double = 300.0 + x + 2.0 * y + 0.1 * x * x
        ret += 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}
