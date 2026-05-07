import AppKit
import SpriteKit

/// Emitter that spawns floating ♪ / ♫ notes around the goose while it chills.
///
/// `start()` begins a periodic spawn (one note every 0.7–1.4s) at whatever
/// `anchor` is at the moment of spawn. `stop()` halts spawns; existing notes
/// finish their float-and-fade naturally.
@MainActor
final class MusicNoteParticles: SKNode {
    private static let symbols: [String] = ["♪", "♫", "♬", "♩"]
    private static let colors: [NSColor] = [
        NSColor.black,
        NSColor(srgbRed: 0.9, green: 0.2, blue: 0.3, alpha: 1),    // punk red
        NSColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1),    // metal slate
        NSColor(srgbRed: 0.3, green: 0.6, blue: 0.9, alpha: 1),    // pop blue
    ]

    private var anchor: () -> CGPoint = { .zero }
    private var spawnAction: SKAction?

    override init() {
        super.init()
        zPosition = 11
    }

    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// Begin spawning notes. `anchor` is queried at every spawn so notes appear
    /// near the goose's current head position even if it (slightly) moves.
    func start(anchor: @escaping @MainActor () -> CGPoint) {
        self.anchor = anchor
        stop()
        let spawn = SKAction.run { [weak self] in self?.emit() }
        let wait = SKAction.wait(forDuration: 1.0, withRange: 0.7)
        let loop = SKAction.repeatForever(.sequence([spawn, wait]))
        spawnAction = loop
        run(loop, withKey: "spawn")
    }

    func stop() {
        removeAction(forKey: "spawn")
        spawnAction = nil
    }

    private func emit() {
        let base = anchor()
        let jitterX = CGFloat.random(in: -10...10)
        let jitterY = CGFloat.random(in: -2...4)
        let spawnPoint = CGPoint(x: base.x + jitterX, y: base.y + 8 + jitterY)

        let note = SKLabelNode(text: Self.symbols.randomElement() ?? "♪")
        note.fontName = "Menlo-Bold"
        note.fontSize = 14
        note.fontColor = Self.colors.randomElement() ?? .black
        note.horizontalAlignmentMode = .center
        note.verticalAlignmentMode = .center
        note.position = spawnPoint
        note.alpha = 0
        note.setScale(0.6)
        addChild(note)

        let duration = TimeInterval.random(in: 1.4...2.0)
        let rise = CGFloat.random(in: 36...58)
        let driftX = CGFloat.random(in: -16...16)
        let wobblePhase = CGFloat.random(in: 0...(.pi * 2))
        let wobbleAmp: CGFloat = 5
        let rotateAmp: CGFloat = .pi / 12

        let float = SKAction.customAction(withDuration: duration) { node, elapsed in
            let p = min(1, elapsed / CGFloat(duration))
            let easedRise = 1 - pow(1 - p, 2)
            let dy = rise * easedRise
            let dx = driftX * p + sin(wobblePhase + p * .pi * 2) * wobbleAmp
            node.position = CGPoint(x: spawnPoint.x + dx, y: spawnPoint.y + dy)
            node.zRotation = sin(wobblePhase + p * .pi * 4) * rotateAmp
        }

        let popIn = SKAction.group([
            .fadeIn(withDuration: 0.2),
            .scale(to: 1.0, duration: 0.2),
        ])
        popIn.timingMode = .easeOut

        let fadeOut = SKAction.fadeOut(withDuration: max(0.3, duration - 0.4))
        fadeOut.timingMode = .easeIn

        note.run(.group([float, .sequence([popIn, fadeOut])])) {
            note.removeFromParent()
        }
    }
}
