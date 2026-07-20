import Foundation
import CoreHaptics

/// 持续震动。`UIImpactFeedbackGenerator` 只能给离散的「一下」，
/// 想要按住期间一直震，只能走 CoreHaptics 的 `.hapticContinuous` 事件。
///
/// 部署目标是 iOS 18，能装的机型都带 Taptic Engine，所以没写降级到定时器的兜底；
/// 但用户可能在系统设置里关掉了触感反馈，`supportsHaptics` 那道判断不能省。
@MainActor
final class ContinuousHaptic {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    /// 起震。duration 给足按住的总时长，中途松手调 stop() 提前掐掉。
    func start(duration: TimeInterval, intensity: Float = 0.6, sharpness: Float = 0.4) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil {
                engine = try CHHapticEngine()
                engine?.isAutoShutdownEnabled = true
            }
            try engine?.start()
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: 0,
                duration: duration
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            player = try engine?.makeAdvancedPlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            // 震不起来就算了。触感失败绝不能影响到「结束遛狗」这件事本身。
            player = nil
        }
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop()
    }
}
