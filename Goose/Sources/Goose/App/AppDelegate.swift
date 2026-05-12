import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: OverlayWindow?
    private var statusItem: NSStatusItem?
    private var escMonitor: EscQuitMonitor?
    private var moodItems: [Mood: NSMenuItem] = [:]

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

        let personalityItem = NSMenuItem(title: "Personality", action: nil, keyEquivalent: "")
        let personalitySubmenu = NSMenu(title: "Personality")
        for mood in Mood.allCases {
            let moodItem = NSMenuItem(
                title: mood.displayName,
                action: #selector(selectMood(_:)),
                keyEquivalent: ""
            )
            moodItem.target = self
            moodItem.representedObject = mood.rawValue
            moodItems[mood] = moodItem
            personalitySubmenu.addItem(moodItem)
        }
        personalityItem.submenu = personalitySubmenu
        menu.addItem(personalityItem)
        refreshMoodCheckmarks()

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit Goose", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func selectMood(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mood = Mood(rawValue: raw) else { return }
        MoodStore.set(mood)
        refreshMoodCheckmarks()
    }

    private func refreshMoodCheckmarks() {
        let active = MoodStore.current
        for (mood, item) in moodItems {
            item.state = (mood == active) ? .on : .off
        }
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
