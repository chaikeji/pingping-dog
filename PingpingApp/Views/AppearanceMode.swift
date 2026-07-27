import SwiftUI

/// 白天 / 夜间模式选择。持久化到 UserDefaults 键 `appearanceMode`；
/// 根视图（PingpingApp）读它 → `.preferredColorScheme(...)`，
/// 设置页（PerfectDaySettingsView）里给 Picker 绑定同一个 AppStorage key。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "白天"
        case .dark: return "夜间"
        }
    }

    /// `nil` = 跟随系统；SwiftUI 的 `.preferredColorScheme(nil)` 就等于放手让系统决定。
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static let storageKey = "appearanceMode"
}
