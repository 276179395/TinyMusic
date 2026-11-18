import Testing
@testable import TinyMusic

struct PlaybackQueueTests {
    @Test func endedStopsAtEndWhenRepeatOff() {
        #expect(PlaybackQueue.nextIndexOnEnded(length: 3, index: 2, shuffle: false, repeatMode: .off) == nil)
    }

    @Test func endedWrapsWhenRepeatAll() {
        #expect(PlaybackQueue.nextIndexOnEnded(length: 3, index: 2, shuffle: false, repeatMode: .all) == 0)
    }

    @Test func manualNextAlwaysWraps() {
        #expect(PlaybackQueue.nextIndexManual(length: 3, index: 2, shuffle: false) == 0)
    }

    @Test func manualPreviousWraps() {
        #expect(PlaybackQueue.prevIndexManual(length: 3, index: 0, shuffle: false) == 2)
    }

    @Test func shuffleNeverPicksCurrentWhenPossible() {
        var sequence = [0.0, 0.0, 0.9]
        let target = PlaybackQueue.nextIndexOnEnded(length: 3, index: 0, shuffle: true, repeatMode: .off) {
            sequence.removeFirst()
        }
        #expect(target == 2)
    }

    @Test func removeCurrentPicksNext() {
        let result = PlaybackQueue.queueAfterRemove(["a", "b", "c"], index: 1, removeAt: 1)
        #expect(result?.queue == ["a", "c"])
        #expect(result?.index == 1)
        #expect(result?.playTarget == 1)
    }

    @Test func removeBeforeCurrentMovesIndexBack() {
        let result = PlaybackQueue.queueAfterRemove(["a", "b", "c"], index: 2, removeAt: 0)
        #expect(result?.index == 1)
        #expect(result?.playTarget == nil)
    }

    @Test func removeLastCurrentHasNoTarget() {
        let result = PlaybackQueue.queueAfterRemove(["a"], index: 0, removeAt: 0)
        #expect(result?.queue.isEmpty == true)
        #expect(result?.playTarget == nil)
    }

    @Test func insertAfterCurrentMovesExisting() {
        let result = PlaybackQueue.queueInsertAfterCurrent(["a", "b", "c"], index: 0, track: "c") { $0 == $1 }
        #expect(result.queue == ["a", "c", "b"])
        #expect(result.at == 1)
    }

    @Test func insertBeforeCurrentFixesIndex() {
        let result = PlaybackQueue.queueInsertAfterCurrent(["a", "b", "c"], index: 2, track: "a") { $0 == $1 }
        #expect(result.queue == ["b", "c", "a"])
        #expect(result.index == 1)
    }
}
