import Foundation

enum RepeatMode: String, CaseIterable, Sendable {
    case off
    case all
    case one

    var label: String {
        switch self {
        case .off: return "不循环"
        case .all: return "列表循环"
        case .one: return "单曲循环"
        }
    }
}

enum PlaybackQueue {
    static func nextIndexOnEnded(
        length: Int,
        index: Int,
        shuffle: Bool,
        repeatMode: RepeatMode,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> Int? {
        guard length > 0, index >= 0, index < length else { return nil }
        if shuffle {
            if length == 1 { return 0 }
            var candidate = index
            for _ in 0..<20 where candidate == index {
                candidate = Int(random() * Double(length))
            }
            return candidate == index ? (index + 1) % length : candidate
        }
        let next = index + 1
        if next < length { return next }
        return repeatMode == .all ? 0 : nil
    }

    static func nextIndexManual(
        length: Int,
        index: Int,
        shuffle: Bool,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> Int? {
        guard length > 0, index >= 0, index < length else { return nil }
        if shuffle {
            return nextIndexOnEnded(length: length, index: index, shuffle: true, repeatMode: .off, random: random)
        }
        return (index + 1) % length
    }

    static func prevIndexManual(
        length: Int,
        index: Int,
        shuffle: Bool,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> Int? {
        guard length > 0, index >= 0, index < length else { return nil }
        if shuffle {
            return nextIndexOnEnded(length: length, index: index, shuffle: true, repeatMode: .off, random: random)
        }
        return (index - 1 + length) % length
    }

    static func queueAfterRemove<T>(_ queue: [T], index: Int, removeAt: Int) -> (queue: [T], index: Int, playTarget: Int?)? {
        guard removeAt >= 0, removeAt < queue.count else { return nil }
        var next = queue
        next.remove(at: removeAt)
        let removingCurrent = removeAt == index
        var nextIndex = index
        if removeAt < index { nextIndex -= 1 }
        let playTarget: Int? = removingCurrent ? (next.isEmpty ? nil : min(removeAt, next.count - 1)) : nil
        return (next, nextIndex, playTarget)
    }

    static func queueInsertAfterCurrent<T>(_ queue: [T], index: Int, track: T, isSame: (T, T) -> Bool) -> (queue: [T], index: Int, at: Int) {
        var next = queue
        var current = index
        if let existing = next.firstIndex(where: { isSame($0, track) }) {
            next.remove(at: existing)
            if existing < current { current -= 1 }
        }
        let at = min(current + 1, next.count)
        next.insert(track, at: at)
        return (next, current, at)
    }
}
