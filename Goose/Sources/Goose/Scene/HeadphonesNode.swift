import AppKit
import SpriteKit

/// Pixel-art headphones overlay rendered with `SKShapeNode` (no antialiasing,
/// chunky lines) so it sits cleanly on top of the goose without clashing with
/// the spritesheet aesthetic. Tracks the rig's `neckHeadPoint` each frame.
@MainActor
final class HeadphonesNode: SKNode {
    private let band = SKShapeNode()
    private let leftCup = SKShapeNode(circleOfRadius: 3.5)
    private let rightCup = SKShapeNode(circleOfRadius: 3.5)
    private static let cupOffset: CGFloat = 5

    override init() {
        super.init()
        zPosition = 12
        alpha = 0
        isHidden = true
        buildBand()
        buildCups()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    func show() {
        isHidden = false
        removeAllActions()
        run(.fadeIn(withDuration: 0.25))
    }

    func hide() {
        removeAllActions()
        run(.sequence([
            .fadeOut(withDuration: 0.25),
            .run { [weak self] in self?.isHidden = true },
        ]))
    }

    /// Position + orient relative to the head. Called every frame from
    /// `GooseScene.update`.
    func update(headPoint: CGPoint, perpendicular: CGPoint) {
        position = CGPoint(x: headPoint.x, y: headPoint.y + 1)
        leftCup.position = CGPoint(x: -perpendicular.x * Self.cupOffset, y: -perpendicular.y * Self.cupOffset)
        rightCup.position = CGPoint(x: perpendicular.x * Self.cupOffset, y: perpendicular.y * Self.cupOffset)
    }

    private func buildBand() {
        let path = CGMutablePath()
        path.addArc(
            center: .zero,
            radius: Self.cupOffset + 0.5,
            startAngle: 0,
            endAngle: .pi,
            clockwise: false
        )
        band.path = path
        band.strokeColor = NSColor.black
        band.fillColor = .clear
        band.lineWidth = 2
        band.isAntialiased = false
        band.lineCap = .round
        addChild(band)
    }

    private func buildCups() {
        for cup in [leftCup, rightCup] {
            cup.fillColor = NSColor.black
            cup.strokeColor = NSColor(white: 0.25, alpha: 1)
            cup.lineWidth = 1
            cup.isAntialiased = false
            addChild(cup)
        }
    }
}
