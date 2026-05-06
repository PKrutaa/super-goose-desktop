import AppKit
import WebKit

/// A real, large browser window the goose drags onto the screen during
/// `BrowseTask`. Loads a `WKWebView` showing a real URL chosen by the brain.
///
/// Click-through: it's a spectacle, not a tool. User can't interact with it.
/// Lives at `.floating` so the goose overlay (`.screenSaver`) still draws on top.
@MainActor
final class RealBrowserWindow: NSWindow {
    static let size = CGSize(width: 1000, height: 700)

    private let webView: WKWebView

    init(url: URL) {
        let frame = NSRect(origin: .zero, size: Self.size)
        let webView = WKWebView(frame: frame)
        webView.load(URLRequest(url: url))
        self.webView = webView

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = true
        backgroundColor = NSColor.white
        hasShadow = true
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        contentView = webView
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Slides in from off-screen-right to a centered position over ~0.5s.
    func slideIn() async {
        guard let screen = NSScreen.main?.frame else { return }
        let target = NSRect(
            x: (screen.width - Self.size.width) / 2,
            y: (screen.height - Self.size.height) / 2,
            width: Self.size.width,
            height: Self.size.height
        )
        let start = NSRect(
            x: screen.width + 50,
            y: target.origin.y,
            width: Self.size.width,
            height: Self.size.height
        )
        setFrame(start, display: false)
        orderFront(nil)
        animator().alphaValue = 1
        await NSAnimationContext.runAsync(duration: 0.5) { ctx in
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(target, display: true)
        }
    }

    /// Fades + scales out, then closes the window.
    func dismiss() async {
        await NSAnimationContext.runAsync(duration: 0.4) { ctx in
            ctx.allowsImplicitAnimation = true
            self.animator().alphaValue = 0
            let f = self.frame
            let target = NSRect(
                x: f.origin.x + f.width * 0.1,
                y: f.origin.y + f.height * 0.1,
                width: f.width * 0.8,
                height: f.height * 0.8
            )
            self.animator().setFrame(target, display: true)
        }
        close()
    }
}

private extension NSAnimationContext {
    @MainActor
    static func runAsync(duration: TimeInterval, _ body: @escaping @MainActor (NSAnimationContext) -> Void) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                MainActor.assumeIsolated { body(ctx) }
            }, completionHandler: {
                cont.resume()
            })
        }
    }
}
