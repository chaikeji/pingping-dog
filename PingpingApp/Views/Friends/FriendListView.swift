import SwiftUI
import SwiftData

/// 狗朋友列表（PRD §5.2）：单列，每行头像 + 名字 + 性别/年龄 + 亲密度 + 状态角标。
/// 默认按亲密度排序，可切换（亲密度 / 年龄 / 名字）；左滑删除带二次确认。
struct FriendListView: View {
    enum SortMode: String, CaseIterable {
        case intimacy = "亲密度"
        case age = "年龄"
        case name = "名字"
    }

    @Environment(\.modelContext) private var context
    @Query private var friends: [DogFriend]
    @State private var isAdding = false
    @State private var sortMode: SortMode = .intimacy
    @State private var pendingDelete: DogFriend?

    private var sortedFriends: [DogFriend] {
        switch sortMode {
        case .intimacy: return friends.sorted { $0.intimacy > $1.intimacy }
        case .age: return friends.sorted { $0.ageText < $1.ageText }
        case .name: return friends.sorted { $0.name < $1.name }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedFriends) { friend in
                    NavigationLink(value: friend) {
                        FriendRow(friend: friend)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { pendingDelete = friend } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("狗朋友")
            .navigationDestination(for: DogFriend.self) { FriendDetailView(friend: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("排序", selection: $sortMode) {
                            ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                }
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
            .alert("删除这个狗朋友？", isPresented: .constant(pendingDelete != nil)) {
                Button("删除", role: .destructive) {
                    if let f = pendingDelete { context.delete(f) }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text(pendingDelete.map { "「\($0.name)」及其 3D 模型将被移除，无法恢复。" } ?? "")
            }
        }
    }
}

/// 列表头像：就用照片。3D 模型只在详情页展示。
private struct FriendAvatar: View {
    let friend: DogFriend
    let size: CGFloat

    var body: some View {
        Group {
            if let data = friend.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10).fill(.gray.opacity(0.2))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct FriendRow: View {
    let friend: DogFriend

    /// 原来是 44，加倍到 88：一行的高度跟着缩略图走，正好是原来两行。
    private static let avatarSize: CGFloat = 88

    var body: some View {
        HStack(spacing: 12) {
            FriendAvatar(friend: friend, size: Self.avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label("\(friend.intimacy)", systemImage: "heart.fill")
                .font(.caption).foregroundStyle(AppTheme.coral)
                .labelStyle(.titleAndIcon)
            statusBadge
        }
    }

    private var subtitle: String {
        [friend.gender, friend.ageText].filter { !$0.isEmpty }.joined(separator: " · ")
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
