import Foundation
import UIKit

/// 真机页面性能探针。每次只监测当前刚打开的页面 2 秒，记录明显卡顿帧，
/// 不逐帧写磁盘，避免诊断工具本身制造卡顿。
@MainActor
final class PagePerformanceMonitor {
    static let shared = PagePerformanceMonitor()

    private var navigationStarts: [String: TimeInterval] = [:]
    private var displayLink: CADisplayLink?
    private var activePage = ""
    private var startedAt: TimeInterval = 0
    private var previousFrameAt: CFTimeInterval?
    private var frameCount = 0
    private var hitchCount = 0
    private var worstFrameMs: Double = 0

    private init() {}

    func navigationBegan(to page: String, context: String? = nil) {
        navigationStarts[page] = ProcessInfo.processInfo.systemUptime
        SessionEventLog.log("perf.tap", context: joined(page: page, detail: context))
    }

    func pageAppeared(_ page: String, context: String? = nil) {
        displayLink?.invalidate()

        let now = ProcessInfo.processInfo.systemUptime
        let transitionMs = navigationStarts.removeValue(forKey: page).map { (now - $0) * 1_000 }
        var details = context ?? ""
        if let transitionMs {
            details += details.isEmpty ? "" : ", "
            details += String(format: "tapToAppear=%.1fms", transitionMs)
        }
        SessionEventLog.log("perf.appear", context: joined(page: page, detail: details))

        activePage = page
        startedAt = now
        previousFrameAt = nil
        frameCount = 0
        hitchCount = 0
        worstFrameMs = 0

        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func workFinished(page: String, phase: String, startedAt: TimeInterval, context: String? = nil) {
        let elapsedMs = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        var details = String(format: "phase=%@, elapsed=%.1fms", phase, elapsedMs)
        if let context, !context.isEmpty { details += ", \(context)" }
        SessionEventLog.log("perf.work", context: joined(page: page, detail: details))
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        if let previousFrameAt {
            let frameMs = (now - previousFrameAt) * 1_000
            frameCount += 1
            if frameMs >= 50 {
                hitchCount += 1
                worstFrameMs = max(worstFrameMs, frameMs)
            }
        }
        previousFrameAt = now

        if ProcessInfo.processInfo.systemUptime - startedAt >= 2.0 {
            finish()
        }
    }

    private func finish() {
        displayLink?.invalidate()
        displayLink = nil
        SessionEventLog.log(
            "perf.frames",
            context: joined(
                page: activePage,
                detail: String(
                    format: "window=2.0s, frames=%d, hitches>=50ms=%d, worst=%.1fms",
                    frameCount, hitchCount, worstFrameMs
                )
            )
        )
    }

    private func joined(page: String, detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return "page=\(page)" }
        return "page=\(page), \(detail)"
    }
}
