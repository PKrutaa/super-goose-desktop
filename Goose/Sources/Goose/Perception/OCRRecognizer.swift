import CoreGraphics
import Foundation
import Vision

/// Lightweight wrapper around Vision's `VNRecognizeTextRequest`. Tuned for
/// throughput rather than perfect transcription: fast recognition level, no
/// language correction, and aggressive confidence/length filtering to drop
/// noise like single-character glyphs and low-confidence guesses. Safe to use
/// off the main actor — the actual Vision work runs on a detached task.
final class OCRRecognizer: Sendable {
    private static let minConfidence: Float = 0.5
    private static let minTextLength = 3

    /// Runs OCR on `image` and returns the recognized text fragments. The work
    /// runs on a detached task so callers on `@MainActor` do not block while
    /// Vision crunches the image.
    func recognize(in image: CGImage) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            try Self.recognizeSync(in: image)
        }.value
    }

    private static func recognizeSync(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            guard candidate.confidence >= minConfidence else { return nil }
            let text = candidate.string
            guard text.count >= minTextLength else { return nil }
            return text
        }
    }
}
