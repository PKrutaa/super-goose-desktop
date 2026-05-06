import AppKit
import SpriteKit

@MainActor
final class OverlayWindow: NSWindow {
    let gooseScene: GooseScene

    init() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let scene = GooseScene(size: frame.size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        self.gooseScene = scene

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false

        let view = SKView(frame: frame)
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
