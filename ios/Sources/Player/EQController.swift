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
        persist()
    }

    func setPreamp(_ value: Float) {
        state.preamp = EQLibrary.clamp(value)
        state.presetID = EQLibrary.detect(gains: state.gains, preamp: state.preamp) ?? "custom"
        applyToProcessor()
        persist()
    }

    func applyPreset(_ id: String) {
        guard let preset = EQLibrary.preset(id: id) else { return }
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

    private func persist(notify: Bool = true) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        if notify { onChange?(state) }
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
