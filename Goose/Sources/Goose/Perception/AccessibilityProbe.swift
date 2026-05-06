import AppKit
import ApplicationServices
import Foundation

/// Probes the system for the foreground app (via `NSWorkspace`) and that app's
/// focused window title (via the C-based Accessibility API). The window title
/// path requires the user to grant Accessibility permission in System Settings.
/// If permission is missing, AX calls fail silently and we return `nil` for the
/// window title — `frontmostAppName` still works because `NSWorkspace` does not
/// require AX.
@MainActor
final class AccessibilityProbe {
    /// Whether this process currently has Accessibility permission. Does not
    /// prompt the user.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    /// Triggers the system Accessibility prompt if permission is not yet
    /// granted. Returns the post-prompt trust state.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Returns the foreground app name, its focused window title, and pid.
    /// Any field may be `nil` when the data is unavailable (no frontmost app,
    /// missing AX permission, app does not expose a focused window, etc.).
    func currentContext() -> (appName: String?, windowTitle: String?, processIdentifier: pid_t?) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil, nil)
        }
        let pid = app.processIdentifier
        let title = focusedWindowTitle(for: pid)
        return (app.localizedName, title, pid)
    }

    private func focusedWindowTitle(for pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        var windowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard windowResult == .success, let windowValue = windowRef else { return nil }
        let windowElement = windowValue as! AXUIElement

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
        guard titleResult == .success, let title = titleRef as? String, !title.isEmpty else { return nil }
        return title
    }
}
