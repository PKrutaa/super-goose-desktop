import CoreGraphics
import Foundation

enum SamMath {
    static let deg2Rad: CGFloat = .pi / 180
    static let rad2Deg: CGFloat = 180 / .pi

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a * (1 - t) + b * t
    }

    static func clamp(_ value: CGFloat, _ min: CGFloat, _ max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }

    static func randomRange(_ min: CGFloat, _ max: CGFloat) -> CGFloat {
        guard max > min else { return min }
        return CGFloat.random(in: min...max)
    }

    static func randomInt(upTo upperExclusive: Int) -> Int {
        guard upperExclusive > 0 else { return 0 }
        return Int.random(in: 0..<upperExclusive)
    }
}
