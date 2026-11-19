import Foundation

struct EQPreset: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let desc: String
    let gains: [Float]
    let preamp: Float
}

enum EQLibrary {
    static let bands: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let minDB: Float = -12
    static let maxDB: Float = 12
    static let flatGains: [Float] = Array(repeating: 0, count: 10)

    /// 预设名和说明是本地化文案，每次读取时按当前语言生成（12 个轻量结构体），
    /// 这样在设置页切语言后均衡器里的预设名会立即刷新。
    static var presets: [EQPreset] {
        [
            EQPreset(id: "flat", name: L("平直"), desc: L("不染色，所有频段 0 dB"), gains: flatGains, preamp: 0),
            EQPreset(id: "pop", name: L("流行"), desc: L("人声和中高频更靠前，低频收一点"), gains: [-1, 0, 2, 3.5, 3.5, 2, 0.5, -1, -1.5, -2], preamp: -3),
            EQPreset(id: "rock", name: L("摇滚"), desc: L("经典微笑曲线：鼓和贝斯更重，吉他更亮"), gains: [4, 3, 2, 0, -1, -1, 0, 2, 3, 4], preamp: -4),
            EQPreset(id: "jazz", name: L("爵士"), desc: L("温暖的低频和铜管，中频略退"), gains: [3, 2, 0, 1, -1, -1, 0, 1, 2, 2.5], preamp: -3),
            EQPreset(id: "classical", name: L("古典"), desc: L("保留厅堂感，弦乐和空气感更清晰"), gains: [3.5, 3, 2, 1, 0, 0, -0.5, 0, 2, 3], preamp: -3),
            EQPreset(id: "electronic", name: L("电子"), desc: L("下潜和 hi-hat 都更突出"), gains: [5, 4, 1, -1, -2, 0, 1, 3, 4, 5], preamp: -4),
            EQPreset(id: "hiphop", name: L("嘻哈"), desc: L("808 和底鼓更厚，顶部保留咬字"), gains: [6, 5, 2, 0, -1, 0, 1, 2, 3, 3], preamp: -5),
            EQPreset(id: "vocal", name: L("人声"), desc: L("突出中频，压低低频和齿音"), gains: [-2, -2, -1, 1, 3, 4, 4, 2, 0, -1], preamp: -3),
            EQPreset(id: "acoustic", name: L("原声"), desc: L("木吉他和人声都自然、靠前"), gains: [3, 2, 1, 1, 2, 2, 1.5, 1, 1.5, 2], preamp: -2),
            EQPreset(id: "bass", name: L("低音增强"), desc: L("只抬低频，适合鼓点和小音箱"), gains: [8, 7, 5, 3, 1, 0, 0, 0, 0, 0], preamp: -7),
            EQPreset(id: "treble", name: L("高音增强"), desc: L("更亮的高频，适合闷的耳机"), gains: [0, 0, 0, 0, 0, 0, 1, 3, 5, 6], preamp: -4),
            EQPreset(id: "loudness", name: L("响度"), desc: L("小音量下补足两端，中频略退"), gains: [6, 4, 1, -2, -1, 1, 3, 4, 5, 5], preamp: -6),
        ]
    }

    static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(minDB, min(maxDB, (value * 2).rounded() / 2))
    }

    static func preset(id: String) -> EQPreset? {
        presets.first { $0.id == id }
    }

    static func detect(gains: [Float], preamp: Float) -> String? {
        presets.first { preset in
            preset.gains.count == gains.count
                && zip(preset.gains, gains).allSatisfy { abs($0 - $1) < 0.01 }
                && abs(preset.preamp - preamp) < 0.01
        }?.id
    }
}
