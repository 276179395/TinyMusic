import Testing
@testable import TinyMusic

struct EQTests {
    @Test func everyPresetHasTenBands() {
        for preset in EQLibrary.presets {
            #expect(preset.gains.count == 10)
            #expect(preset.gains.allSatisfy { $0 >= EQLibrary.minDB && $0 <= EQLibrary.maxDB })
        }
    }

    @Test func flatIsDetected() {
        #expect(EQLibrary.detect(gains: EQLibrary.flatGains, preamp: 0) == "flat")
    }

    @Test func rockIsDetected() {
        let rock = EQLibrary.preset(id: "rock")!
        #expect(EQLibrary.detect(gains: rock.gains, preamp: rock.preamp) == "rock")
    }

    @Test func customGainIsNotDetected() {
        var gains = EQLibrary.flatGains
        gains[3] = 5
        #expect(EQLibrary.detect(gains: gains, preamp: 0) == nil)
    }

    @Test func clampRoundsToHalfStepAndBounds() {
        #expect(EQLibrary.clamp(3.26) == 3.5)
        #expect(EQLibrary.clamp(-99) == -12)
        #expect(EQLibrary.clamp(99) == 12)
        #expect(EQLibrary.clamp(.nan) == 0)
    }
}
