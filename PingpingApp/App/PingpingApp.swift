import SwiftUI
import SwiftData
import SDWebImage
import SDWebImageWebPCoder

@main
struct PingpingApp: App {
    /// 外观偏好从 AppStorage 拿；根视图统一 `.preferredColorScheme`，
    /// 各子 view 里之前那些硬编码 `.preferredColorScheme(.dark)` 已一并清掉，
    /// 不然会盖过这里的设置。
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    init() {
        // 动画 WebP 不是 UIImage 原生动画格式，启动时只注册一次解码器。
        // 文件仍完全在 App 本地，不会产生网络请求。
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(appearance.scheme)
        }
        .modelContainer(for: [
            DogProfile.self, DogFriend.self, WalkRoute.self, KnownRoute.self,
            CareHabit.self, DailyLog.self, CareCycle.self, HealthCondition.self,
            VaccinationRecord.self,
        ])
    }
}
