import AppKit
import SpriteKit

@MainActor
final class GooseScene: SKScene, GooseSceneEffects {
    private static let displayScale: CGFloat = 1.0

    let simulation = GooseSimulation()
    private let goose = GooseArt()
    private let audio = AudioPlayer()
    private let evictBar = EvictProgressBar()
    private let gooseContainer = SKNode()
    private let hearts = HeartParticles()
    private let headphones = HeadphonesNode()

    private var agent: AgentDirector?
    private var honkTicker: HonkTicker?
    private var chillingTicker: ChillingTicker?
    private let perception = PerceptionEngine()
    private var currentDraggedWindow: FloatingWindow?
    private var droppedWindows: [FloatingWindow] = []

    private var lastLeftMouseDown = false
    private var hoverStartTime: TimeInterval = -1
    private var lastHeartSpawnTime: TimeInterval = -1
    private static let clickRadius: CGFloat = 50
    private static let hoverRadius: CGFloat = 60
    private static let hoverDelay: TimeInterval = 0.5
    private static let heartCooldown: TimeInterval = 0.7
    private static let droppedWindowLifetime: TimeInterval = 25
    private static let droppedWindowFadeDuration: TimeInterval = 1.0

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0, y: 0)

        gooseContainer.setScale(Self.displayScale)
        gooseContainer.zPosition = 10
        gooseContainer.addChild(goose.node)
        gooseContainer.addChild(headphones)
        addChild(gooseContainer)

        evictBar.position = CGPoint(x: 16, y: size.height - 28)
        evictBar.zPosition = 100
        addChild(evictBar)

        hearts.zPosition = 70
        addChild(hearts)

        simulation.screenSize = size / Self.displayScale
        simulation.position = CGPoint(x: simulation.screenSize.width / 2, y: simulation.screenSize.height / 2)
        simulation.targetPos = simulation.position
        simulation.direction = 180
        simulation.lFootPos = simulation.footHome(rightFoot: false)
        simulation.rFootPos = simulation.footHome(rightFoot: true)
        simulation.onFootLand = { [weak audio] in audio?.playPat() }
        simulation.onHonk = { [weak audio] in audio?.playHonk() }
        simulation.onBite = { [weak audio] in audio?.playBite() }
        simulation.setTask(WanderTask())

        let personality = Personality.default
        let fmClient = FoundationModelClient()
        let brain = GooseBrain(personality: personality, fmClient: fmClient)
        let agent = AgentDirector(simulation: simulation, effects: self, perception: perception, brain: brain)
        self.agent = agent
        agent.start()
        let ticker = HonkTicker(simulation: simulation, perception: perception)
        ticker.start()
        self.honkTicker = ticker
        let chillTicker = ChillingTicker(
            simulation: simulation,
            perception: perception,
            effects: self,
            personality: personality,
            fmClient: fmClient
        )
        chillTicker.start()
        self.chillingTicker = chillTicker
    }

    override func update(_ currentTime: TimeInterval) {
        pollMouseInteraction()
        simulation.tick()
        goose.update(simulation: simulation)
        var rig = GooseRig()
        rig.update(position: simulation.position, directionDegrees: simulation.direction, neckLerp: simulation.neckLerpPercent)
        headphones.update(headPoint: rig.neckHeadPoint, perpendicular: rig.perpendicular)
    }

    override func willMove(from view: SKView) {
        agent?.stop()
        honkTicker?.stop()
        chillingTicker?.stop()
    }

    private func pollMouseInteraction() {
        let mouse = NSEvent.mouseLocation
        let goosePos = simulation.position
        let dist = CGPoint.distance(mouse, goosePos)
        let now = Double(GameTime.time)

        let leftPressed = NSEvent.pressedMouseButtons & 1 != 0
        let risingEdge = leftPressed && !lastLeftMouseDown
        lastLeftMouseDown = leftPressed

        if risingEdge, dist < Self.clickRadius, !(simulation.currentTask is NabMouseTask) {
            simulation.setTask(NabMouseTask())
            return
        }

        if dist < Self.hoverRadius {
            if hoverStartTime < 0 {
                hoverStartTime = now
                lastHeartSpawnTime = -1
            }
            let hovered = now - hoverStartTime
            let cooldownElapsed = now - lastHeartSpawnTime
            if hovered > Self.hoverDelay, cooldownElapsed > Self.heartCooldown {
                hearts.spawn(at: CGPoint(x: goosePos.x, y: goosePos.y + 40))
                audio.playPat()
                lastHeartSpawnTime = now
            }
        } else {
            hoverStartTime = -1
        }
    }

    func setEvictProgress(_ progress: CGFloat) {
        evictBar.setProgress(progress)
    }

    // MARK: - GooseSceneEffects (Native window dragging)

    func attachDraggedWindow(_ window: FloatingWindow, at point: CGPoint, direction: CGFloat) {
        currentDraggedWindow?.closeWithFade(duration: 0.3)
        currentDraggedWindow = window
        window.window.alphaValue = 0
        window.setCenter(windowCenter(beak: point, direction: direction, windowSize: window.size))
        window.show()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.window.animator().alphaValue = 1
        }
    }

    func updateDraggedWindowPosition(_ point: CGPoint, direction: CGFloat) {
        guard let window = currentDraggedWindow else { return }
        window.setCenter(windowCenter(beak: point, direction: direction, windowSize: window.size))
    }

    func setHeadphones(visible: Bool) {
        if visible { headphones.show() } else { headphones.hide() }
    }

    func detachDraggedWindow() {
        guard let window = currentDraggedWindow else { return }
        currentDraggedWindow = nil
        droppedWindows.append(window)
        let toRemove = window
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.droppedWindowLifetime) { [weak self] in
            self?.fadeOutDroppedWindow(toRemove)
        }
    }

    private func fadeOutDroppedWindow(_ window: FloatingWindow) {
        droppedWindows.removeAll { $0 === window }
        window.closeWithFade(duration: Self.droppedWindowFadeDuration)
    }

    // MARK: - Helpers

    /// Places a window's center ahead of the goose's beak in the direction it
    /// is facing, so the window appears to be carried by the goose.
    private func windowCenter(beak: CGPoint, direction: CGFloat, windowSize: CGSize) -> CGPoint {
        let forward = CGPoint.fromAngleDegrees(direction)
        let offset = max(windowSize.width, windowSize.height) / 2 + 20
        return CGPoint(
            x: beak.x + forward.x * offset,
            y: beak.y + forward.y * offset + 10
        )
    }
}

