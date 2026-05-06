import CoreGraphics
import Foundation

/// Math operators and helpers for `CGPoint`, used as the goose's 2D vector type.
/// Mirrors the API surface of `SamEngine.Vector2` from the original C# source.

func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
prefix func - (a: CGPoint) -> CGPoint { CGPoint(x: -a.x, y: -a.y) }
func * (a: CGPoint, b: CGFloat) -> CGPoint { CGPoint(x: a.x * b, y: a.y * b) }
func * (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x * b.x, y: a.y * b.y) }
func / (a: CGPoint, b: CGFloat) -> CGPoint { CGPoint(x: a.x / b, y: a.y / b) }
func += (a: inout CGPoint, b: CGPoint) { a = a + b }
func -= (a: inout CGPoint, b: CGPoint) { a = a - b }

extension CGPoint {
    static let zero2 = CGPoint(x: 0, y: 0)

    static func fromAngleDegrees(_ degrees: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: cos(radians), y: sin(radians))
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: SamMath.lerp(a.x, b.x, t), y: SamMath.lerp(a.y, b.y, t))
    }

    static func normalize(_ v: CGPoint) -> CGPoint {
        if v.x == 0, v.y == 0 { return .zero2 }
        let m = (v.x * v.x + v.y * v.y).squareRoot()
        return CGPoint(x: v.x / m, y: v.y / m)
    }

    static func magnitude(_ v: CGPoint) -> CGFloat {
        (v.x * v.x + v.y * v.y).squareRoot()
    }

    static func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        a.x * b.x + a.y * b.y
    }
}
