import AVFoundation
import Accelerate

/// 10 段均衡器：挂在 AVPlayerItem 上的 MTAudioProcessingTap + 峰值 biquad 级联。
///
/// 之所以用音频处理 tap：播放走的是 AVPlayer（流代理/本地文件都走它），
/// AVAudioEngine 的 AVAudioUnitEQ 接不进来；tap 是 AVPlayer 唯一能插 DSP 的地方。
final class EQProcessor {
    /// 和桌面一致的 10 个频段（Hz）
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    private(set) var enabled = false
    private var gains: [Float] = Array(repeating: 0, count: 10)
    private var preampDB: Float = 0

    private var sampleRate: Double = 44100
    private var channels: Int = 2
    /// 每个频段一组 (b0,b1,b2,a1,a2)
    private var coeffs: [[Float]] = []
    /// 每个频段每个声道的状态 (z1,z2)
    private var state: [[Float]] = []

    private let lock = NSLock()

    func set(enabled: Bool, gains: [Float], preampDB: Float) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled
        if gains.count == Self.frequencies.count {
            self.gains = gains
        }
        self.preampDB = preampDB
        rebuildCoefficientsLocked()
    }

    func prepare(format: AudioStreamBasicDescription) {
        lock.lock(); defer { lock.unlock() }
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44100
        channels = Int(max(1, format.mChannelsPerFrame))
        state = Array(repeating: Array(repeating: 0, count: channels * 2), count: Self.frequencies.count)
        rebuildCoefficientsLocked()
    }

    /// 峰值 EQ 系数（RBJ cookbook）
    private func rebuildCoefficientsLocked() {
        guard sampleRate > 0 else { return }
        var out: [[Float]] = []
        out.reserveCapacity(Self.frequencies.count)
        for (i, freq) in Self.frequencies.enumerated() {
            let gain = gains[i]
            let a = pow(10, gain / 40)
            let w0 = 2 * Double.pi * Double(freq) / sampleRate
            let alpha = sin(w0) / (2 * 1.0) // Q = 1
            let cosw0 = cos(w0)
            let b0 = 1 + alpha * Double(a)
            let b1 = -2 * cosw0
            let b2 = 1 - alpha * Double(a)
            let a0 = 1 + alpha / Double(a)
            let a1 = -2 * cosw0
            let a2 = 1 - alpha / Double(a)
            out.append([
                Float(b0 / a0), Float(b1 / a0), Float(b2 / a0), Float(a1 / a0), Float(a2 / a0),
            ])
        }
        coeffs = out
    }

    /// 原地处理一段音频（interleaved / non-interleaved 都支持）
    func process(frames: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) {
        lock.lock(); defer { lock.unlock() }
        guard enabled, !coeffs.isEmpty, frames > 0 else { return }

        let preamp = pow(10, preampDB / 20)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)

        for buffer in buffers {
            guard let raw = buffer.mData else { continue }
            let floats = raw.assumingMemoryBound(to: Float.self)
            let stride = buffer.mNumberChannels > 0 ? Int(buffer.mNumberChannels) : 1
            for frame in 0..<frames {
                for ch in 0..<stride {
                    let idx = frame * stride + ch
                    var sample = floats[idx] * preamp
                    for band in 0..<coeffs.count {
                        let c = coeffs[band]
                        let s1 = state[band][min(ch * 2, state[band].count - 1)]
                        let s2 = state[band][min(ch * 2 + 1, state[band].count - 1)]
                        let out = c[0] * sample + s1
                        state[band][min(ch * 2, state[band].count - 1)] = c[1] * sample - c[3] * out + s2
                        state[band][min(ch * 2 + 1, state[band].count - 1)] = c[2] * sample - c[4] * out
                        sample = out
                    }
                    floats[idx] = sample
                }
            }
        }
    }
}
