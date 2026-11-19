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

    /// 预设本体（不含本地化文案）。
    ///
    /// 单独抽出来是因为 `detect` 在拖动均衡器滑块时每帧都要跑一遍，
    /// 而 `presets` 每次访问都会做 12 个预设 × 2 条文案 = 24 次 bundle 查表。
    /// 拖动 60 Hz 就是每秒 1440 次，全是白花的。
    struct EQPresetDefinition: Sendable {
        let id: String
        let nameKey: String
        let descKey: String
        let gains: [Float]
        let preamp: Float
    }

    static let definitions: [EQPresetDefinition] = [
        EQPresetDefinition(id: "flat", nameKey: "平直", descKey: "不染色，所有频段 0 dB", gains: flatGains, preamp: 0),
        EQPresetDefinition(id: "pop", nameKey: "流行", descKey: "人声和中高频更靠前，低频收一点", gains: [-1, 0, 2, 3.5, 3.5, 2, 0.5, -1, -1.5, -2], preamp: -3),
        EQPresetDefinition(id: "rock", nameKey: "摇滚", descKey: "经典微笑曲线：鼓和贝斯更重，吉他更亮", gains: [4, 3, 2, 0, -1, -1, 0, 2, 3, 4], preamp: -4),
        EQPresetDefinition(id: "jazz", nameKey: "爵士", descKey: "温暖的低频和铜管，中频略退", gains: [3, 2, 0, 1, -1, -1, 0, 1, 2, 2.5], preamp: -3),
        EQPresetDefinition(id: "classical", nameKey: "古典", descKey: "保留厅堂感，弦乐和空气感更清晰", gains: [3.5, 3, 2, 1, 0, 0, -0.5, 0, 2, 3], preamp: -3),
        EQPresetDefinition(id: "electronic", nameKey: "电子", descKey: "下潜和 hi-hat 都更突出", gains: [5, 4, 1, -1, -2, 0, 1, 3, 4, 5], preamp: -4),
        EQPresetDefinition(id: "hiphop", nameKey: "嘻哈", descKey: "808 和底鼓更厚，顶部保留咬字", gains: [6, 5, 2, 0, -1, 0, 1, 2, 3, 3], preamp: -5),
        EQPresetDefinition(id: "vocal", nameKey: "人声", descKey: "突出中频，压低低频和齿音", gains: [-2, -2, -1, 1, 3, 4, 4, 2, 0, -1], preamp: -3),
        EQPresetDefinition(id: "acoustic", nameKey: "原声", descKey: "木吉他和人声都自然、靠前", gains: [3, 2, 1, 1, 2, 2, 1.5, 1, 1.5, 2], preamp: -2),
        EQPresetDefinition(id: "bass", nameKey: "低音增强", descKey: "只抬低频，适合鼓点和小音箱", gains: [8, 7, 5, 3, 1, 0, 0, 0, 0, 0], preamp: -7),
        EQPresetDefinition(id: "treble", nameKey: "高音增强", descKey: "更亮的高频，适合闷的耳机", gains: [0, 0, 0, 0, 0, 0, 1, 3, 5, 6], preamp: -4),
        EQPresetDefinition(id: "loudness", nameKey: "响度", descKey: "小音量下补足两端，中频略退", gains: [6, 4, 1, -2, -1, 1, 3, 4, 5, 5], preamp: -6),
    ]

    /// 预设名和说明是本地化文案，每次读取时按当前语言生成（12 个轻量结构体），
    /// 这样在设置页切语言后均衡器里的预设名会立即刷新。
    ///
    /// 只给界面用；每帧都会跑的热路径（`detect` / `applyPreset`）请走 `definitions`。
    static var presets: [EQPreset] {
        definitions.map {
            EQPreset(id: $0.id, name: L($0.nameKey), desc: L($0.descKey), gains: $0.gains, preamp: $0.preamp)
        }
    }

    static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(minDB, min(maxDB, (value * 2).rounded() / 2))
    }

    /// 界面用的本地化预设（带名字和说明）。
    static func preset(id: String) -> EQPreset? {
        guard let definition = presetDefinition(id: id) else { return nil }
        return EQPreset(
            id: definition.id,
            name: L(definition.nameKey),
            desc: L(definition.descKey),
            gains: definition.gains,
            preamp: definition.preamp
        )
    }

    /// 热路径用：不碰本地化。
    static func presetDefinition(id: String) -> EQPresetDefinition? {
        definitions.first { $0.id == id }
    }

    static func detect(gains: [Float], preamp: Float) -> String? {
        definitions.first { definition in
            definition.gains.count == gains.count
                && zip(definition.gains, gains).allSatisfy { abs($0 - $1) < 0.01 }
                && abs(definition.preamp - preamp) < 0.01
        }?.id
    }
}
