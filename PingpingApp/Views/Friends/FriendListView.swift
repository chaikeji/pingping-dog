import SwiftUI
import SwiftData

struct FriendListView: View {
    @Query(sort: \DogFriend.createdAt, order: .reverse) private var friends: [DogFriend]
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(friends) { friend in
                    NavigationLink(value: friend) {
                        FriendRow(friend: friend)
                    }
                }
            }
            .navigationTitle("狗朋友")
            .navigationDestination(for: DogFriend.self) { FriendDetailView(friend: $0) }
            .toolbar {
                Button { isAdding = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $isAdding) { AddFriendView() }
            .overlay {
                if friends.isEmpty {
                    ContentUnavailableView(
                        "还没有狗朋友",
                        systemImage: "person.2",
                        description: Text("点右上角 + 认识第一个狗朋友")
                    )
                }
            }
        }
    }
}

private struct FriendRow: View {
    let friend: DogFriend

    var body: some View {
        HStack {
            if let data = friend.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFill()
                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.2)).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading) {
                Text(friend.name).font(.headline)
                Text(friend.breed).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch friend.modelStatus {
        case .ready: Image(systemName: "cube.fill").foregroundStyle(.green)
        case .processing, .queued: ProgressView()
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .notStarted: EmptyView()
        }
    }
}
