import Foundation
import Observation

@MainActor
@Observable
final class LyricsStore {
    private(set) var lines: [LyricLine] = []
    private(set) var activeIndex = -1
    private(set) var loading = false
    private(set) var present = false
    private(set) var error: String?

    private var loadKey: String?

    func load(for track: Track) async {
        guard loadKey != track.key else { return }
        loadKey = track.key
        activeIndex = -1
        if let cached = CacheStore.shared.lyrics(for: track.key) {
            lines = cached
            present = !cached.isEmpty
            loading = false
            return
        }
        loading = true
        defer { loading = false }
        do {
            let result: LyricsResult = try await RustBackend.shared.call("s3_lyrics", [
                "key": .string(track.key),
            ])
            lines = result.lines
            present = result.present && !result.lines.isEmpty
            error = nil
        } catch {
            lines = []
            present = false
            self.error = error.localizedDescription
        }
    }

    func reset() {
        loadKey = nil
        lines = []
        activeIndex = -1
        present = false
        error = nil
    }

    func update(position: TimeInterval) {
        let next = Self.activeIndex(lines: lines, positionMs: Int(position * 1000))
        // 播放器每 0.25 秒推一次进度，歌词却要几秒才换一行。`@Observable` 不做等值判断，
        // 无条件赋值会让整个歌词列表每 0.25 秒重算一次。
        guard next != activeIndex else { return }
        activeIndex = next
    }

    nonisolated static func activeIndex(lines: [LyricLine], positionMs: Int) -> Int {
        guard !lines.isEmpty else { return -1 }
        let target = positionMs + 60
        var low = 0
        var high = lines.count - 1
        var answer = -1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].timeMs <= target {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }
}
