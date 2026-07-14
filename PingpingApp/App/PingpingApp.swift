import SwiftUI
import SwiftData

@main
struct PingpingApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [DogProfile.self, DogFriend.self, WalkRoute.self, KnownRoute.self])
    }
}
