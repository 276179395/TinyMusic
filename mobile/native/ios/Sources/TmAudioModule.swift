import AVFoundation
import MediaPlayer
import UIKit

/// 播放器原生模块：AVPlayer + 锁屏/线控 + 音频会话。
///
/// 通信方式：**JS 轮询 state()**，而不是原生往 JS 推。
/// 原因：AVPlayer 的回调都在主线程，而 Lynx 的 JS 回调只能在它的 JS 线程上调用；
/// 轮询把两边解耦，也顺带解决了"锁屏操作怎么回传"。
/// 队列/随机/循环/音质这些规则在 packages/shared 里，这里只管播放器本身。
@objcMembers
final class TmAudioModule: NSObject, LynxModule {
    @objc class var name: String { "TmAudio" }

    @objc class var methodLookup: [String: String] {
        [
            "load": NSStringFromSelector(#selector(load(_:title:artist:cover:duration:))),
            "loadLocal": NSStringFromSelector(#selector(loadLocal(_:title:artist:))),
            "play": NSStringFromSelector(#selector(play)),
            "pause": NSStringFromSelector(#selector(pause)),
            "seek": NSStringFromSelector(#selector(seek(_:))),
            "setVolume": NSStringFromSelector(#selector(setVolume(_:))),
            "stop": NSStringFromSelector(#selector(stop)),
            "state": NSStringFromSelector(#selector(state(_:))),
        ]
    }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?

    private var status: String = "idle"
    private var pendingEnded = false
    private var pendingError: String?
    private var pendingCommand: [String: Any]?
    private var nowPlaying: [String: Any] = [:]

    override init() {
        super.init()
        commonSetup()
    }

    init(param: Any) {
        super.init()
        _ = param
        commonSetup()
    }

    private func commonSetup() {
        setupSession()
        setupRemoteCommands()
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            switch self.player.timeControlStatus {
            case .playing: self.status = "playing"
            case .waitingToPlayAtSpecifiedRate: self.status = "buffering"
            default: self.status = self.player.currentItem == nil ? "idle" : "paused"
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time.seconds
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        statusObserver?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    // MARK: - JS 方法

    func load(_ url: String, title: String, artist: String, cover: String, duration: Double) {
        onMain {
            self.pendingEnded = false
            self.pendingError = nil
            guard let u = URL(string: url) else {
                self.pendingError = "无效的音频地址"
                return
            }
            let item = AVPlayerItem(url: u)
            self.player.replaceCurrentItem(with: item)
            self.status = "loading"
            self.nowPlaying = [
                MPMediaItemPropertyTitle: title,
                MPMediaItemPropertyArtist: artist,
                MPMediaItemPropertyPlaybackDuration: duration,
            ]
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlaying
            if !cover.isEmpty, let coverUrl = URL(string: cover) {
                self.loadArtwork(coverUrl)
            }

            self.endObserver.map { NotificationCenter.default.removeObserver($0) }
            self.endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                self?.pendingEnded = true
                self?.status = "paused"
            }
        }
    }

    /// 播放本机文件（已下载的音频）：路径直接交给 URL(fileURLWithPath:)，
    /// 空格/中文不需要 JS 侧做百分号编码。
    func loadLocal(_ path: String, title: String, artist: String) {
        onMain {
            self.pendingEnded = false
            self.pendingError = nil
            let fileURL = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                self.pendingError = "文件不存在：" + path
                return
            }
            NSLog("[TinyMusic] audio.loadLocal path=\(path)")
            let item = AVPlayerItem(url: fileURL)
            self.player.replaceCurrentItem(with: item)
            self.status = "loading"
            self.nowPlaying = [
                MPMediaItemPropertyTitle: title,
                MPMediaItemPropertyArtist: artist,
            ]
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlaying
            self.endObserver.map { NotificationCenter.default.removeObserver($0) }
            self.endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                self?.pendingEnded = true
                self?.status = "paused"
            }
        }
    }

    func play() {
        onMain {
            NSLog("[TinyMusic] audio.play()")
            self.player.play()
            self.status = "playing"
        }
    }

    func pause() {
        onMain {
            self.player.pause()
            self.status = "paused"
        }
    }

    func seek(_ seconds: Double) {
        onMain {
            let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            self.player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func setVolume(_ v: Double) {
        onMain { self.player.volume = Float(max(0, min(1, v))) }
    }

    func stop() {
        onMain {
            self.player.pause()
            self.player.replaceCurrentItem(with: nil)
            self.status = "idle"
            self.pendingEnded = false
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    /// 轮询入口：把播放状态 / 进度 / 一次性事件打包成 JSON 回调给 JS。
    func state(_ cb: @escaping (Any?) -> Void) {
        var payload: [String: Any] = [:]
        DispatchQueue.main.sync {
            let duration = self.player.currentItem?.duration.seconds ?? 0
            let position = self.player.currentTime().seconds
            payload["status"] = self.status
            payload["position"] = position.isFinite ? position : 0
            payload["duration"] = duration.isFinite ? duration : 0
            if self.pendingEnded {
                payload["ended"] = true
                self.pendingEnded = false
            }
            if let error = self.pendingError {
                payload["error"] = error
                self.pendingError = nil
            }
            if let command = self.pendingCommand {
                payload["command"] = command
                self.pendingCommand = nil
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            cb(json)
        } else {
            cb("{}")
        }
    }

    // MARK: - 线程

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    // MARK: - 音频会话 / 锁屏

    private func setupSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            NSLog("[TinyMusic] 音频会话初始化失败: \(error.localizedDescription)")
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: nil
        )
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.pendingCommand = ["name": "play"]
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pendingCommand = ["name": "pause"]
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.pendingCommand = ["name": "next"]
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.pendingCommand = ["name": "prev"]
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                self?.pendingCommand = ["name": "seek", "value": e.positionTime]
            }
            return .success
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            player.pause()
            status = "paused"
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable {
            player.pause()
            status = "paused"
        }
    }

    private func loadArtwork(_ url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = art
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }.resume()
    }
}
