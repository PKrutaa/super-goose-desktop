import Foundation
import QuartzCore

/// Monotonic game clock. Tick once per frame from the run loop.
/// `time` is seconds since process start; `deltaTime` is the fixed simulation
/// step the goose runs at (matches the original 120fps logic).
@MainActor
enum GameTime {
    static let frameRate: Int = 60
    static let deltaTime: CGFloat = 1.0 / 60.0

    private static let start = CACurrentMediaTime()
    private(set) static var time: CGFloat = 0

    static func tick() {
        time = CGFloat(CACurrentMediaTime() - start)
    }
}
