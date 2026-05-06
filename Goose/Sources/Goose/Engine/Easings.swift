import CoreGraphics
import Foundation

/// Subset of Robert Penner-style easing functions used by the goose.
/// Add more here as new tasks need them.
enum Easings {
    static func linear(_ t: CGFloat) -> CGFloat { t }

    static func quadraticEaseInOut(_ t: CGFloat) -> CGFloat {
        if t < 0.5 { return 2 * t * t }
        return -2 * t * t + 4 * t - 1
    }

    static func cubicEaseInOut(_ t: CGFloat) -> CGFloat {
        if t < 0.5 { return 4 * t * t * t }
        let n = 2 * t - 2
        return 0.5 * n * n * n + 1
    }

    static func exponentialEaseOut(_ t: CGFloat) -> CGFloat {
        guard t != 1 else { return t }
        return 1 - pow(2, -10 * t)
    }

    static func sineEaseInOut(_ t: CGFloat) -> CGFloat {
        0.5 * (1 - cos(t * .pi))
    }
}
