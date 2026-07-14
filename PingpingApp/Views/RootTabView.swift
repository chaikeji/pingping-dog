import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            ProfileView()
                .tabItem { Label("平平档案", systemImage: "pawprint.fill") }
            FriendListView()
                .tabItem { Label("狗朋友", systemImage: "person.2.fill") }
            WalkHistoryView()
                .tabItem { Label("遛狗轨迹", systemImage: "map.fill") }
        }
    }
}
