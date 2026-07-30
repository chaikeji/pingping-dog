import Foundation

/// 遛狗会话的诊断日志：把 start / resume / discard / finish / onAppear 这些关键事件
/// 落到 Application Support 里一个小文本文件，方便事后回看"数据是被谁清掉的"。
///
/// 起因：用户报了一个 bug —— 遛狗中途用 app 内拍照，回来数据全没。
/// 假设是 SwiftUI 的 .fullScreenCover dismiss 会触发底下 view 二次 .onAppear，
/// 导致 session.start() 被多喊一次把状态清零。日志用来验证 / 举证。
///
/// 只保留最近 300 行 —— 遛狗事件本身就不多，太长的日志不方便快速看。
enum SessionEventLog {
    /// 单行上限：太长的 context 截掉，避免一行日志把整个文件撑爆。
    private static let maxLineLength = 400
    /// 环形上限：超过就丢头。300 条足以覆盖一次完整遛狗周期 + 前后几次触发。
    private static let maxLines = 300

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session_events.log")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// 记一条事件。event 是简短名字（"start" / "resume" / "onAppear" ...），
    /// context 是自由文本，一般带上关键状态方便回看。
    static func log(_ event: String, context: String? = nil) {
        let stamp = formatter.string(from: Date())
        var line = "[\(stamp)] \(event)"
        if let context, !context.isEmpty { line += " | \(context)" }
        if line.count > maxLineLength {
            line = String(line.prefix(maxLineLength)) + "…"
        }
        append(line + "\n")
    }

    private static func append(_ line: String) {
        // 读老内容 → 尾追 → 超行数丢头 → 原子写回。
        // 遛狗时事件密度低（1~10 条/次），每次读写整文件没关系；有性能顾虑再换 FileHandle 追加。
        var existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        existing += line
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
        }
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// 读整份日志。空文件回一句提示，方便"我"页直接显示。
    static func readAll() -> String {
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        return content.isEmpty ? "（还没有事件记录）" : content
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 日志文件路径，供分享 / 拷贝用。
    static var logFileURL: URL { fileURL }
}
