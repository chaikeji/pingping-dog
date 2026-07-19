import Foundation

/// USDZ 模型文件的落盘位置。
///
/// 两个坑，都是真机上必然踩到的：
///
/// 1. 不能放 Caches。系统存储紧张时会清空 Caches，而单个模型有几十 MB，
///    正是优先被清掉的对象，清完 App 这边还以为文件在。改放 Application Support。
/// 2. 不能存绝对路径。沙盒容器路径里带一段 UUID，**重装 App 会变**；
///    我们靠 Sideloadly 免费签名分发、7 天就要重签重装一次，
///    存下来的绝对路径下次启动必然指向一个不存在的位置。
///    所以数据库里那条路径只当「文件名的载体」用，每次读都按当前容器重新拼。
enum ModelStorage {
    /// 模型目录（Application Support/Models），不存在就建出来。
    /// Application Support 默认不会自动创建，得自己 create。
    static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var models = base.appendingPathComponent("Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: models.path) {
            try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
            // 模型随时能重新生成，没必要占 iCloud 备份空间：一个就有几十 MB。
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? models.setResourceValues(values)
        }
        return models
    }

    /// 某个 owner（狗朋友 / 平平）对应的模型落盘位置。
    static func destination(ownerID: UUID) throws -> URL {
        try directory().appendingPathComponent("\(ownerID.uuidString).usdz")
    }

    /// 列表用的缩略图。和模型放一起，模型没了它也一并失效。
    static func thumbnailURL(ownerID: UUID) throws -> URL {
        try directory().appendingPathComponent("\(ownerID.uuidString)-thumb.jpg")
    }

    /// 把库里存的路径还原成当前容器下真实可用的 URL。
    ///
    /// 只取文件名，重新拼当前的 Application Support 路径 —— 这样重装后容器 UUID 变了也照样能找到。
    /// 文件确实不在（被清理、或还没下载完）时返回 nil，让调用方走「模型不可用」分支，
    /// 而不是把一个指向空气的 URL 交给 QuickLook。
    static func resolve(_ stored: URL?) -> URL? {
        guard let stored, let directory = try? directory() else { return nil }
        let candidate = directory.appendingPathComponent(stored.lastPathComponent)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
