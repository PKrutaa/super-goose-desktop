import Foundation

/// Fisher-Yates shuffled index deck. Returns each index exactly once before
/// reshuffling, used by the goose's task picker so behaviors don't repeat
/// in a row by chance.
final class Deck {
    private(set) var indices: [Int]
    private var cursor: Int = 0

    init(length: Int) {
        self.indices = Array(0..<max(0, length))
        reshuffle()
    }

    func reshuffle() {
        for i in 0..<indices.count {
            indices[i] = i
            let swap = SamMath.randomInt(upTo: i + 1)
            indices.swapAt(i, swap)
        }
    }

    func next() -> Int {
        guard !indices.isEmpty else { return 0 }
        let result = indices[cursor]
        cursor += 1
        if cursor >= indices.count {
            reshuffle()
            cursor = 0
        }
        return result
    }
}
