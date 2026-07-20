import SwiftUI
import SwiftData
import MapKit
import PhotosUI
import UIKit

/// 遛狗中（PRD §5.3，Panora Batch 1 §②）：
/// 全屏深色地图 + 荧光绿轨迹线 + 🐶 定位；顶部玻璃胶囊「遛狗中 · GPS ▮▮▮」；
/// 底部黑色渐变面板：超大 km 数、三栏统计（尿尿/时间/拉屎）、4 个控制钮（拍照 / 红方停 / 绿圆继续 / 狗朋友）。
struct WalkTrackingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var session = WalkSessionViewModel()

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showFriendPicker = false
    @State private var showShortDistanceAlert = false
    @State private var summaryRoute: WalkRoute?
    @State private var showPhotoOptions = false

    var body: some View {
        ZStack {
            Map(position: $camera) {
                if let last = session.locationManager.currentPoints.last {
                    Annotation("", coordinate: last.coordinate) {
                        Text("🐶").font(.system(size: 34)).shadow(radius: 3)
                    }
                } else {
                    UserAnnotation()
                }
                MapPolyline(coordinates: session.locationManager.currentPoints.map(\.coordinate))
                    .stroke(Panora.lime, lineWidth: 5)
            }
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()
            .colorScheme(.dark)

            VStack(spacing: 0) {
                topStatusPill
                if session.locationInsufficient { locationBanner }
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
        .photoSourcePicker(isPresented: $showPhotoOptions) { session.addPhoto($0) }
    }

    // MARK: - 顶部：玻璃胶囊「遛狗中 · GPS ▮▮▮」

    private var topStatusPill: some View {
        HStack(spacing: 10) {
            Text(session.isPaused ? "已暂停" : "遛狗中")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Panora.textPrimary)
            Text("·").foregroundStyle(Panora.textSecondary)
            HStack(spacing: 3) {
                Text("GPS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Panora.textSecondary)
                gpsBars
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .panoraGlass(cornerRadius: 999)
        .padding(.top, 8)
    }

    /// 三格信号条：满信号 = 3 格绿，弱信号根据授权状态降级。
    private var gpsBars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            let active: Int = session.locationInsufficient ? 1 : 3
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < active ? Panora.systemGreen : Color.white.opacity(0.25))
                    .frame(width: 3, height: CGFloat(4 + i * 3))
            }
        }
    }

    // MARK: - 定位权限降级提示

    private var locationBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash.fill")
            Text("定位权限不足，锁屏/后台可能断轨").font(.caption)
            Spacer()
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.caption.bold())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .panoraGlass(cornerRadius: 12)
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.top, 8)
    }

    // MARK: - 下：黑色渐变面板

    private var bottomPanel: some View {
        VStack(spacing: 18) {
            distanceBlock
            statsRow
            controlsRow
        }
        .padding(.top, 20)
        .padding(.bottom, 30)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(bottomFadeBackground)
    }

    private var bottomFadeBackground: some View {
        Panora.bottomFade
            .frame(height: 360)
            .allowsHitTesting(false)
    }

    private var distanceBlock: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.2f", session.distanceMeters / 1000))
                .font(.system(size: 84, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Panora.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("公里")
                .font(.system(size: 14))
                .foregroundStyle(Panora.textSecondary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(icon: "💦", label: "尿尿", value: "\(session.peeCount)") { session.addPee() }
            statCell(icon: nil, label: "时间", value: formattedElapsed, action: nil)
            statCell(icon: "💩", label: "拉屎", value: "\(session.poopCount)") { session.addPoop() }
        }
    }

    private func statCell(icon: String?, label: String, value: String, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Panora.textPrimary)
                HStack(spacing: 4) {
                    if let icon { Text(icon).font(.system(size: 12)) }
                    Text(label)
                        .font(.system(size: 14))
                        .foregroundStyle(Panora.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private var controlsRow: some View {
        HStack(spacing: 0) {
            controlIconButton(system: "camera") { showPhotoOptions = true }
            Spacer()
            // 长按 0.8s 才结束；<100m 弹拦截。
            Button {} label: {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Panora.systemRed)
                    .frame(width: 42, height: 42)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.8).onEnded { _ in endWalk() }
            )
            Spacer()
            // 暂停 / 继续切换。原型要求「无三角」，按暂停态显示三角提示可恢复。
            Button { session.togglePause() } label: {
                Circle()
                    .fill(Panora.systemGreen)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Group {
                            if session.isPaused {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    )
            }
            Spacer()
            controlIconButton(system: "pawprint") { showFriendPicker = true }
        }
        .padding(.horizontal, 20)
    }

    private func controlIconButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Panora.textPrimary)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
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
                                    Image(systemName: "checkmark").foregroundStyle(Panora.coral)
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

/// 本次遛狗总结页（PRD §5.3，Panora Batch 1 §③）：
/// 地图卡（圆角 18）→ 大号 距离 / 时长 → 尿尿 / 拉屎 / 狗朋友 三张实心深色计数卡 → 照片横排缩略。
struct WalkSummaryView: View {
    let route: WalkRoute
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Panora.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        Map {
                            MapPolyline(coordinates: route.points.map(\.coordinate))
                                .stroke(Panora.lime, lineWidth: 5)
                        }
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .allowsHitTesting(false)
                        .padding(.horizontal, 16)

                        HStack(spacing: 40) {
                            summaryStat(String(format: "%.2f", route.distanceMeters / 1000), "公里")
                            summaryStat(durationText, "时长")
                        }
                        .padding(.top, 4)

                        HStack(spacing: 12) {
                            countChip("💦", "尿尿", route.peeCount)
                            countChip("💩", "拉屎", route.poopCount)
                            countChip("🐕", "狗朋友", route.metDogFriendIDs.count)
                        }
                        .padding(.horizontal, 16)

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
                    .padding(.vertical, 12)
                }
                .scrollContentBackground(.hidden)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("遛完啦")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
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
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Panora.textPrimary)
            Text(unit)
                .font(.system(size: 12))
                .foregroundStyle(Panora.textSecondary)
        }
    }

    private func countChip(_ emoji: String, _ label: String, _ count: Int) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.system(size: 20))
            Text("\(count)")
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Panora.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Panora.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .panoraCard(cornerRadius: 14)
    }
}