private func / (size: CGSize, scale: CGFloat) -> CGSize {
    CGSize(width: size.width / scale, height: size.height / scale)
}

@MainActor
private final class EvictProgressBar: SKNode {
    private static let width: CGFloat = 320
    private static let height: CGFloat = 24

    private let background = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 4)
    private let fill = SKShapeNode()
    private let label = SKLabelNode(text: "Continue holding ESC to evict goose")

    override init() {
        super.init()
        background.fillColor = NSColor(calibratedRed: 0.72, green: 0.86, blue: 0.95, alpha: 1)
        background.strokeColor = .clear
        background.position = CGPoint(x: Self.width / 2, y: Self.height / 2)

        fill.fillColor = NSColor(calibratedRed: 1, green: 0.72, blue: 0.78, alpha: 1)
        fill.strokeColor = .clear

        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 13
        label.fontColor = NSColor(white: 0.15, alpha: 1)
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 8, y: Self.height / 2)

        addChild(background)
        addChild(fill)
        addChild(label)
        alpha = 0
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("not used")
    }

    func setProgress(_ progress: CGFloat) {
        let clamped = max(0, min(1, progress))
        alpha = clamped > 0.05 ? min(1, (clamped - 0.05) / 0.15) : 0

        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: Self.width * clamped, height: Self.height))
        fill.path = path
    }
}
