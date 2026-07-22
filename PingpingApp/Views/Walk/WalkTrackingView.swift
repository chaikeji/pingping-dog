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
                peeSpots: session.peeSpots.map(\.coordinate),
                poopSpots: session.poopSpots.map(\.coordinate),
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

    /// 三栏：niaoniao 大图(左推)｜时间(居中，不换行，字号不变)｜bianbian 大图(右推)。
    /// 两侧图标替代了原来大号数字的位置；计数缩成小徽章浮在图标右上角。
    private var statsRow: some View {
        HStack(spacing: 8) {
            iconCountCell(asset: "niaoniao", count: session.peeCount) { session.addPee() }
                .frame(maxWidth: .infinity)
            timeCell
                .fixedSize(horizontal: true, vertical: false)
            iconCountCell(asset: "bianbian", count: session.poopCount) { session.addPoop() }
                .frame(maxWidth: .infinity)
        }
    }

    /// 图标 + 右上角小徽章的一格。整格可点击 → +1。
    /// 图标尺寸跟时间那格的 30pt 数字视觉重量对齐（时间那格总高 ≈ 数字 30 + 间距 4 + 标签 14）。
    private func iconCountCell(asset: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(height: 48)
                .overlay(alignment: .topTrailing) {
                    Text("\(count)")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Panora.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        // 右上角外挂一点，避免徽章跟图标叠得糊在一起
                        .offset(x: 10, y: -4)
                }
        }
        .buttonStyle(.plain)
    }

    /// 中间时间格：保留原来的「大号数字 + 小字标签」结构。
    private var timeCell: some View {
        VStack(spacing: 4) {
            Text(formattedElapsed)
                .font(.system(size: 30, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Panora.textPrimary)
                .lineLimit(1)
            Text("时间")
                .font(.system(size: 14))
                .foregroundStyle(Panora.textSecondary)
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

/// 本次遛狗总结页（PRD §5.3，Panora Batch 1 §③，交接稿 design_handoff_summary/README.md）：
/// 顶栏日期 → 大标题 (「遛完啦，今天走了 X.XX 公里」) → 轨迹卡（起终点） →
/// 数据条（左上角狗朋友头像叠放） → 3D 照片流 → 底部「保存这次遛狗」CTA。
///
/// 页面本身**不入库**：结束遛狗时 session.finish() 已经存了。
/// 底部大按钮 = 关闭此页回列表，跟原来右上角「完成」等价。
struct WalkSummaryView: View {
    let route: WalkRoute
    let onDone: () -> Void

    /// 遇到的狗朋友：从库里按 metDogFriendIDs 反查取头像。
    @Query private var allFriends: [DogFriend]
    /// 本次没照片时，去所有遛狗记录里找一张最近的竖版照片当占位。
    @Query(sort: \WalkRoute.startDate, order: .reverse) private var allWalks: [WalkRoute]

    /// 「保存这次遛狗」按下的一瞬间置 true，让 × 和 CTA 隐掉一帧，截屏拿到的就是纯净的总结页。
    @State private var isCapturing = false
    /// 存完相册后弹的小 toast，1s 后自动消失并关页。
    @State private var savedToastVisible = false

    var body: some View {
        ZStack {
            Panora.appBackground.ignoresSafeArea()

            // 不再套 ScrollView：地图 208 + 数据条 + coverflow + CTA 一屏就装得下；
            // coverflow 用两侧 Spacer 挤在中间「剩余空间」里居中，跟设计对齐。
            VStack(spacing: 0) {
                topBar
                headline
                routeMapCard
                    .padding(.horizontal, 16)
                statsStrip
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                Spacer(minLength: 12)
                coverflow
                    .padding(.horizontal, 16)
                Spacer(minLength: 12)
                bottomCTA
            }

            // 截屏成功后弹的 toast。放在最外层 ZStack 里，别的层不干扰它的居中定位。
            if savedToastVisible {
                VStack {
                    Spacer()
                    Text("已保存到相册")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Panora.textPrimary)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.black.opacity(0.72), in: Capsule())
                        .padding(.bottom, 90)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        // 从 WalkAllStatsView 走 NavigationStack push 进来时，父 nav bar / tab bar 会盖上来；
        // 从 fullScreenCover 进来时没有这两层，这三个 modifier 就是无害的空操作。
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - 顶栏

    /// 左「×」关闭，中间小字日期时间，右侧留空（原设计有「编辑」按钮，本页数据已定型故省去）。
    /// 截屏时 × 用 opacity 隐掉，占位保住，不影响日期居中。
    private var topBar: some View {
        HStack {
            Button(action: onDone) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Panora.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .opacity(isCapturing ? 0 : 1)
            Spacer()
            Text(headerDateText)
                .font(.system(size: 12))
                .foregroundStyle(Panora.textMuted)
            Spacer()
            // 左右对称留白，保住日期居中；不加编辑按钮。
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - 大标题

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("遛完啦，今天走了")
            HStack(spacing: 0) {
                Text(String(format: "%.2f", route.distanceMeters / 1000))
                    .foregroundStyle(Panora.lime)
                Text(" 公里")
                    .foregroundStyle(Panora.lime)
            }
        }
        .font(.system(size: 26, weight: .bold))
        .kerning(-0.5)
        .foregroundStyle(Panora.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    // MARK: - 路线图卡

    private var routeMapCard: some View {
        let coords = route.points.map(\.coordinate)
        return PanoraMapView(
            route: coords,
            peeSpots: route.peeSpots.map(\.coordinate),
            poopSpots: route.poopSpots.map(\.coordinate),
            startPin: coords.first,
            endPin: coords.last,
            interactive: false,
            fitsRoute: true
        )
        .frame(height: 208)
        // overlay 必须在 clipShape 之前，否则渐隐会溢出圆角外沿 —— 或者需要自己再叠一次圆角裁剪。
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color(hex: 0x0A0B0C).opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 80)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .allowsHitTesting(false)
        .shadow(color: .black.opacity(0.45), radius: 14, y: 10)
    }

    // MARK: - 数据条 + 狗朋友头像叠放

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statCell(value: durationText, label: "时长")
            divider
            statCell(value: "\(route.peeCount)", label: "💦 尿尿")
            divider
            statCell(value: "\(route.poopCount)", label: "💩 拉屎")
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 6)
        .panoraCard(cornerRadius: 18)
        .overlay(alignment: .topLeading) {
            // 圆心压在卡片上沿：offset y 用 -15 让下半圆盖住卡边、上半圆浮在外面。
            if !metFriends.isEmpty {
                friendAvatarStack
                    .padding(.leading, 10)
                    .offset(y: -15)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Panora.dividerOnGlass)
            .frame(width: 0.5, height: 34)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Panora.textPrimary)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Panora.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metFriends: [DogFriend] {
        let ids = Set(route.metDogFriendIDs)
        return allFriends.filter { ids.contains($0.id) }
    }

    private var friendAvatarStack: some View {
        HStack(spacing: -8) {
            ForEach(metFriends) { friend in
                Group {
                    if let data = friend.avatarData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        // 没头像：拿名字第一个字撑一下，别露空圆。
                        Text(String(friend.name.prefix(1)))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Panora.textPrimary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Panora.blueChart.opacity(0.65))
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                // 2pt 深色描边，跟卡片主体色接近，让头像跟卡「分层」。
                .overlay(Circle().strokeBorder(Color(hex: 0x191B20), lineWidth: 2))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            }
        }
    }

    // MARK: - 3D 照片流

    /// 本次没拍照时的回落：所有遛狗记录里最近一次有**竖版**照片的那张。
    /// 找不到就返回空 → coverflow 整块不渲染。
    private var photosToShow: [UIImage] {
        let ownPortraits = route.photosData.compactMap(UIImage.init(data:))
        if !ownPortraits.isEmpty { return ownPortraits }

        for candidate in allWalks where candidate.id != route.id {
            for data in candidate.photosData {
                if let ui = UIImage(data: data), ui.size.height > ui.size.width {
                    return [ui]
                }
            }
        }
        return []
    }

    @ViewBuilder private var coverflow: some View {
        let photos = photosToShow
        if photos.isEmpty {
            EmptyView()
        } else if photos.count == 1 {
            // 就一张：不出侧边空卡也没有轮播；居中放大到 3D 中间态那个尺寸。
            singlePhotoCard(photos[0])
                .frame(maxWidth: .infinity)   // 居中
        } else {
            PhotoCoverflow(photos: photos)
        }
    }

    private func singlePhotoCard(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable().scaledToFill()
            .frame(width: 110, height: 147)   // 96 * 1.14 ≈ 中间态尺寸
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 14, y: 10)
    }

    // MARK: - 底部 CTA

    /// 「保存这次遛狗」：走截屏 → 存相册 → 弹 toast → 关页流程；不是数据入库（那事儿 finish() 早做了）。
    /// 截屏中用 opacity 隐掉自己，保住占位不塌，让截图里没这颗按钮。
    private var bottomCTA: some View {
        Button(action: handleSaveTap) {
            Text("保存这次遛狗")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Panora.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Panora.lime, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: Panora.lime.opacity(0.28), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .opacity(isCapturing ? 0 : 1)
        .disabled(isCapturing)
    }

    // MARK: - 截屏保存

    /// 隐掉两颗按钮 → 下一帧 drawHierarchy 拿位图 → 存相册 → toast → 关页。
    ///
    /// 用 window.drawHierarchy(afterScreenUpdates: true) 抓当前渲染结果，而不是 ImageRenderer 离屏重建：
    /// 后者要把安全区、颜色空间、深色主题一样一样重新拼，稍有偏差截出来的图跟屏幕不一致；
    /// drawHierarchy 就是所见即所得，代价是把状态栏（时间/电量）也带进去，符合 iOS 用户对「截屏」的直觉。
    private func handleSaveTap() {
        guard !isCapturing else { return }
        isCapturing = true

        // 排一次主队列，等 SwiftUI 把 × / CTA 的 opacity 刷新到 0 再抓图；
        // 同步抓的话按钮还没消失，会被截进去。
        DispatchQueue.main.async {
            if let image = captureKeyWindow() {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
            withAnimation(.easeIn(duration: 0.15)) { savedToastVisible = true }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.2)) { savedToastVisible = false }
                isCapturing = false
                onDone()
            }
        }
    }

    private func captureKeyWindow() -> UIImage? {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let window = windowScene?.windows.first(where: \.isKeyWindow)
                ?? windowScene?.windows.first else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    // MARK: - 文案

    private var durationText: String {
        let m = route.durationSeconds / 60
        let s = route.durationSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// 顶部小字："2026年5月21日 晚 20:14" —— 时段词按小时分档，跟设计稿的 "晚 20:14" 对齐。
    private var headerDateText: String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: route.startDate)
        let period: String
        switch comps.hour ?? 0 {
        case 0..<6: period = "凌晨"
        case 6..<12: period = "早"
        case 12..<14: period = "中午"
        case 14..<18: period = "下午"
        default: period = "晚"
        }
        return String(
            format: "%d年%d月%d日 %@ %02d:%02d",
            comps.year ?? 0, comps.month ?? 0, comps.day ?? 0,
            period, comps.hour ?? 0, comps.minute ?? 0
        )
    }
}

// MARK: - 3D 照片轮播（Panora 交接稿 §③「照片封面流」）
//
// 按设计公式手绘 3D 变换，不走 ScrollView：ScrollView 的 scrollTransition 是「跟着滑动量插值」，
// 拿不出「点箭头 / 点圆点跳一步 + cubic-bezier 弹出」这种命令式动效。这里就是自绘 ZStack + 一套
// index-driven transform：
//   translateX = (i - current) * 40pt
//   rotateY    = active ? 0 : (isPast ? +38° : -38°)
//   scale      = active ? 1.14 : max(0.7, 1 - abs * 0.08)
//   opacity    = abs > 2 ? 0 : 1 - abs * 0.28
//   zIndex     = 100 - abs
private struct PhotoCoverflow: View {
    let photos: [UIImage]
    @State private var current: Int = 0

    /// 设计稿明确的 cubic-bezier(.22,.61,.36,1) / 0.45s ——「快出慢入」的软弹感。
    private var animation: Animation { .timingCurve(0.22, 0.61, 0.36, 1, duration: 0.45) }

    var body: some View {
        VStack(spacing: 16) {
            stage
            controls
        }
    }

    private var stage: some View {
        ZStack {
            ForEach(photos.indices, id: \.self) { i in
                photoCard(photos[i], slot: i - current)
                    .zIndex(Double(100 - abs(i - current)))
                    .onTapGesture {
                        withAnimation(animation) { current = i }
                    }
            }
        }
        // 128 * 1.14 ≈ 145.9；再留几 pt 给下阴影不被裁。
        .frame(height: 156)
    }

    private func photoCard(_ image: UIImage, slot: Int) -> some View {
        let distance = abs(slot)
        let isActive = slot == 0
        let isPast = slot < 0
        return Image(uiImage: image)
            .resizable().scaledToFill()
            .frame(width: 96, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 14, y: 10)
            .rotation3DEffect(
                .degrees(isActive ? 0 : (isPast ? 38 : -38)),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )
            .scaleEffect(isActive ? 1.14 : max(0.7, 1 - CGFloat(distance) * 0.08))
            .offset(x: CGFloat(slot) * 40)
            .opacity(distance > 2 ? 0 : 1 - Double(distance) * 0.28)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            arrowButton(system: "chevron.left") {
                guard current > 0 else { return }
                withAnimation(animation) { current -= 1 }
            }
            .opacity(current == 0 ? 0.35 : 1)

            HStack(spacing: 5) {
                ForEach(photos.indices, id: \.self) { i in
                    Capsule()
                        .fill(current == i ? Panora.lime : Color.white.opacity(0.28))
                        .frame(width: current == i ? 18 : 4, height: 4)
                        .animation(animation, value: current)
                        .contentShape(Rectangle().inset(by: -6))   // 圆点太小，多给点点击容差
                        .onTapGesture {
                            withAnimation(animation) { current = i }
                        }
                }
            }

            arrowButton(system: "chevron.right") {
                guard current < photos.count - 1 else { return }
                withAnimation(animation) { current += 1 }
            }
            .opacity(current == photos.count - 1 ? 0.35 : 1)
        }
    }

    private func arrowButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
