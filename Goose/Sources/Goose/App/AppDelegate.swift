import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: OverlayWindow?
    private var statusItem: NSStatusItem?
    private var escMonitor: EscQuitMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusBarItem()
        setUpOverlayWindow()
        setUpEscMonitor()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setUpStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🪿"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Goose", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func setUpOverlayWindow() {
        let window = OverlayWindow()
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window
    }

    private func setUpEscMonitor() {
        escMonitor = EscQuitMonitor(window: overlayWindow) { [weak self] in
            self?.quit()
        }
        escMonitor?.start()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
