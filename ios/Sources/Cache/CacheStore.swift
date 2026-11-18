import Foundation
import Observation
import CryptoKit

@MainActor
@Observable
final class CacheStore {
    static let shared = CacheStore()

    private(set) var entries: [String: CacheEntry] = [:]
    private(set) var progress: [String: Double] = [:]
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
        reconcile()
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
            entry.playlist.isEmpty ? "未分类" : entry.playlist
        }
        return groups.map { name, list in
            let sorted = list.sorted { $0.cachedAt < $1.cachedAt }
            let cover = sorted.first.flatMap { coverURL(for: $0.key)?.absoluteString }
            return Playlist(name: name, count: sorted.count, cover: cover, root: name == "未分类")
        }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func cachedTracks(in playlist: String) -> [Track] {
        entries.values
            .filter { $0.status == .done && (($0.playlist.isEmpty ? "未分类" : $0.playlist) == playlist) }
            .sorted { $0.cachedAt < $1.cachedAt }
            .map(\.track)
    }

    func isCached(_ key: String) -> Bool {
        localURL(for: key) != nil
    }

    func localURL(for key: String) -> URL? {
        guard let entry = entries[key], entry.status == .done else { return nil }
        let url = audioDir.appendingPathComponent(entry.audioFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func coverURL(for key: String) -> URL? {
        guard let entry = entries[key], let file = entry.artworkFile else { return nil }
        let url = artworkDir.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
        save()
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
        progress[info.key] = 0
        save()
    }

    func updateProgress(_ key: String, _ value: Double) {
        progress[key] = min(max(value, 0), 1)
    }

    func finish(_ key: String, bytes: Int64) {
        guard var entry = entries[key] else { return }
        entry.status = .done
        entry.audioBytes = bytes
        entry.error = nil
        entries[key] = entry
        active.remove(key)
        progress.removeValue(forKey: key)
        save()
        updateTotal()
        enforceLimit(protect: key)
    }

    func setSidecars(_ key: String, lyricsFile: String?, artworkFile: String?) {
        guard var entry = entries[key] else { return }
        entry.lyricsFile = lyricsFile
        entry.artworkFile = artworkFile
        entries[key] = entry
        save()
        updateTotal()
    }

    func fail(_ key: String, error: String) {
        guard var entry = entries[key] else { return }
        entry.status = .failed
        entry.error = error
        entries[key] = entry
        active.remove(key)
        progress.removeValue(forKey: key)
        save()
    }

    func remove(_ key: String) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: audioDir.appendingPathComponent(entry.audioFile))
        if let file = entry.lyricsFile { try? fm.removeItem(at: lyricsDir.appendingPathComponent(file)) }
        if let file = entry.artworkFile { try? fm.removeItem(at: artworkDir.appendingPathComponent(file)) }
        active.remove(key)
        progress.removeValue(forKey: key)
        save()
        updateTotal()
    }

    func clear() {
        entries.removeAll()
        active.removeAll()
        progress.removeAll()
        let fm = FileManager.default
        for dir in [audioDir, lyricsDir, artworkDir] {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files { try? fm.removeItem(at: file) }
            }
        }
        save()
        updateTotal()
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

    func updateTotal() {
        totalBytes = entries.values.reduce(into: 0) { total, entry in
            total += fileSize(audioDir.appendingPathComponent(entry.audioFile))
            if let file = entry.lyricsFile { total += fileSize(lyricsDir.appendingPathComponent(file)) }
            if let file = entry.artworkFile { total += fileSize(artworkDir.appendingPathComponent(file)) }
        }
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
        let index = CacheIndex(entries: entries)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func reconcile() {
        let fm = FileManager.default
        for (key, entry) in entries {
            let audio = audioDir.appendingPathComponent(entry.audioFile)
            if entry.status == .done && (!fm.fileExists(atPath: audio.path) || !AudioValidation.isValid(at: audio)) {
                entries.removeValue(forKey: key)
                try? fm.removeItem(at: audio)
            } else if entry.status == .downloading {
                var updated = entry
                updated.status = .failed
                updated.error = "缓存中断，可重试"
                entries[key] = updated
            }
        }
        save()
    }
}
