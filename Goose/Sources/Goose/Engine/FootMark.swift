import CoreGraphics
import Foundation

/// A single saddle-brown footprint left in mud. Times of 0 indicate an
/// unused ring-buffer slot.
struct FootMark {
    static let lifetime: CGFloat = 8.5
    static let shrinkTime: CGFloat = 1.0
    static let initialRadius: CGFloat = 3.0

    var position: CGPoint = .zero2
    var time: CGFloat = 0
}
