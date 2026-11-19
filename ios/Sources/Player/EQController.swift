import Foundation
import AVFoundation
import Observation

struct EQState: Codable, Sendable {
    var enabled: Bool = false
    var gains: [Float] = EQLibrary.flatGains
    var preamp: Float = 0
    var presetID: String = "flat"
}

@MainActor
@Observable
final class EQController {
    private static let storageKey = "tinymusic.eq.native"

    private(set) var state: EQState
    let processor = EQProcessor()
    var onChange: ((EQState) -> Void)?
    /// 拖动滑块时的落盘防抖（见 `persist(notify:debounced:)`）。
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    var enabled: Bool { state.enabled }
    var gains: [Float] { state.gains }
    var preamp: Float { state.preamp }
    var presetID: String { state.presetID }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(EQState.self, from: data),
           saved.gains.count == EQLibrary.bands.count {
            state = saved
        } else {
            state = EQState()
        }
        applyToProcessor()
    }

    func setEnabled(_ enabled: Bool) {
        state.enabled = enabled
        applyToProcessor()
        persist()
    }

    func apply(_ remote: EQState) {
        guard remote.gains.count == EQLibrary.bands.count else { return }
        state = EQState(
            enabled: remote.enabled,
            gains: remote.gains.map(EQLibrary.clamp),
            preamp: EQLibrary.clamp(remote.preamp),
            presetID: EQLibrary.detect(gains: remote.gains.map(EQLibrary.clamp), preamp: EQLibrary.clamp(remote.preamp)) ?? "custom"
        )
        applyToProcessor()
        persist(notify: false)
    }

    func setGain(index: Int, value: Float) {
        guard state.gains.indices.contains(index) else { return }
        state.gains[index] = EQLibrary.clamp(value)
        state.presetID = EQLibrary.detect(gains: state.gains, preamp: state.preamp) ?? "custom"
        applyToProcessor()
        persist(debounced: true)
    }

    func setPreamp(_ value: Float) {
        state.preamp = EQLibrary.clamp(value)
        state.presetID = EQLibrary.detect(gains: state.gains, preamp: state.preamp) ?? "custom"
        applyToProcessor()
        persist(debounced: true)
    }

    func applyPreset(_ id: String) {
        guard let preset = EQLibrary.presetDefinition(id: id) else { return }
        state.gains = preset.gains
        state.preamp = preset.preamp
        state.presetID = preset.id
        state.enabled = true
        applyToProcessor()
        persist()
    }

    func reset() {
        state = EQState()
        applyToProcessor()
        persist()
    }

    private func applyToProcessor() {
        processor.set(enabled: state.enabled, gains: state.gains, preampDB: state.preamp)
    }

    /// `debounced` 只给滑块拖动用：`setGain` / `setPreamp` 每帧都会走到这里，
    /// 而 `applyToProcessor()` 才是音频必须的那一步（已经同步做了）。
    /// 落盘（JSON 编码 + UserDefaults 写）和上云通知都没必要每帧一次。
    private func persist(notify: Bool = true, debounced: Bool = false) {
        persistTask?.cancel()
        if debounced {
            persistTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled else { return }
                self.writeToDisk()
                if notify { self.onChange?(self.state) }
            }
            return
        }
        writeToDisk()
        if notify { onChange?(state) }
    }

    /// 立刻落盘并补发一次变更通知：离开均衡器页时调用，
    /// 别把用户刚拖的档位留在防抖窗口里（否则关 App 就丢了，iCloud 也不会收到）。
    func flush() {
        let hadPending = persistTask != nil
        persistTask?.cancel()
        persistTask = nil
        writeToDisk()
        if hadPending { onChange?(state) }
    }

    private func writeToDisk() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// 把 MTAudioProcessingTap 挂到当前 AVPlayerItem 上；失败静默跳过，不影响播放。
    func attach(to item: AVPlayerItem) {
        var callbacks = EQTap.callbacks(for: processor)

        var tap: MTAudioProcessingTap?
        let created = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap
        )
        guard created == noErr, let tap else { return }

        Task { @MainActor in
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
            let params = AVMutableAudioMixInputParameters(track: track)
            params.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            item.audioMix = mix
        }
    }
}
