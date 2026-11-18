import Testing
@testable import TinyMusic

struct LyricsStoreTests {
    private let lines = [
        LyricLine(timeMs: 1000, text: "one"),
        LyricLine(timeMs: 2000, text: "two"),
        LyricLine(timeMs: 3000, text: "three"),
    ]

    @Test func beforeFirstIsMinusOne() {
        #expect(LyricsStore.activeIndex(lines: lines, positionMs: 500) == -1)
    }

    @Test func leadAllowsSlightlyEarlyLine() {
        #expect(LyricsStore.activeIndex(lines: lines, positionMs: 1950) == 1)
    }

    @Test func exactLineHits() {
        #expect(LyricsStore.activeIndex(lines: lines, positionMs: 2000) == 1)
    }

    @Test func afterLastIsLast() {
        #expect(LyricsStore.activeIndex(lines: lines, positionMs: 9999) == 2)
    }

    @Test func emptyReturnsMinusOne() {
        #expect(LyricsStore.activeIndex(lines: [], positionMs: 0) == -1)
    }
}
