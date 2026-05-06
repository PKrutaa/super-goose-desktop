import AppKit
import CoreGraphics

/// Offscreen renderer that draws the goose using the same rig and stroke
/// strategy as `GooseArt`, into a Core Graphics bitmap context. Used for
/// visual verification without requiring Screen Recording permission.
enum PreviewRenderer {
    static func renderToPNG(at path: String, canvas: CGSize = CGSize(width: 200, height: 200), displayScale: CGFloat = 1.0) -> Bool {
        let pixelSize = CGSize(width: canvas.width * 2, height: canvas.height * 2)
        guard let context = makeContext(size: pixelSize) else { return false }

        context.scaleBy(x: 2, y: 2)
        context.setFillColor(NSColor(srgbRed: 0.8, green: 0.92, blue: 0.4, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: canvas))

        context.translateBy(x: canvas.width / 2, y: canvas.height / 2 - 10)
        context.scaleBy(x: displayScale, y: displayScale)

        var rig = GooseRig()
        rig.update(position: .zero2, directionDegrees: 180, neckLerp: 0)

        let perpendicular = CGPoint(x: rig.forward.y, y: -rig.forward.x)
        let leftFoot = CGPoint.zero2
        let rightFoot = perpendicular * 6

        drawShadow(context: context)
        drawFeet(context: context, leftFoot: leftFoot, rightFoot: rightFoot)
        drawGoose(context: context, rig: rig)

        guard let cgImage = context.makeImage() else { return false }
        return writePNG(cgImage, to: path)
    }

    private static func makeContext(size: CGSize) -> CGContext? {
        let width = Int(size.width)
        let height = Int(size.height)
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func drawShadow(context: CGContext) {
        let size = CGSize(width: 40, height: 30)
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2 - 4, width: size.width, height: size.height)

        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()

        context.setFillColor(GooseColors.shadowDot.cgColor)
        let xRange = stride(from: Int(rect.minX), to: Int(rect.maxX), by: 2)
        let yRange = stride(from: Int(rect.minY), to: Int(rect.maxY), by: 2)
        for y in yRange {
            for x in xRange {
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        context.restoreGState()
    }

    private static func drawGoose(context: CGContext, rig: GooseRig) {
        let fwd = rig.forward

        let bodyA = rig.bodyCenter + fwd * 11
        let bodyB = rig.bodyCenter - fwd * 11
        let underA = rig.underbodyCenter + fwd * 7
        let underB = rig.underbodyCenter - fwd * 7
        let beakEnd = rig.head2EndPoint + fwd * 3

        strokeLine(context, from: bodyA, to: bodyB, color: GooseColors.outline, width: 24)
        strokeLine(context, from: rig.neckBase, to: rig.neckHeadPoint, color: GooseColors.outline, width: 15)
        strokeLine(context, from: rig.neckHeadPoint, to: rig.head1EndPoint, color: GooseColors.outline, width: 17)
        strokeLine(context, from: rig.head1EndPoint, to: rig.head2EndPoint, color: GooseColors.outline, width: 12)
        strokeLine(context, from: underA, to: underB, color: GooseColors.outline, width: 15)
        strokeLine(context, from: bodyA, to: bodyB, color: GooseColors.white, width: 22)
        strokeLine(context, from: rig.neckBase, to: rig.neckHeadPoint, color: GooseColors.white, width: 13)
        strokeLine(context, from: rig.neckHeadPoint, to: rig.head1EndPoint, color: GooseColors.white, width: 15)
        strokeLine(context, from: rig.head1EndPoint, to: rig.head2EndPoint, color: GooseColors.white, width: 10)
        strokeLine(context, from: rig.head2EndPoint, to: beakEnd, color: GooseColors.orange, width: 9)

        drawEyes(context: context, rig: rig)
    }

    private static func drawFeet(context: CGContext, leftFoot: CGPoint, rightFoot: CGPoint) {
        context.setFillColor(GooseColors.orange.cgColor)
        for center in [leftFoot, rightFoot] {
            context.fillEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
        }
    }

    private static func drawEyes(context: CGContext, rig: GooseRig) {
        let fwd = rig.forward
        let perp = rig.perpendicular
        let stretch = CGPoint(x: 1.3, y: 0.4)
        let baseX = rig.neckHeadPoint.x + fwd.x * 5
        let baseY = rig.neckHeadPoint.y + 3 + fwd.y * 5

        let eye1 = CGPoint(
            x: baseX - perp.x * stretch.x * 5,
            y: baseY - perp.y * stretch.y * 5
        )
        let eye2 = CGPoint(
            x: baseX + perp.x * stretch.x * 5,
            y: baseY + perp.y * stretch.y * 5
        )

        context.setFillColor(GooseColors.eye.cgColor)
        for center in [eye1, eye2] {
            context.fillEllipse(in: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
        }
    }

    private static func strokeLine(_ context: CGContext, from a: CGPoint, to b: CGPoint, color: NSColor, width: CGFloat) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: a)
        context.addLine(to: b)
        context.strokePath()
    }

    private static func writePNG(_ cgImage: CGImage, to path: String) -> Bool {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
