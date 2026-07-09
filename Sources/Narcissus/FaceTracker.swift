import Vision
import CoreImage
import CoreGraphics

/// Detects a face in each sample buffer (throttled) and produces a smoothed,
/// square normalized crop rect (Vision coordinate space: origin bottom-left, 0...1).
final class FaceTracker {
    private var smoothedRect: CGRect?
    private let smoothingFactor: CGFloat = 0.25
    private var lastDetectionTime: CFAbsoluteTime = 0
    private let detectionInterval: CFAbsoluteTime = 1.0 / 10.0 // throttle Vision to 10fps
    private var isDetecting = false

    private let sequenceHandler = VNSequenceRequestHandler()

    /// Returns the current best-known square crop rect (normalized, Vision coords).
    /// Falls back to a centered square if no face has ever been detected.
    var currentCropRect: CGRect {
        smoothedRect ?? FaceTracker.centeredSquare(padding: 0.15)
    }

    func process(pixelBuffer: CVPixelBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard !isDetecting, now - lastDetectionTime >= detectionInterval else { return }
        isDetecting = true
        lastDetectionTime = now

        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            defer { self?.isDetecting = false }
            guard let self else { return }
            guard let results = request.results as? [VNFaceObservation], let face = results.first else {
                return
            }
            let square = FaceTracker.squareify(face.boundingBox, padding: 0.6)
            self.updateSmoothedRect(with: square)
        }
        request.revision = VNDetectFaceRectanglesRequestRevision3

        try? sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
    }

    private func updateSmoothedRect(with newRect: CGRect) {
        guard let previous = smoothedRect else {
            smoothedRect = newRect
            return
        }
        let x = previous.origin.x + (newRect.origin.x - previous.origin.x) * smoothingFactor
        let y = previous.origin.y + (newRect.origin.y - previous.origin.y) * smoothingFactor
        let size = previous.size.width + (newRect.size.width - previous.size.width) * smoothingFactor
        smoothedRect = CGRect(x: x, y: y, width: size, height: size)
    }

    /// Expands a face bounding box into a square with padding, clamped to 0...1.
    private static func squareify(_ box: CGRect, padding: CGFloat) -> CGRect {
        let side = max(box.width, box.height) * (1 + padding)
        let centerX = box.midX
        let centerY = box.midY
        var rect = CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)

        rect.origin.x = min(max(rect.origin.x, 0), 1 - rect.width)
        rect.origin.y = min(max(rect.origin.y, 0), 1 - rect.height)
        if rect.width > 1 {
            rect = CGRect(x: 0, y: rect.origin.y, width: 1, height: 1)
        }
        return rect
    }

    private static func centeredSquare(padding: CGFloat) -> CGRect {
        let side = 1 - padding * 2
        return CGRect(x: padding, y: padding, width: side, height: side)
    }
}
