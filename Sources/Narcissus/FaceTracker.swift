import Vision
import CoreImage
import CoreGraphics

enum CropMode: Equatable {
    case face
    case eyes
}

/// Detects a face in each sample buffer (throttled) and produces a smoothed
/// normalized crop rect (Vision coordinate space: origin bottom-left, 0...1),
/// shaped according to the current `mode`.
final class FaceTracker {
    var mode: CropMode = .face

    private var smoothedRect: CGRect?
    private let smoothingFactor: CGFloat = 0.25
    private var lastDetectionTime: CFAbsoluteTime = 0
    private let detectionInterval: CFAbsoluteTime = 1.0 / 10.0 // throttle Vision to 10fps
    private var isDetecting = false

    // MARK: - Settle detection
    //
    // Exponential smoothing never mathematically reaches its target, only
    // approaches it — so "settled" is defined as several consecutive detections
    // landing within a tiny delta of the previous smoothed rect.
    private var settleCompletion: (() -> Void)?
    private var settleConsecutiveCount = 0
    private let settleThreshold: CGFloat = 0.004
    private let settleRequiredConsecutive = 3

    private let sequenceHandler = VNSequenceRequestHandler()

    private let facePadding: CGFloat = 0.22
    private let eyeBandHorizontalPadding: CGFloat = 0.15
    private let eyeBandVerticalPadding: CGFloat = 0.15
    // Fallback (no landmarks available) proportional band, same as the original heuristic.
    private let eyeFallbackTopFraction: CGFloat = 0.25
    private let eyeFallbackBottomFraction: CGFloat = 0.55

    /// Returns the current best-known crop rect (normalized, Vision coords).
    /// Falls back to a centered square if no face has ever been detected.
    var currentCropRect: CGRect {
        smoothedRect ?? FaceTracker.centeredSquare(padding: 0.15)
    }

    /// Arms a one-shot watcher: `completion` fires (on the main queue) once the
    /// smoothed crop rect has converged — i.e. stopped visibly moving — after a
    /// target jump (mode switch, camera switch, first detection, etc.).
    func awaitSettle(completion: @escaping () -> Void) {
        settleConsecutiveCount = 0
        settleCompletion = completion
    }

    func process(pixelBuffer: CVPixelBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard !isDetecting, now - lastDetectionTime >= detectionInterval else { return }
        isDetecting = true
        lastDetectionTime = now

        let request = VNDetectFaceLandmarksRequest { [weak self] request, _ in
            defer { self?.isDetecting = false }
            guard let self else { return }
            guard let results = request.results as? [VNFaceObservation], let face = results.first else {
                return
            }
            let target: CGRect
            switch self.mode {
            case .face:
                target = FaceTracker.squareify(face.boundingBox, padding: self.facePadding)
            case .eyes:
                target = self.eyebrowToEyeBand(for: face) ?? self.eyeBandFallback(from: face.boundingBox)
            }
            self.updateSmoothedRect(with: target)
        }
        request.revision = VNDetectFaceLandmarksRequestRevision3

        try? sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
    }

    /// Smooths toward the new target rect on all four dimensions independently, so a
    /// mode switch (square face crop <-> thin eye band) eases into its new shape
    /// rather than snapping.
    private func updateSmoothedRect(with newRect: CGRect) {
        guard let previous = smoothedRect else {
            smoothedRect = newRect
            checkSettled(delta: 0)
            return
        }
        let x = previous.origin.x + (newRect.origin.x - previous.origin.x) * smoothingFactor
        let y = previous.origin.y + (newRect.origin.y - previous.origin.y) * smoothingFactor
        let width = previous.size.width + (newRect.size.width - previous.size.width) * smoothingFactor
        let height = previous.size.height + (newRect.size.height - previous.size.height) * smoothingFactor
        let updated = CGRect(x: x, y: y, width: width, height: height)

        let delta = max(
            abs(updated.origin.x - previous.origin.x),
            abs(updated.origin.y - previous.origin.y),
            abs(updated.width - previous.width),
            abs(updated.height - previous.height)
        )
        smoothedRect = updated
        checkSettled(delta: delta)
    }

