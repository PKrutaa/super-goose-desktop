import AppKit
import SpriteKit

@MainActor
final class GooseScene: SKScene, GooseSceneEffects {
    private static let displayScale: CGFloat = 1.0
    private static let browserScale: CGFloat = 0.55

    let simulation = GooseSimulation()
    private let goose = GooseArt()
    private let audio = AudioPlayer()
    private let evictBar = EvictProgressBar()
    private let gooseContainer = SKNode()
    private let hearts = HeartParticles()

    private var agent: AgentDirector?
    private var honkTicker: HonkTicker?
    private let perception = PerceptionEngine()
    private var currentBrowser: BrowserSprite?
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

        let brain = GooseBrain(personality: .default)
        let agent = AgentDirector(simulation: simulation, effects: self, perception: perception, brain: brain)
        self.agent = agent
        agent.start()
        let ticker = HonkTicker(simulation: simulation, perception: perception)
        ticker.start()
        self.honkTicker = ticker
    }

    override func update(_ currentTime: TimeInterval) {
        pollMouseInteraction()
        simulation.tick()
        goose.update(simulation: simulation)
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

    // MARK: - GooseSceneEffects (Browser)

    func openBrowser(near point: CGPoint) async {
        await closeBrowser()
        let browser = BrowserSprite()
        browser.setScale(0.01)
        browser.position = browserPosition()
        browser.zPosition = 60
        addChild(browser)
        currentBrowser = browser
        await browser.run(.scale(to: Self.browserScale, duration: 0.5))
    }

    func typeBrowserURL(_ text: String) async {
        guard let browser = currentBrowser else { return }
        await browser.typeURL(text)
    }

    func showBrowserResult(_ result: BrowseResult) async {
        guard let browser = currentBrowser else { return }
        let spinner = browser.showLoadingSpinner()
        spinner.removeFromParent()
        switch result.content {
        case .image(let url):
            if let sprite = await downloadImageSprite(from: url) {
                browser.showContent(sprite)
            } else {
                browser.showContent(textNode(snippet: "404 honk"))
            }
        case .text(let snippet):
            browser.showContent(textNode(snippet: snippet))
        }
    }

    func showBrowserError() async {
        currentBrowser?.showContent(textNode(snippet: "no internets honk"))
    }

    func closeBrowser() async {
        guard let browser = currentBrowser else { return }
        currentBrowser = nil
        await browser.run(.group([
            .scale(to: 0.01, duration: 0.4),
            .fadeOut(withDuration: 0.4)
        ]))
        browser.removeFromParent()
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

    private func browserPosition() -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2 + 60)
    }

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

    private func downloadImageSprite(from url: URL) async -> SKSpriteNode? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else {
            return nil
        }
        let texture = SKTexture(image: image)
        let sprite = SKSpriteNode(texture: texture)
        let maxDimension: CGFloat = 130
        let scaleFit = min(maxDimension / sprite.size.width, maxDimension / sprite.size.height)
        sprite.setScale(scaleFit)
        sprite.position = CGPoint(x: BrowserSprite.contentSize.width / 2, y: -BrowserSprite.contentSize.height / 2)
        return sprite
    }

    private func textNode(snippet: String) -> SKLabelNode {
        let label = SKLabelNode(text: snippet)
        label.fontName = "Menlo"
        label.fontSize = 9
        label.fontColor = NSColor(white: 0.2, alpha: 1)
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = BrowserSprite.contentSize.width - 16
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: 8, y: -8)
        return label
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
