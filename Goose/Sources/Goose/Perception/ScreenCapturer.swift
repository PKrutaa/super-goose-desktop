import CoreGraphics
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

/// Captures the main display via ScreenCaptureKit. Requires the user to grant
/// the "Screen Recording" privacy permission. macOS prompts on the first
/// `SCShareableContent` / `SCScreenshotManager` call; if the user declines, the
/// permission stays denied and `tccutil reset ScreenCapture` is needed to
/// re-prompt. Failures are surfaced as `nil` plus a stderr warning so the rest
/// of the perception pipeline can continue degraded rather than crash.
@MainActor
final class ScreenCapturer {
    /// Target width for captured images. We let ScreenCaptureKit downscale via
    /// the GPU instead of doing a CPU-side `CGContext` redraw downstream.
    private static let captureWidth = 1024

    private var cachedDisplay: SCDisplay?

    /// Returns a snapshot of the main display already downscaled to ~1024px
    /// wide, or `nil` if capture failed (typically because Screen Recording
    /// permission is missing).
    func captureMainDisplay() async throws -> CGImage? {
        guard let display = try await resolveDisplay() else { return nil }

        let scale = CGFloat(Self.captureWidth) / CGFloat(display.width)
        let targetHeight = max(1, Int(CGFloat(display.height) * scale))

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Self.captureWidth
        config.height = targetHeight
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            PerceptionLog.warn("ScreenCapturer: SCScreenshotManager.captureImage failed (\(error.localizedDescription))")
            cachedDisplay = nil
            return nil
        }
    }

    private func resolveDisplay() async throws -> SCDisplay? {
        if let cached = cachedDisplay {
            return cached
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            PerceptionLog.warn("ScreenCapturer: SCShareableContent.current failed (\(error.localizedDescription)) — Screen Recording permission may be missing. Run `tccutil reset ScreenCapture` and grant access on the next prompt.")
            return nil
        }

        guard let display = content.displays.first else {
            PerceptionLog.warn("ScreenCapturer: no displays returned by SCShareableContent")
            return nil
        }

        cachedDisplay = display
        return display
    }
}