    private func checkSettled(delta: CGFloat) {
        guard settleCompletion != nil else { return }
        if delta < settleThreshold {
            settleConsecutiveCount += 1
        } else {
            settleConsecutiveCount = 0
        }
        guard settleConsecutiveCount >= settleRequiredConsecutive else { return }
        let completion = settleCompletion
        settleCompletion = nil
        DispatchQueue.main.async {
            completion?()
        }
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

    /// Real eye-landmark crop: spans both eyebrows (top) down through the eyes with
    /// a small margin toward the nose bridge (bottom), across both eyes horizontally.
    /// Returns nil if Vision couldn't compute landmarks (extreme angle, etc.).
    private func eyebrowToEyeBand(for face: VNFaceObservation) -> CGRect? {
        guard let landmarks = face.landmarks,
              let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye,
              let leftBrow = landmarks.leftEyebrow, let rightBrow = landmarks.rightEyebrow else {
            return nil
        }

        let box = face.boundingBox
        func imagePoints(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
            region.normalizedPoints.map { CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height) }
        }

        let browPoints = imagePoints(leftBrow) + imagePoints(rightBrow)
        let eyePoints = imagePoints(leftEye) + imagePoints(rightEye)
        let allPoints = browPoints + eyePoints
        guard !allPoints.isEmpty,
              let minX = allPoints.map(\.x).min(), let maxX = allPoints.map(\.x).max(),
              let browTopY = browPoints.map(\.y).max(), let eyeBottomY = eyePoints.map(\.y).min() else {
            return nil
        }

        // Extend a bit below the eyes toward the nose bridge for breathing room.
        let noseMargin = max(browTopY - eyeBottomY, 0) * 0.5
        let top = browTopY
        let bottom = eyeBottomY - noseMargin

        let width = maxX - minX
        let height = max(top - bottom, 0.001)
        let horizontalPadding = width * eyeBandHorizontalPadding
        let verticalPadding = height * eyeBandVerticalPadding

        var rect = CGRect(
            x: minX - horizontalPadding,
            y: bottom - verticalPadding,
            width: width + horizontalPadding * 2,
            height: height + verticalPadding * 2
        )
        rect.origin.x = min(max(rect.origin.x, 0), 1 - rect.width)
        rect.origin.y = min(max(rect.origin.y, 0), 1 - rect.height)
        if rect.width > 1 {
            rect = CGRect(x: 0, y: rect.origin.y, width: 1, height: rect.height)
        }
        if rect.height > 1 {
            rect = CGRect(x: rect.origin.x, y: 0, width: rect.width, height: 1)
        }
        return rect
    }

    /// Proportional-band fallback used when Vision can't compute landmarks for a
    /// detected face, so Eyes mode never shows an empty/garbage crop.
    private func eyeBandFallback(from box: CGRect) -> CGRect {
        let top = box.maxY - box.height * eyeFallbackTopFraction
        let bottom = box.maxY - box.height * eyeFallbackBottomFraction
        let height = top - bottom

        let widthPadding = box.width * eyeBandHorizontalPadding
        var rect = CGRect(
            x: box.minX - widthPadding,
            y: bottom,
            width: box.width + widthPadding * 2,
            height: height
        )

        rect.origin.x = min(max(rect.origin.x, 0), 1 - rect.width)
        rect.origin.y = min(max(rect.origin.y, 0), 1 - rect.height)
        if rect.width > 1 {
            rect = CGRect(x: 0, y: rect.origin.y, width: 1, height: rect.height)
        }
        return rect
    }

    private static func centeredSquare(padding: CGFloat) -> CGRect {
        let side = 1 - padding * 2
        return CGRect(x: padding, y: padding, width: side, height: side)
    }
}
