import AppKit
import SpriteKit

/// Pink heart emitter used for "good goose" feedback (e.g. after a pat).
///
/// Each call to `spawn(at:count:)` adds short-lived heart sprites that float
/// upward, wobble sideways, scale-pop, fade out, and remove themselves.
@MainActor
final class HeartParticles: SKNode {
    private static let heartSize = CGSize(width: 12, height: 10)
    private static let heartPath: CGPath = makeHeartPath(size: heartSize)

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func spawn(at point: CGPoint, count: Int = 1) {
        for _ in 0..<count {
            addChild(makeHeart(spawnPoint: point))
        }
    }

    private func makeHeart(spawnPoint: CGPoint) -> SKShapeNode {
        let heart = SKShapeNode(path: Self.heartPath)
        heart.fillColor = .systemPink
        heart.strokeColor = .clear
        heart.alpha = 1
        heart.setScale(0.5)

        let jitterX = CGFloat.random(in: -4...4)
        let basePoint = CGPoint(x: spawnPoint.x + jitterX, y: spawnPoint.y)
        heart.position = basePoint

        let duration = TimeInterval.random(in: 1.0...1.4)
        let rise = CGFloat.random(in: 30...50)
        let wobbleAmplitude: CGFloat = 6
        let wobblePhase = CGFloat.random(in: 0...(.pi * 2))

        let float = SKAction.customAction(withDuration: duration) { node, elapsed in
            let progress = min(1, elapsed / CGFloat(duration))
            let easedRise = 1 - pow(1 - progress, 2)
            let dy = rise * easedRise
            let dx = sin(wobblePhase + progress * .pi * 2) * wobbleAmplitude
            node.position = CGPoint(x: basePoint.x + dx, y: basePoint.y + dy)
        }

        let popUp = SKAction.scale(to: 1.2, duration: 0.2)
        popUp.timingMode = .easeOut
        let settle = SKAction.scale(to: 0.8, duration: max(0.1, duration - 0.2))
        settle.timingMode = .easeInEaseOut
        let scaleSequence = SKAction.sequence([popUp, settle])

        let fade = SKAction.fadeOut(withDuration: duration)
        fade.timingMode = .easeOut

        let group = SKAction.group([float, scaleSequence, fade])
        heart.run(.sequence([group, .removeFromParent()]))
        return heart
    }

    private static func makeHeartPath(size: CGSize) -> CGPath {
        let w = size.width
        let h = size.height
        let bottom = CGPoint(x: 0, y: -h * 0.5)
        let topDip = CGPoint(x: 0, y: h * 0.3)

        let path = CGMutablePath()
        path.move(to: bottom)
        path.addCurve(
            to: topDip,
            control1: CGPoint(x: -w * 0.6, y: -h * 0.1),
            control2: CGPoint(x: -w * 0.6, y: h * 0.55)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: w * 0.6, y: h * 0.55),
            control2: CGPoint(x: w * 0.6, y: -h * 0.1)
        )
        path.closeSubpath()
        return path
    }
}
