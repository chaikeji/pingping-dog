import SwiftUI

/// 设计 token（对应 PRD §6 / HTML 预览里的 CSS 变量）。全 App 统一从这里取色，别散写 hex。
enum AppTheme {
    static let lime = Color(hex: 0xCDEC2E)      // 品牌主色 / 强调
    static let ink = Color(hex: 0x14150C)       // 主文字 / 深色底
    static let coral = Color(hex: 0xFF6B45)     // 次强调 / 扣分
    static let amber = Color(hex: 0xF4B740)     // 徽章渐变
    static let inkSub = Color(hex: 0x6B6D5E)    // 辅助文字
    static let greenOK = Color(hex: 0x3F9D54)   // 加分 / 成功

    /// 首页背景：浅色 #d9d9d3 / 深色 #2a2b26，随系统主题切换。
    static let stageGray = Color(light: 0xD9D9D3, dark: 0x2A2B26)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// 随浅色/深色主题切换的动态色。
    init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
