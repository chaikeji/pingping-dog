import SwiftUI
import SwiftData

@main
struct PingpingApp: App {
    /// 外观偏好从 AppStorage 拿；根视图统一 `.preferredColorScheme`，
    /// 各子 view 里之前那些硬编码 `.preferredColorScheme(.dark)` 已一并清掉，
    /// 不然会盖过这里的设置。
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(appearance.scheme)
        }
        .modelContainer(for: [
            DogProfile.self, DogFriend.self, WalkRoute.self, KnownRoute.self,
            CareHabit.self, DailyLog.self, CareCycle.self, HealthCondition.self,
        ])
    }
}
