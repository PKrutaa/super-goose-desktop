import AppKit

/// Goose palette using the public hex values exposed via `defaults` in the
/// official Mac port (Desktop Goose v0.22 README).
enum GooseColors {
    static let white = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1)
    static let outline = NSColor(srgbRed: 0xD3 / 255.0, green: 0xD3 / 255.0, blue: 0xD3 / 255.0, alpha: 1)
    static let orange = NSColor(srgbRed: 1.0, green: 0xA5 / 255.0, blue: 0, alpha: 1)
    static let eye = NSColor.black
    static let mud = NSColor(srgbRed: 0x8B / 255.0, green: 0x45 / 255.0, blue: 0x13 / 255.0, alpha: 1)
    static let shadowDot = NSColor(white: 0.55, alpha: 1)
}
