import SwiftUI
import SwiftData
import MapKit
import PhotosUI

/// 遛狗中（PRD §5.3）：全屏深色地图，主数据只留 距离 + 时长；
/// 顶部尿尿/拉屎/狗朋友计数 + 拍照；底部相机 | 长按结束 | 暂停/继续。
struct WalkTrackingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = WalkSessionViewModel()

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showFriendPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showShortDistanceAlert = false
    @State private var summaryRoute: WalkRoute?

    var body: some View {
        ZStack {
            Map(position: $camera) {
                UserAnnotation()
                MapPolyline(coordinates: session.locationManager.currentPoints.map(\.coordinate))
                    .stroke(AppTheme.lime, lineWidth: 5)
            }
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topCounters
                Spacer()
                bottomPanel
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { session.start() }
        .sheet(isPresented: $showFriendPicker) {
            FriendPickerSheet(selected: session.metFriendIDs) { session.toggleFriend($0) }
        }
        .alert("本次遛狗距离过短", isPresented: $showShortDistanceAlert) {
            Button("继续遛狗", role: .cancel) {}
            Button("结束（不保存）", role: .destructive) { dismiss() }
        } message: {
            Text("距离不足 100 米，记录无法保存。确定结束遛狗吗？")
        }
        .fullScreenCover(isPresented: Binding(get: { summaryRoute != nil }, set: { if !$0 { summaryRoute = nil } })) {
            if let route = summaryRoute {
                WalkSummaryView(route: route) { dismiss() }
            }
        }
    }

    // 顶部：尿尿 / 拉屎 / 狗朋友 / 拍照
    private var topCounters: some View {
        HStack(spacing: 10) {
            counterButton(emoji: "💦", label: "尿尿", count: session.peeCount) { session.addPee() }
            counterButton(emoji: "💩", label: "拉屎", count: session.poopCount) { session.addPoop() }
            counterButton(emoji: "🐕", label: "狗朋友", count: session.metFriendIDs.count) { showFriendPicker = true }
            PhotosPicker(selection: $photoItem, matching: .images) {
                VStack(spacing: 3) {
                    Text("📷").font(.title3)
                    Text("拍照").font(.caption2)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .task(id: photoItem) {
            guard let photoItem, let raw = try? await photoItem.loadTransferable(type: Data.self) else { return }
            if let ui = UIImage(data: raw), let jpeg = ui.jpegData(compressionQuality: 0.8) { session.addPhoto(jpeg) }
        }
    }

    private func counterButton(emoji: String, label: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(emoji).font(.title3)
                Text(count > 0 ? "\(label) \(count)" : label).font(.caption2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .foregroundStyle(.white)
    }

    // 底部：距离 + 时长 + 控制（相机 | 长按结束 | 暂停/继续）
    private var bottomPanel: some View {
        VStack(spacing: 18) {
            HStack(spacing: 40) {
                stat(value: String(format: "%.2f", session.distanceMeters / 1000), unit: "公里")
                stat(value: formattedElapsed, unit: "时长")
            }
            if session.isPaused {
                Text("你已暂停遛狗，点 ▶ 继续").font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 28) {
                Spacer()
                // 结束：长按才生效；<100m 先拦截
                Button {} label: {
                    Image(systemName: "stop.fill").font(.title2)
                        .frame(width: 62, height: 62)
                        .background(Circle().fill(AppTheme.coral))
                        .foregroundStyle(.white)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.8).onEnded { _ in endWalk() }
                )
                // 暂停 / 继续
                Button { session.togglePause() } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill").font(.title2)
                        .frame(width: 62, height: 62)
                        .background(Circle().fill(.ultraThinMaterial))
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            Text("长按方块结束遛狗").font(.caption2).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
    }

    private func stat(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 34, weight: .bold)).monospacedDigit().foregroundStyle(.white)
            Text(unit).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func endWalk() {
        if session.meetsMinDistance {
            if let route = session.finish(context: context) {
                summaryRoute = route
            } else {
                dismiss()
            }
        } else {
            showShortDistanceAlert = true
        }
    }

    private var formattedElapsed: String {
        let h = session.elapsedSeconds / 3600
        let m = (session.elapsedSeconds % 3600) / 60
        let s = session.elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

/// 遛狗中「狗朋友」多选弹窗：勾选本次遇到的狗朋友；含「去添加新朋友」入口。
/// 遛狗在后台继续记录、不断轨（本弹窗只是盖在遛狗中界面上的 sheet）。
private struct FriendPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DogFriend.intimacy, order: .reverse) private var friends: [DogFriend]
    let selected: Set<UUID>
    let onToggle: (UUID) -> Void

    @State private var localSelected: Set<UUID> = []
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showAdd = true } label: {
                        Label("去添加新朋友", systemImage: "plus.circle.fill")
                    }
                }
                Section("这次遇到了谁") {
                    ForEach(friends) { friend in
                        Button {
                            onToggle(friend.id)
                            if localSelected.contains(friend.id) { localSelected.remove(friend.id) }
                            else { localSelected.insert(friend.id) }
                        } label: {
                            HStack {
                                Text(friend.name).foregroundStyle(.primary)
                                Spacer()
                                if localSelected.contains(friend.id) {
                                    Image(systemName: "checkmark").foregroundStyle(AppTheme.coral)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("遇到的狗朋友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
            .sheet(isPresented: $showAdd) { AddFriendView() }
            .onAppear { localSelected = selected }
        }
    }
}

/// 本次遛狗总结页（PRD §5.3）：地图轨迹 + 距离/时长 + 尿尿/拉屎/狗朋友计数 + 照片。
struct WalkSummaryView: View {
    let route: WalkRoute
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Map {
                        MapPolyline(coordinates: route.points.map(\.coordinate))
                            .stroke(AppTheme.lime, lineWidth: 5)
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .allowsHitTesting(false)

                    HStack(spacing: 40) {
                        summaryStat(String(format: "%.2f", route.distanceMeters / 1000), "公里")
                        summaryStat(durationText, "时长")
                    }

                    HStack(spacing: 12) {
                        countChip("💦", "尿尿", route.peeCount)
                        countChip("💩", "拉屎", route.poopCount)
                        countChip("🐕", "狗朋友", route.metDogFriendIDs.count)
                    }

                    if !route.photosData.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(route.photosData.enumerated()), id: \.offset) { _, data in
                                    if let ui = UIImage(data: data) {
                                        Image(uiImage: ui).resizable().scaledToFill()
                                            .frame(width: 120, height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }.padding(.horizontal, 16)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("遛完啦")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { onDone() } }
        }
    }

    private var durationText: String {
        let h = route.durationSeconds / 3600
        let m = (route.durationSeconds % 3600) / 60
        let s = route.durationSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func summaryStat(_ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 30, weight: .bold)).monospacedDigit()
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func countChip(_ emoji: String, _ label: String, _ count: Int) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.title3)
            Text("\(count)").font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(AppTheme.stageGray, in: RoundedRectangle(cornerRadius: 14))
    }
}
