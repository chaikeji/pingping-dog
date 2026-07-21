import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Query private var habits: [CareHabit]
    @Query private var cycles: [CareCycle]

    var body: some View {
        TabView {
            ProfileView()
                .tabItem { Label("平平", systemImage: "pawprint.fill") }
            FriendListView()
                .tabItem { Label("好朋狗", systemImage: "person.2.fill") }
            WalkHistoryView()
                .tabItem { Label("遛狗", systemImage: "map.fill") }
            PerfectDayTab()
                .tabItem { Label("完美的一天", systemImage: "sun.max.fill") }
        }
        .task { seedDefaultsIfNeeded() }
    }

    /// 首次启动播种：默认 5 个日常习惯 + 6 个周期护理项。
    private func seedDefaultsIfNeeded() {
        if habits.isEmpty {
            CareHabit.defaults().forEach { context.insert($0) }
        }
        if cycles.isEmpty {
            CareCycle.defaults().forEach { context.insert($0) }
        }
    }
}
