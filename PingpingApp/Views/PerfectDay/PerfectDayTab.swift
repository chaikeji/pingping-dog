import SwiftUI

/// 「完美的一天」这个 tab 的容器。
///
/// 根页面是今天，点日期条进到某一天 —— 用的是同一个 `PerfectDayView`，
/// 只是传了 day 就变只读，UI 完全一样。
///
/// path 永远只放一天（换页是横跳，不是往下钻）：历史页上还有日期条，
/// 要是每点一次就 push 一层，返回时得连点十几下才回得到今天。
struct PerfectDayTab: View {
    @State private var path: [Date] = []

    var body: some View {
        NavigationStack(path: $path) {
            PerfectDayView(onSelectDay: jump(to:))
                .navigationDestination(for: Date.self) { day in
                    PerfectDayView(day: day, onSelectDay: jump(to:))
                        // 页面自己画返回键，导航栏藏起来才跟今天长得一样。
                        .toolbar(.hidden, for: .navigationBar)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func jump(to day: Date) {
        // 点回今天就直接退栈，别再叠一页看着一样的。
        path = day == PetDay.start() ? [] : [day]
    }
}
