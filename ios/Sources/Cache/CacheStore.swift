import Foundation
import Observation
import CryptoKit

/// 单个 key 的下载进度盒子。
///
/// 进度是高频值（合流后仍有 4 Hz）。如果放进一张 `[String: Double]` 字典里，
/// `@Observable` 的依赖粒度是**整个字典**——任何一行读其中一个 key，都会在任何 key 变化时重算。
/// 每行只观察自己那个盒子，别人的进度变化就与它无关。
@MainActor
@Observable
final class CacheProgress {
    var value: Double = 0
}

@MainActor
@Observable
final class CacheStore {
    static let shared = CacheStore()

    private(set) var entries: [String: CacheEntry] = [:]
    /// 每 key 一个盒子；字典本身不参与观察（见 `CacheProgress`）。
    @ObservationIgnored private(set) var progressBoxes: [String: CacheProgress] = [:]
    private(set) var active: Set<String> = []
    private(set) var totalBytes: Int64 = 0
    var protectedKey: String?

    var limitMB: Int {
        didSet {
            UserDefaults.standard.set(limitMB, forKey: "cache.limitMB")
            enforceLimit()
        }
    }

    var wifiOnly: Bool {
        didSet { UserDefaults.standard.set(wifiOnly, forKey: "cache.wifiOnly") }
    }

