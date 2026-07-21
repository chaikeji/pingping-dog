import SwiftUI
import SwiftData
import CoreLocation
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

    /// 点一次「回到我的位置」就 +1，逼 PanoraMapView 重设一次相机（中心没变时也生效）。
    @State private var recenterToken = 0
    @State private var showFriendPicker = false

    /// 只有距离不够时才拦一道确认。距离够就按满 3 秒直接结束、进总结页 ——
    /// 环转满本身已经是确认了，再多一步是多余的。
    @State private var showShortDistanceAlert = false
    @State private var summaryRoute: WalkRoute?
    @State private var showPhotoOptions = false

    /// 按住红方块结束遛狗：环上的红色进度 0…1，按满 1.7 秒才真的结束。
    @State private var holdProgress: CGFloat = 0
    /// 方块外那圈红色光晕的胀开进度 0…1。故意比 holdProgress 快，先涨满再等环转满。
    @State private var innerGrow: CGFloat = 0
    @State private var isHoldingEnd = false
    /// 3 秒后触发结束的那个延时任务。中途松手要能取消，所以得留着句柄。
    @State private var holdTask: DispatchWorkItem?
    /// 按住期间的持续震动。用 CoreHaptics，不是一串离散的 impact。
    @State private var haptic = ContinuousHaptic()

    var body: some View {
        ZStack {
            // 相机跟着最后一个点走：center 每收到新定位就变，PanoraMapView 会自动跟随。
            PanoraMapView(
                route: session.locationManager.currentPoints.map(\.coordinate),
                pin: session.locationManager.currentPoints.last?.coordinate,
                center: session.locationManager.currentPoints.last?.coordinate,
                zoom: 16.5,
                recenterToken: recenterToken,
                pitch: 45
            )
            .ignoresSafeArea()

            // 顶 / 底黑色渐变分别独立铺满，比之前更浓；给状态条 & 底部面板托底。
            VStack(spacing: 0) {
                topFade
                Spacer()
                bottomFade
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topStatusPill
                if session.locationInsufficient { locationBanner }
                Spacer()
                // 按住红方块时浮在地图下沿的提示，白底黑字（白 = 下面公里数的颜色）。
                if isHoldingEnd {
                    holdHintPopup
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
                bottomPanel
            }
            .animation(.easeOut(duration: 0.12), value: isHoldingEnd)

            // 自定义居中弹窗（系统 .alert 位置控制不了；我们要屏幕正中）。
            if showShortDistanceAlert {
                shortDistanceDialog
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(.easeOut(duration: 0.144), value: showShortDistanceAlert)
        .preferredColorScheme(.dark)
        .onAppear { session.start() }
        .sheet(isPresented: $showFriendPicker) {
            FriendPickerSheet(selected: session.metFriendIDs) { session.toggleFriend($0) }
        }
        .fullScreenCover(isPresented: Binding(get: { summaryRoute != nil }, set: { if !$0 { summaryRoute = nil } })) {
            if let route = summaryRoute {
                WalkSummaryView(route: route) { dismiss() }
            }
        }
        .photoSourcePicker(isPresented: $showPhotoOptions) { session.addPhoto($0) }
    }

    // MARK: - 距离过短弹窗（居中）

    private var shortDistanceDialog: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { showShortDistanceAlert = false }
            VStack(spacing: 14) {
                Text("本次遛狗距离过短")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Panora.textPrimary)
                Text("记录无法保存，确定结束本次遛狗吗？")
                    .font(.system(size: 14))
                    .foregroundStyle(Panora.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        showShortDistanceAlert = false
                        dismiss()
                    } label: {
                        Text("结束")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Panora.systemRed)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                    }
                    Button {
                        showShortDistanceAlert = false
                    } label: {
                        Text("继续遛狗")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Panora.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Panora.lime))
                    }
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 300)
            .panoraCard(cornerRadius: 20)
            // 整体比屏幕正中再高 60pt（只挪卡片，不挪背后的遮罩）。
            .offset(y: -60)
        }
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

    // MARK: - 顶 / 底渐变（各自独立铺满，不跟面板绑死，直到 safe area 边缘都黑）

    private var topFade: some View {
        LinearGradient(
            colors: [Color.black.opacity(0.7), Color.black.opacity(0.35), Color.clear],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 200)
    }

    private var bottomFade: some View {
        LinearGradient(
            colors: [Color.clear, Color.black.opacity(0.55), Color.black.opacity(0.92)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 420)
    }

    // MARK: - 下：内容面板（透明，托底靠外层的 bottomFade）

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
    }

    /// 公里数 + 「公里」标签 + 定位按钮（右侧）。
    private var distanceBlock: some View {
        ZStack {
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
            // 「回到自己位置」按钮：贴右，视觉上跟公里数是一行。
            HStack {
                Spacer()
                recenterButton
            }
        }
    }

    private var recenterButton: some View {
        Button {
            recenterToken += 1
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Panora.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .overlay(Circle().strokeBorder(Panora.glassBorder, lineWidth: 0.5))
        }
    }

    /// 三栏：💦 尿尿(左推)｜时间(居中，不换行，字号不变)｜💩 拉屎(右推)。
    private var statsRow: some View {
        HStack(spacing: 8) {
            statTapCell(icon: "💦", label: "尿尿", value: "\(session.peeCount)") { session.addPee() }
                .frame(maxWidth: .infinity)
            statContent(icon: nil, label: "时间", value: formattedElapsed)
                .fixedSize(horizontal: true, vertical: false)
            statTapCell(icon: "💩", label: "拉屎", value: "\(session.poopCount)") { session.addPoop() }
                .frame(maxWidth: .infinity)
        }
    }

    private func statTapCell(icon: String?, label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            statContent(icon: icon, label: label, value: value)
        }
        .buttonStyle(.plain)
    }

    private func statContent(icon: String?, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Panora.textPrimary)
                .lineLimit(1)
            HStack(spacing: 4) {
                if let icon { Text(icon).font(.system(size: 12)) }
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(Panora.textSecondary)
            }
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 0) {
            controlIconButton(system: "camera") { showPhotoOptions = true }
            Spacer()
            middleControl
                .animation(.easeOut(duration: 0.144), value: session.isPaused)
            Spacer()
            controlIconButton(system: "pawprint") { showFriendPicker = true }
        }
        .padding(.horizontal, 20)
    }

    /// 遛狗中默认只露一个白杠「暂停」按钮；点它暂停 → 展开红方（长按结束）+ 绿三角（继续）。
    @ViewBuilder
    private var middleControl: some View {
        if session.isPaused {
            // 红在左、绿在右。红方块视觉边长跟绿三角字形对齐（都 30），间距再拉开一倍（30 → 60）。
            HStack(spacing: 60) {
                endHoldButton
                // 继续（绿三角）：点即恢复。裸三角，不套绿色圆底。frame 保持 34 给足 tap 区。
                Button { session.togglePause() } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Panora.systemGreen)
                        .frame(width: 34, height: 34)
                }
            }
        } else {
            // 遛狗中：白色暂停条。点即暂停并展开红/绿控制。
            Button { session.togglePause() } label: {
                HStack(spacing: 5) {
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 4, height: 20)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 4, height: 20)
                }
                .frame(width: 42, height: 42)
            }
        }
    }

    // MARK: - 结束遛狗：按住 1.7 秒，环转满才生效

    /// 按住时三件事同时发生：方块由红转白 → 白方块外面胀出一圈红色光晕（快，0.72s 涨满）
    /// → 最外层空心环上的红色顺时针转满（慢，1.7s，转满才真的结束）。
    /// 光晕和环都走 overlay / 视觉溢出，不占布局，不会把左右两个钮挤开。
    private var endHoldButton: some View {
        ZStack {
            // 红色光晕：从方块边缘往外胀，涨到 45 就停 —— 外环是 55，中间留 5pt 的缝，不贴上去。
            Circle()
                .fill(Panora.systemRed)
                .frame(width: 21 + 24 * innerGrow, height: 21 + 24 * innerGrow)
                .opacity(isHoldingEnd ? 1 : 0)
            // 方块本体：按住的瞬间由红转白，好让外面那圈红显出来。
            RoundedRectangle(cornerRadius: 4)
                .fill(isHoldingEnd ? Color.white : Panora.systemRed)
                .frame(width: 21, height: 21)
        }
        // 布局尺寸钉死在 21：光晕和外环都只是视觉溢出，不许把左右两个钮挤开。
        .frame(width: 21, height: 21)
        // 这里刻意不挂 .animation(value: isHoldingEnd)：变白、光晕和外环的「出现」都要求是瞬时的。
        // 会动的只有尺寸和进度本身 —— 那两个由 innerGrow / holdProgress 各自的 withAnimation 驱动。
        .overlay {
            ZStack {
                // 底环：让「有个环在这儿」这件事在红色转起来之前就看得见。
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 3)
                // 进度：从 12 点方向开始（trim 默认从 3 点，所以整体转 -90°）。
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Panora.systemRed, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 55, height: 55)
            .opacity(isHoldingEnd ? 1 : 0)
        }
        // 用 DragGesture(minimumDistance: 0) 而不是 LongPressGesture：
        // 我们要的是「按下就开始、松手就取消」，LongPressGesture 只在达成时给一次回调，
        // 中途松手拿不到事件，环就停在半路了。
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHold() }
                .onEnded { _ in cancelHold() }
        )
    }

    /// 按住时浮在地图下沿的提示。白底（= 公里数的颜色）黑字。
    private var holdHintPopup: some View {
        Text("长按结束运动")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Panora.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Panora.textPrimary, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    private func beginHold() {
        // onChanged 会连续触发，这里要幂等，否则动画和定时器会被反复重置、永远转不满。
        guard !isHoldingEnd else { return }
        isHoldingEnd = true
        holdProgress = 0
        innerGrow = 0
        // 环：1.7 秒线性转满，跟真正触发结束的那个延时严格对齐。
        withAnimation(.linear(duration: 1.7)) { holdProgress = 1 }
        // 光晕：0.72 秒就涨满，明显快于环，先胀开再等环追上来。
        withAnimation(.easeOut(duration: 0.72)) { innerGrow = 1 }

        // 手指落下先来一记 impact 当起手 —— CoreHaptics 引擎启动有几十毫秒延迟，
        // 少了这一下会觉得「按下去没反应」。随后接上 1.7 秒的持续震。
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        haptic.start(duration: 1.7)

        let task = DispatchWorkItem {
            // 转满就彻底停震：接下来要么进总结页、要么弹「距离过短」，
            // 那两个界面上再来一记震动只会让人以为又触发了什么。
            stopHaptics()
            isHoldingEnd = false
            holdProgress = 0
            innerGrow = 0
            endWalk()
        }
        holdTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: task)
    }

    private func stopHaptics() {
        haptic.stop()
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        stopHaptics()
        guard isHoldingEnd else { return }
        isHoldingEnd = false
        withAnimation(.easeOut(duration: 0.16)) {
            holdProgress = 0
            innerGrow = 0
        }
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

    /// 环转满后：距离够就直接落库进总结页；不够才拦一道确认框。
    private func endWalk() {
        guard session.meetsMinDistance else {
            showShortDistanceAlert = true
            return
        }
        if let route = session.finish(context: context) {
            summaryRoute = route
        } else {
            dismiss()
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
            .navigationTitle("遇到的好朋狗")
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
                        // 静态轨迹卡：不跟随、不给手势，自动把整条轨迹装进画面。
                        PanoraMapView(
                            route: route.points.map(\.coordinate),
                            interactive: false,
                            fitsRoute: true
                        )
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
                            countChip("🐕", "狗友", route.metDogFriendIDs.count)
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
