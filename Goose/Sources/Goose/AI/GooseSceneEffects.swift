import CoreGraphics
import Foundation

/// Side-effect surface that action tasks call into. Implemented by
/// `GooseScene` so tasks remain decoupled from SpriteKit / AppKit specifics.
@MainActor
protocol GooseSceneEffects: AnyObject {
    // Native window dragging — used by `DragWindowTask` for both notes (real
    // `NSTextView` content) and photos (real `NSImageView` content).
    func attachDraggedWindow(_ window: FloatingWindow, at point: CGPoint, direction: CGFloat)
    func updateDraggedWindowPosition(_ point: CGPoint, direction: CGFloat)
    func detachDraggedWindow()

    /// Toggle the chilling-headphones overlay on the goose.
    func setHeadphones(visible: Bool)

    /// Toggle the floating music-note particle emitter around the goose's head.
    func setMusicNotes(active: Bool)
}