    private let indexURL: URL
    private let audioDir: URL
    private let lyricsDir: URL
    private let artworkDir: URL
    private var isEnforcing = false
    /// 每个 entry 已计入 `totalBytes` 的字节数，用于增量维护总占用。
    private var entryBytes: [String: Int64] = [:]
    /// `touch()` 的落盘防抖（见 `scheduleSave()`）。
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tinymusic", isDirectory: true)
            .appendingPathComponent("Offline", isDirectory: true)
        audioDir = support.appendingPathComponent("audio", isDirectory: true)
        lyricsDir = support.appendingPathComponent("lyrics", isDirectory: true)
        artworkDir = support.appendingPathComponent("artwork", isDirectory: true)
        indexURL = support.appendingPathComponent("index.json")
        limitMB = UserDefaults.standard.object(forKey: "cache.limitMB") as? Int ?? 2048
        wifiOnly = UserDefaults.standard.object(forKey: "cache.wifiOnly") as? Bool ?? true
        prepareDirectories()
        load()
        reconcileStatuses()
        updateTotal()
    }

    nonisolated static var cacheRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tinymusic", isDirectory: true)
            .appendingPathComponent("Offline", isDirectory: true)
    }

    nonisolated static func audioDestination(for key: String) -> URL {
        cacheRoot.appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent(fileName(for: key, ext: fileExtension(for: key)))
    }

    nonisolated static func lyricsDestination(for key: String) -> URL {
        cacheRoot.appendingPathComponent("lyrics", isDirectory: true)
            .appendingPathComponent(fileName(for: key, ext: "json"))
    }

    nonisolated static func artworkDestination(for key: String) -> URL {
        cacheRoot.appendingPathComponent("artwork", isDirectory: true)
            .appendingPathComponent(fileName(for: key, ext: "jpg"))
    }

    nonisolated static func fileName(for key: String, ext: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hash).\(ext.lowercased())"
    }

    nonisolated static func fileExtension(for key: String) -> String {
        let ext = key.split(separator: ".").last.map(String.init)?.lowercased() ?? "m4a"
        let allowed = ["mp3", "m4a", "aac", "flac", "wav"]
        return allowed.contains(ext) ? ext : "m4a"
    }

    /// 断网/断开 S3 时，资料库用它显示离线歌单。
    var cachedPlaylists: [Playlist] {
        let groups = Dictionary(grouping: entries.values.filter { $0.status == .done }) { entry in
            entry.playlist.isEmpty ? L("未分类") : entry.playlist
        }
        return groups.map { name, list in
            let sorted = list.sorted { $0.cachedAt < $1.cachedAt }
            let cover = sorted.first.flatMap { coverURL(for: $0.key)?.absoluteString }
            return Playlist(name: name, count: sorted.count, cover: cover, root: name == L("未分类"))
        }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func cachedTracks(in playlist: String) -> [Track] {
        entries.values
            .filter { $0.status == .done && (($0.playlist.isEmpty ? L("未分类") : $0.playlist) == playlist) }
            .sorted { $0.cachedAt < $1.cachedAt }
            .map(\.track)
    }

    /// 纯内存判断，不碰磁盘：每行每趟 body 都会调它。
    ///
    /// 「文件还在不在」由 `reconcileFiles()` 负责（启动后在后台做音频头校验）。
    func isCached(_ key: String) -> Bool {
        entries[key]?.status == .done
    }

    /// 真正要播放时才调（每次切歌一次），所以这里的 `fileExists` 留着——
    /// 缓存目录被系统清理掉时，还能退回流播放而不是直接报错。
    func localURL(for key: String) -> URL? {
        guard let entry = entries[key], entry.status == .done else { return nil }
        let url = audioDir.appendingPathComponent(entry.audioFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 同上：body 里每行都会调，不能再做 stat。
    /// 封面文件真的丢了的话 `CoverImage` 会走失败占位，不会崩。
    func coverURL(for key: String) -> URL? {
        guard let entry = entries[key], let file = entry.artworkFile else { return nil }
        return artworkDir.appendingPathComponent(file)
    }

    func progressBox(for key: String) -> CacheProgress? {
        progressBoxes[key]
    }

    func lyrics(for key: String) -> [LyricLine]? {
        guard let entry = entries[key], let file = entry.lyricsFile else { return nil }
        let url = lyricsDir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([LyricLine].self, from: data)
    }

    func touch(_ key: String) {
        guard var entry = entries[key] else { return }
        entry.lastPlayedAt = Date()
        entries[key] = entry
        // `lastPlayedAt` 只影响 LRU 淘汰顺序，不值得为它把整个索引重写一遍——
        // 播一首缓存歌就编码 + 原子写一次几百条的 JSON，是主线程上的一次几百微秒到几毫秒的抖动。
        scheduleSave()
    }

    func markDownloading(_ info: CacheTaskInfo) {
        guard !isCached(info.key) else { return }
        let ext = Self.fileExtension(for: info.key)
        let entry = CacheEntry(
            key: info.key,
            title: info.title,
            artist: info.artist,
            playlist: info.playlist,
            audioFile: Self.fileName(for: info.key, ext: ext),
            audioBytes: 0,
            codec: "",
            quality: "",
            lyricsFile: nil,
            artworkFile: nil,
            cachedAt: Date(),
            lastPlayedAt: nil,
            status: .downloading,
            error: nil
        )
        entries[info.key] = entry
        active.insert(info.key)
        progressBoxes[info.key] = CacheProgress()
        save()
    }

    /// 批量写入下载进度。
    ///
    /// 只收仍在下载中的 key（避免晚到的批次把已结束的条目又写回进度表），
    /// 并且只写那些值真的变了的盒子——`@Observable` 的 setter 不做等值判断。
    func updateProgress(_ batch: [String: Double]) {
        guard !batch.isEmpty else { return }
        for (key, value) in batch where active.contains(key) {
            guard let box = progressBoxes[key] else { continue }
            let clamped = min(max(value, 0), 1)
            if box.value != clamped { box.value = clamped }
        }
    }

    func finish(_ key: String, bytes: Int64) {
        guard var entry = entries[key] else { return }
        entry.status = .done
        entry.audioBytes = bytes
        entry.error = nil
        entries[key] = entry
        active.remove(key)
        progressBoxes.removeValue(forKey: key)
        save()
        refreshBytes(for: key)
        enforceLimit(protect: key)
    }

    func setSidecars(_ key: String, lyricsFile: String?, artworkFile: String?) {
        guard var entry = entries[key] else { return }
        entry.lyricsFile = lyricsFile
        entry.artworkFile = artworkFile
        entries[key] = entry
        save()
        refreshBytes(for: key)
    }

    func fail(_ key: String, error: String) {
        guard var entry = entries[key] else { return }
        entry.status = .failed
        entry.error = error
        entries[key] = entry
        active.remove(key)
        progressBoxes.removeValue(forKey: key)
        save()
    }

    func remove(_ key: String) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: audioDir.appendingPathComponent(entry.audioFile))
        if let file = entry.lyricsFile { try? fm.removeItem(at: lyricsDir.appendingPathComponent(file)) }
        if let file = entry.artworkFile { try? fm.removeItem(at: artworkDir.appendingPathComponent(file)) }
        active.remove(key)
        progressBoxes.removeValue(forKey: key)
        totalBytes -= entryBytes.removeValue(forKey: key) ?? 0
        save()
    }

    func clear() {
        entries.removeAll()
        active.removeAll()
        progressBoxes.removeAll()
        entryBytes.removeAll()
        totalBytes = 0
        let fm = FileManager.default
        for dir in [audioDir, lyricsDir, artworkDir] {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files { try? fm.removeItem(at: file) }
            }
        }
        save()
    }

    func enforceLimit(protect: String? = nil) {
        guard !isEnforcing else { return }
        isEnforcing = true
        defer { isEnforcing = false }
        let limit = Int64(max(0, limitMB)) * 1024 * 1024
        guard limit > 0 else { return }
        while totalBytes > limit {
            let candidates = entries.values
                .filter { $0.status == .done && !active.contains($0.key) && $0.key != protect && $0.key != protectedKey }
                .sorted { ($0.lastPlayedAt ?? $0.cachedAt) < ($1.lastPlayedAt ?? $1.cachedAt) }
            guard let oldest = candidates.first else { break }
            remove(oldest.key)
        }
    }

    /// 全量重算（只在启动和恢复时用）。
    ///
    /// 逐条重算要 stat 每个缓存文件的 1–3 个附属文件；批量缓存时 `finish` 每首都会触发一次，
    /// 那就是 O(n²) 次 stat。日常路径请走 `refreshBytes(for:)`。
    func updateTotal() {
        entryBytes.removeAll(keepingCapacity: true)
        var total: Int64 = 0
        for entry in entries.values {
            var bytes = entry.audioBytes
            if let file = entry.lyricsFile { bytes += fileSize(lyricsDir.appendingPathComponent(file)) }
            if let file = entry.artworkFile { bytes += fileSize(artworkDir.appendingPathComponent(file)) }
            entryBytes[entry.key] = bytes
            total += bytes
        }
        totalBytes = total
    }

    /// 增量维护单个 entry 的占用：只 stat 它自己的歌词/封面，不碰其他 entry。
    private func refreshBytes(for key: String) {
        guard let entry = entries[key] else {
            totalBytes -= entryBytes.removeValue(forKey: key) ?? 0
            return
        }
        var bytes = entry.audioBytes
        if let file = entry.lyricsFile { bytes += fileSize(lyricsDir.appendingPathComponent(file)) }
        if let file = entry.artworkFile { bytes += fileSize(artworkDir.appendingPathComponent(file)) }
        totalBytes += bytes - (entryBytes[key] ?? 0)
        entryBytes[key] = bytes
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
    }

    private func prepareDirectories() {
        let fm = FileManager.default
        for dir in [audioDir, lyricsDir, artworkDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var root = Self.cacheRoot
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(CacheIndex.self, from: data) else {
            return
        }
        entries = index.entries
    }

    private func save() {
        saveTask?.cancel()
        saveTask = nil
        let index = CacheIndex(entries: entries)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.save()
        }
    }

    /// 把防抖中的写入立刻落盘（进后台 / 切场景时调用），别把 `lastPlayedAt` 留在窗口里。
    func flushSave() {
        guard saveTask != nil else { return }
        save()
    }

    /// 启动收尾里唯一不能省的那一步：把「上次没下完」的条目标成失败。
    /// 纯内存操作，不需要碰磁盘。
    private func reconcileStatuses() {
        var changed = false
        for (key, entry) in entries where entry.status == .downloading {
            var updated = entry
            updated.status = .failed
            updated.error = L("缓存中断，可重试")
            entries[key] = updated
            changed = true
        }
        if changed { save() }
    }

    /// 校验缓存文件是否真的可用（有没有被系统清掉、是不是有效音频头）。
    ///
    /// 原来这段在 `@MainActor` 的 `init` 里同步跑：每条 entry 都要用 `FileHandle` 打开读 12 个字节，
    /// 缓存 500 首就是启动时 500 次 open+read，全堵在主线程上，而且随库大小线性增长。
    /// 现在放到后台任务里跑，结果回主 actor 应用。
    func reconcileFiles() async {
        let snapshot = entries
        let directory = audioDir
        let broken: [(key: String, file: String)] = await Task.detached(priority: .utility) {
            snapshot.compactMap { key, entry -> (key: String, file: String)? in
                guard entry.status == .done else { return nil }
                let url = directory.appendingPathComponent(entry.audioFile)
                return AudioValidation.isValid(at: url) ? nil : (key, entry.audioFile)
            }
        }.value
        guard !broken.isEmpty else { return }
        var changed = false
        for item in broken {
            // 后台跑的这段时间里，这一条可能已经被删掉、或者又下好了一份：只处理还是同一条的。
            guard let entry = entries[item.key],
                  entry.status == .done,
                  entry.audioFile == item.file else { continue }
            entries.removeValue(forKey: item.key)
            try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(entry.audioFile))
            totalBytes -= entryBytes.removeValue(forKey: item.key) ?? 0
            changed = true
        }
        if changed { save() }
    }
}
