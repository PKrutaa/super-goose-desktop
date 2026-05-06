import AppKit
import CoreGraphics

@MainActor
final class EscQuitMonitor {
    private static let escapeKeyCode: CGKeyCode = 53
    private static let holdDurationToQuit: TimeInterval = 1.5
    private static let pollInterval: TimeInterval = 1.0 / 60.0
    private static let decayPerTick: CGFloat = 0.05

    private weak var window: OverlayWindow?
    private let onQuit: () -> Void
    private var timer: Timer?
    private var holdProgress: CGFloat = 0

    init(window: OverlayWindow?, onQuit: @escaping () -> Void) {
        self.window = window
        self.onQuit = onQuit
    }

    func start() {
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let pressed = CGEventSource.keyState(.combinedSessionState, key: Self.escapeKeyCode)
        if pressed {
            holdProgress = min(1.0, holdProgress + CGFloat(Self.pollInterval / Self.holdDurationToQuit))
        } else {
            holdProgress = max(0, holdProgress - Self.decayPerTick)
        }

        window?.gooseScene.setEvictProgress(holdProgress)

        if holdProgress >= 1.0 {
            stop()
            onQuit()
        }
    }
}
