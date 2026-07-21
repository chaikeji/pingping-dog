import SwiftUI

/// Panora 深色玻璃风的 token（Batch 1：仅遛狗模块用）。
/// 别在其它 tab 引用，等到 Batch 2/3 再逐块迁移；主 `AppTheme` 暂不动。
enum Panora {
    // MARK: - 单色

    static let ink = Color(hex: 0x14150C)
    static let lime = Color(hex: 0xCDEC2E)
    static let coral = Color(hex: 0xFF6B45)
    static let greenOK = Color(hex: 0x3F9D54)
    /// 里程卡柱状 & 数值主色。
    static let blueChart = Color(hex: 0x35A6DD)
    /// 月历方格：当天有效遛狗 1 次的浅绿。
    static let greenCalendarLight = Color(hex: 0x4ADE80)
    /// 月历方格：当天有效遛狗 2 次及以上的深绿。
    static let greenCalendarDark = Color(hex: 0x15803D)

    /// 遛狗中的系统级红/绿：停止 / 继续。
    static let systemRed = Color(hex: 0xFF3B30)
    static let systemGreen = Color(hex: 0x34C759)

    // MARK: - 卡片 & 玻璃描边

    static let cardBorder = Color.white.opacity(0.08)
    static let cardHighlight = Color.white.opacity(0.06)   // inset 0 1px white 6%
    static let glassBorder = Color.white.opacity(0.18)
    static let dividerOnGlass = Color.white.opacity(0.12)

    // MARK: - 文字

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textMuted = Color.white.opacity(0.40)
    static let textFaint = Color.white.opacity(0.30)

    // MARK: - 渐变

    /// App 底：165° #0D0E10 → #121319 → #221C14 → #2E2410（对应 README 的 4-stop 值）。
    static let appBackground: LinearGradient = {
        let start = UnitPoint(x: 0.371, y: 0.017) // 165° 起点（CSS 角）
        let end = UnitPoint(x: 0.629, y: 0.983)
        return LinearGradient(
            stops: [
                .init(color: Color(hex: 0x0D0E10), location: 0.00),
                .init(color: Color(hex: 0x121319), location: 0.45),
                .init(color: Color(hex: 0x221C14), location: 0.82),
                .init(color: Color(hex: 0x2E2410), location: 1.00),
            ],
            startPoint: start,
            endPoint: end
        )
    }()

    /// 实心深色卡：180° #1B1D22 → #16171B。
    static let darkCard = LinearGradient(
        colors: [Color(hex: 0x1B1D22), Color(hex: 0x16171B)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 遛狗中下半黑色渐变面板：透明 → #0A0B0D。
    static let bottomFade = LinearGradient(
        colors: [Color.clear, Color(hex: 0x0A0B0D)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - 复用样式

extension View {
    /// 实心深色卡背景（Panora）+ 描边。
    func panoraCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(Panora.darkCard, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Panora.cardBorder, lineWidth: 0.5)
            )
    }

    /// 玻璃浮层（Panora）：只用在有地图/照片/彩色内容的悬浮层上。
    func panoraGlass(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Panora.glassBorder, lineWidth: 0.5)
            )
    }
}
