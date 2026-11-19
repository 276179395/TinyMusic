import Foundation

final class CacheManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = CacheManager()

    private var session: URLSession!
    private var backgroundCompletionHandler: (() -> Void)?

    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "cn.carljoy.tinymusic.cache")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func start() {
        _ = session
    }

    func handleEvents(completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
    }

    @discardableResult
    func enqueue(track: Track, playlist: String, backend: RustBackend = .shared) async throws -> Bool {
        let already = await MainActor.run { CacheStore.shared.isCached(track.key) }
        guard !already else { return false }

        let source: PlayURL = try await backend.call("s3_play_url", ["key": .string(track.key)])
        let wifiOnly = await MainActor.run { CacheStore.shared.wifiOnly }
        guard let url = URL(string: source.url) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.allowsExpensiveNetworkAccess = !wifiOnly
        request.allowsConstrainedNetworkAccess = !wifiOnly
        request.timeoutInterval = 60

        let info = CacheTaskInfo(key: track.key, title: track.title, artist: track.artist, playlist: playlist)
        let task = session.downloadTask(with: request)
        if let data = try? JSONEncoder().encode(info) {
            task.taskDescription = String(data: data, encoding: .utf8)
        }
        await MainActor.run { CacheStore.shared.markDownloading(info) }
        task.resume()
        return true
    }

    func cancel(key: String) {
        session.getAllTasks { tasks in
            for task in tasks where Self.taskInfo(task)?.key == key {
                task.cancel()
            }
        }
    }

    func cancelAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let info = Self.taskInfo(downloadTask) else { return }
        let value = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        Task { @MainActor in CacheStore.shared.updateProgress(info.key, value) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let info = Self.taskInfo(downloadTask) else { return }
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: location)
            Task { @MainActor in
                CacheStore.shared.fail(info.key, error: L("缓存失败：HTTP %@", "\(http.statusCode)"))
            }
            return
        }
        guard AudioValidation.isValid(at: location) else {
            let size = (try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? FileManager.default.removeItem(at: location)
            Task { @MainActor in
                CacheStore.shared.fail(info.key, error: L("缓存失败：服务器返回的不是有效音频（%@ 字节）", "\(size)"))
            }
            return
        }
        let destination = CacheStore.audioDestination(for: info.key)
        let fm = FileManager.default
        try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: destination)
        do {
            try fm.moveItem(at: location, to: destination)
        } catch {
            Task { @MainActor in CacheStore.shared.fail(info.key, error: L("写入缓存失败：%@", error.localizedDescription)) }
            return
        }
        let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
        Task { @MainActor in
            CacheStore.shared.finish(info.key, bytes: bytes)
        }
        Task { await fetchSidecars(info) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let info = Self.taskInfo(task) else { return }
        Task { @MainActor in
            CacheStore.shared.fail(info.key, error: error.localizedDescription)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        DispatchQueue.main.async { handler?() }
    }

    private func fetchSidecars(_ info: CacheTaskInfo) async {
        let backend = RustBackend.shared
        var lyricsFile: String?
        var artworkFile: String?

        if let lyrics: LyricsResult = try? await backend.call("s3_lyrics", ["key": .string(info.key)]),
           lyrics.present, !lyrics.lines.isEmpty,
           let data = try? JSONEncoder().encode(lyrics.lines) {
            let url = CacheStore.lyricsDestination(for: info.key)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            lyricsFile = url.lastPathComponent
        }

        if let cover: String? = try? await backend.call("s3_cover", ["key": .string(info.key)]),
           let cover, let url = URL(string: cover),
           let (data, response) = try? await URLSession.shared.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            let destination = CacheStore.artworkDestination(for: info.key)
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: destination, options: .atomic)
            artworkFile = destination.lastPathComponent
        }

        let finalLyrics = lyricsFile
        let finalArtwork = artworkFile
        await MainActor.run {
            CacheStore.shared.setSidecars(info.key, lyricsFile: finalLyrics, artworkFile: finalArtwork)
        }
    }

    private static func taskInfo(_ task: URLSessionTask) -> CacheTaskInfo? {
        guard let text = task.taskDescription, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CacheTaskInfo.self, from: data)
    }
}
