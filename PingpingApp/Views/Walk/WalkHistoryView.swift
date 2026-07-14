import SwiftUI
import SwiftData

struct WalkHistoryView: View {
    @Query(sort: \WalkRoute.startDate, order: .reverse) private var routes: [WalkRoute]
    @State private var isWalking = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(routes) { route in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(route.startDate.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            if route.isKnownRoute {
                                Label("常走路线", systemImage: "checkmark.seal.fill")
                                    .font(.caption).foregroundStyle(.green)
                            } else {
                                Label("新路线", systemImage: "sparkles")
                                    .font(.caption).foregroundStyle(.blue)
                            }
                        }
                        Text(String(format: "%.0f 米", route.distanceMeters))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("遛狗轨迹")
            .toolbar {
                Button { isWalking = true } label: { Image(systemName: "figure.walk") }
            }
            .fullScreenCover(isPresented: $isWalking) {
                NavigationStack { WalkTrackingView() }
            }
            .overlay {
                if routes.isEmpty {
                    ContentUnavailableView(
                        "还没有遛狗记录",
                        systemImage: "map",
                        description: Text("点右上角开始第一次遛狗")
                    )
                }
            }
        }
    }
}
