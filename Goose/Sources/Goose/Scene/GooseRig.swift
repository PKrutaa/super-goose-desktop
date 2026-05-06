import CoreGraphics
import Foundation

/// Skeletal rig describing the goose's body parts as 2D points in world space.
/// Ported from `TheGoose.UpdateRig` in the original C# (y-down) source,
/// adapted to SpriteKit's y-up coordinate system.
struct GooseRig {
    var underbodyCenter: CGPoint = .zero2
    var bodyCenter: CGPoint = .zero2
    var neckBase: CGPoint = .zero2
    var neckHeadPoint: CGPoint = .zero2
    var head1EndPoint: CGPoint = .zero2
    var head2EndPoint: CGPoint = .zero2

    var forward: CGPoint = CGPoint(x: 1, y: 0)
    var perpendicular: CGPoint = CGPoint(x: 0, y: -1)

    /// Rebuilds rig points around `position` (typically the feet level).
    /// `directionDegrees` follows standard math (0 = east, 90 = north in y-up).
    /// `neckLerp` ranges 0 (idle, neck retracted) to 1 (extended/running).
    mutating func update(position: CGPoint, directionDegrees: CGFloat, neckLerp: CGFloat) {
        let fwd = CGPoint.fromAngleDegrees(directionDegrees)
        let perp = CGPoint(x: fwd.y, y: -fwd.x)
        let up = CGPoint(x: 0, y: 1)

        forward = fwd
        perpendicular = perp

        bodyCenter = position + up * 14
        underbodyCenter = position + up * 9

        let neckLength = SamMath.lerp(20, 10, neckLerp)
        let neckForward = SamMath.lerp(3, 16, neckLerp)

        neckBase = bodyCenter + fwd * 15
        neckHeadPoint = neckBase + fwd * neckForward + up * neckLength
        head1EndPoint = neckHeadPoint + fwd * 3 - up * 1
        head2EndPoint = head1EndPoint + fwd * 5
    }
}
