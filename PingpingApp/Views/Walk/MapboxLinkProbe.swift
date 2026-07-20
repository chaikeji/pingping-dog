import MapboxMaps

/// 临时文件，只为第一轮 CI 验证三件事：SPM 能解析 Mapbox 私有包、二进制能链接、
/// Swift 能 import 这个模块。刻意只写一个 typealias —— 不构造任何对象，
/// 避免把「初始化器签名记错」混进这一轮的失败原因里。
///
/// 第二轮真正接入地图（UIViewRepresentable 包 MapView）之后，删掉这个文件。
private typealias MapboxLinkCheck = MapboxMaps.MapView
