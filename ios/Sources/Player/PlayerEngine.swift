import Foundation
import AVFoundation
import MediaPlayer
import Observation
import UIKit

@MainActor
@Observable
final class PlayerEngine {
    private(set) var queue: [Track] = []
    private(set) var index = -1
    private(set) var current: Track?
    /// 当前队列来自哪个歌单；用于资料库卡片的播放状态。
    private(set) var playlistContext: String?
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var buffering = false
    private(set) var error: String?
    var shuffle = false
    var repeatMode: RepeatMode = .off
    var showNowPlaying = false

    var currentCoverURL: String? {
        guard let current else { return nil }
        return cache.coverURL(for: current.key)?.absoluteString ?? current.cover
    }

    private let backend: RustBackend
    private let cache: CacheStore
    let eq = EQController()
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var artworkKey: String?
    private var artwork: MPMediaItemArtwork?
    private var audioConfigured = false

    init(backend: RustBackend = .shared, cache: CacheStore = .shared) {
        self.backend = backend
        self.cache = cache
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
                self?.buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                if let item = self.player.currentItem {
                    let value = item.duration.seconds
                    if value.isFinite, value > 0 { self.duration = value }
                }
                self.updateNowPlaying()
            }
        }
    }

    func play(track: Track, in tracks: [Track], context: String? = nil) {
        queue = tracks
        index = tracks.firstIndex(of: track) ?? 0
        playlistContext = context
        load(track)
    }

    func play(track: Track) {
        playlistContext = nil
        let tracks = queue.isEmpty ? [track] : queue
        if let existing = tracks.firstIndex(of: track) {
            index = existing
            queue = tracks
        } else {
            queue = tracks + [track]
            index = queue.count - 1
        }
        load(track)
    }

    func toggle() {
        guard current != nil else { return }
        if player.rate > 0 {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        let target = PlaybackQueue.nextIndexManual(length: queue.count, index: max(0, index), shuffle: shuffle)
        guard let target, queue.indices.contains(target) else { return }
        index = target
        load(queue[target])
    }

    /// 把曲目插到当前曲目后面，作为“下一首播放”。
    func playNext(_ track: Track) {
        guard current != nil else {
            play(track: track, in: [track])
            return
        }
        if current?.key == track.key { return }
        var next = queue
        if let existing = next.firstIndex(of: track) {
            next.remove(at: existing)
        }
        let insertAt = min(max(index + 1, 0), next.count)
        next.insert(track, at: insertAt)
        queue = next
    }

    /// 从当前队列删掉一首；如果删的是正在播放的，自动接上下一首。
    func removeFromQueue(_ track: Track) {
        guard let idx = queue.firstIndex(where: { $0.key == track.key }),
              let result = PlaybackQueue.queueAfterRemove(queue, index: index, removeAt: idx) else { return }
        queue = result.queue
        guard !queue.isEmpty else {
            clearQueue()
            return
        }
        index = result.index
        if let target = result.playTarget {
            index = target
            load(queue[target])
        }
    }

    func clearQueue() {
        queue.removeAll()
        index = -1
        playlistContext = nil
        stop()
        buffering = false
        showNowPlaying = false
    }

    func jump(to track: Track) {
        guard let idx = queue.firstIndex(where: { $0.key == track.key }) else { return }
        index = idx
        load(track)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if position > 3 {
            seek(to: 0)
            return
        }
        let target = PlaybackQueue.prevIndexManual(length: queue.count, index: max(0, index), shuffle: shuffle)
        guard let target, queue.indices.contains(target) else { return }
        index = target
        load(queue[target])
    }

    func seek(to seconds: TimeInterval) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        loadTask?.cancel()
        artworkTask?.cancel()
        artworkKey = nil
        artwork = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        cache.protectedKey = nil
        current = nil
        isPlaying = false
        position = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func setQueue(_ tracks: [Track], startingAt index: Int) {
        queue = tracks
        playlistContext = nil
        self.index = max(0, min(index, tracks.count - 1))
        if queue.indices.contains(self.index) {
            load(queue[self.index])
        }
    }

    private func load(_ track: Track) {
        loadTask?.cancel()
        cache.protectedKey = track.key
        current = track
        error = nil
        position = 0
        duration = 0
        buffering = true
        if let local = cache.localURL(for: track.key) {
            cache.touch(track.key)
            startItem(url: local.absoluteString, track: track)
            return
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let source: PlayURL = try await self.backend.call("s3_play_url", [
                    "key": .string(track.key),
                ])
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.startItem(url: source.url, track: track)
                }
            } catch {
                await MainActor.run {
                    self.buffering = false
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func startItem(url string: String, track: Track) {
        ensureAudioSession()
        guard let url = URL(string: string) else {
            error = "音频地址无效"
            buffering = false
            return
        }
        let item = AVPlayerItem(url: url)
        eq.attach(to: item)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        buffering = false
        observeEnd(for: item)
        updateNowPlaying()
        failObserver.map { NotificationCenter.default.removeObserver($0) }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            Task { @MainActor in self?.error = message ?? "播放失败" }
        }
    }

    private func observeEnd(for item: AVPlayerItem) {
        endObserver.map { NotificationCenter.default.removeObserver($0) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleEnded() }
        }
    }

    private func handleEnded() {
        if repeatMode == .one {
            seek(to: 0)
            player.play()
            return
        }
        guard let target = PlaybackQueue.nextIndexOnEnded(
            length: queue.count,
            index: max(0, index),
            shuffle: shuffle,
            repeatMode: repeatMode
        ), queue.indices.contains(target) else {
            isPlaying = false
            return
        }
        index = target
        load(queue[target])
    }

    private func ensureAudioSession() {
        guard !audioConfigured else { return }
        audioConfigured = true
        configureAudioSession()
        configureRemoteCommands()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            self.error = "音频会话初始化失败：\(error.localizedDescription)"
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                Task { @MainActor in
                    self?.player.pause()
                    self?.isPlaying = false
                }
            }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  reason == .oldDeviceUnavailable else { return }
            Task { @MainActor in
                self?.player.pause()
                self?.isPlaying = false
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.player.play()
                self?.isPlaying = true
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.player.pause()
                self?.isPlaying = false
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if artworkKey == current.key, let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        loadArtworkIfNeeded(for: current)
    }

    private func loadArtworkIfNeeded(for track: Track) {
        guard artworkKey != track.key else { return }
        artworkKey = track.key
        artwork = nil
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let self else { return }
            guard let image = await self.loadArtwork(for: track) else { return }
            guard !Task.isCancelled, self.current?.key == track.key else { return }
            let mediaArtwork = Self.makeArtwork(image)
            self.artwork = mediaArtwork
            #if DEBUG
            NSLog("[TinyMusic] now-playing artwork ready %dx%d", Int(image.size.width), Int(image.size.height))
            #endif
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = mediaArtwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    /// 图片请求闭包会被 MediaPlayer 在 accessQueue 调用；必须保持 nonisolated。
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func loadArtwork(for track: Track) async -> UIImage? {
        if let local = cache.coverURL(for: track.key),
           let image = UIImage(contentsOfFile: local.path) {
            return image
        }
        guard let cover = track.cover,
              let url = URL(string: cover),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            return nil
        }
        return UIImage(data: data)
    }
}
