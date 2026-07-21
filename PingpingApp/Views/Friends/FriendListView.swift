import SwiftUI
import SwiftData

/// 狗朋友列表（PRD §5.2，Panora 深色玻璃风 Batch 4）：
/// 大标题 + 亲密度排序 + 荧光绿「+」；单列行卡（102 头像 + 名字副标 + 亲密度药丸 + 状态角标）。
/// 左滑删除带二次确认（保留原逻辑）。
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
            ZStack {
                Panora.appBackground.ignoresSafeArea()

                if friends.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            header
                            ForEach(sortedFriends) { friend in
                                NavigationLink(value: friend) {
                                    FriendRow(friend: friend)
                                }
                                .buttonStyle(.plain)
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                                // 保留左滑删除 —— NavigationLink 里不能直接挂 swipeActions，
                                // 用 contextMenu 兜底：长按弹删除。真机上再加真的 swipe 需要 List。
                                .contextMenu {
                                    Button(role: .destructive) {
                                        pendingDelete = friend
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationDestination(for: DogFriend.self) { FriendDetailView(friend: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $isAdding) { AddFriendView() }
            .alert("删除这个好朋狗？", isPresented: .constant(pendingDelete != nil)) {
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

    // MARK: - 顶部（大标题 + 排序 + 加号）

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Menu {
                    Picker("排序", selection: $sortMode) {
                        ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15))
                        .foregroundStyle(Panora.textSecondary)
                        .frame(width: 22, height: 22)
                }
                Text("好朋狗")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Panora.textPrimary)
                Spacer()
                Button { isAdding = true } label: {
                    Text("+")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Panora.lime)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Panora.lime.opacity(0.16)))
                        .overlay(Circle().strokeBorder(Panora.lime.opacity(0.40), lineWidth: 0.5))
                }
            }
            Text("按\(sortMode.rawValue)排序 · \(friends.count) 位狗友")
                .font(.system(size: 12))
                .foregroundStyle(Panora.textMuted)
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 20) {
            Text("🐕")
                .font(.system(size: 46))
                .frame(width: 96, height: 96)
                .background(Panora.darkCard, in: RoundedRectangle(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Panora.cardBorder, lineWidth: 0.5)
                )
                .opacity(0.85)
            VStack(spacing: 8) {
                Text("还没有好朋狗")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Panora.textPrimary)
                Text("点右上角 + 认识第一个好朋狗\n拍张照，收藏成可旋转的 3D 小模型")
                    .font(.system(size: 14))
                    .foregroundStyle(Panora.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            Button { isAdding = true } label: {
                Text("＋ 认识新朋友")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Panora.ink)
                    .padding(.horizontal, 26).padding(.vertical, 13)
                    .background(Panora.lime, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Panora.lime.opacity(0.30), radius: 12, y: 6)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - 行卡

private struct FriendRow: View {
    let friend: DogFriend
    private static let avatarSize: CGFloat = 102

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Panora.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Panora.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                intimacyPill
            }
            Spacer(minLength: 0)
            statusBadge
        }
        .padding(12)
        .frame(height: 126)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panoraCard()
    }

    private var avatar: some View {
        Group {
            if let data = friend.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.06))
                    Text("🐕")
                        .font(.system(size: 34))
                        .opacity(0.45)
                }
            }
        }
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var subtitle: String {
        let parts = [friend.gender, friend.ageText].filter { !$0.isEmpty }
        return parts.isEmpty ? "未填" : parts.joined(separator: " · ")
    }

    private var intimacyPill: some View {
        HStack(spacing: 5) {
            Text("♥")
                .font(.system(size: 12))
                .foregroundStyle(Panora.coral)
            Text("\(friend.intimacy)")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Panora.coral)
            Text("亲密度")
                .font(.system(size: 11))
                .foregroundStyle(Panora.coral.opacity(0.8))
        }
        .padding(.horizontal, 11).padding(.vertical, 4)
        .background(Panora.coral.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch friend.modelStatus {
        case .ready:
            badge(icon: "🧊", text: "3D",
                  fg: Color(hex: 0x5BC47A), bg: Panora.greenOK.opacity(0.16))
        case .processing, .queued:
            badge(icon: "◔", text: "生成中",
                  fg: Panora.textSecondary, bg: Color.white.opacity(0.08))
        case .failed:
            badge(icon: "⚠️", text: "失败",
                  fg: Panora.coral, bg: Panora.coral.opacity(0.16))
        case .notStarted:
            EmptyView()
        }
    }

    private func badge(icon: String, text: String, fg: Color, bg: Color) -> some View {
        HStack(spacing: 5) {
            Text(icon).font(.system(size: 11))
            Text(text).font(.system(size: 10.5)).foregroundStyle(fg)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(bg, in: Capsule())
    }
}
