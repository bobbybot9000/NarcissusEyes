import AppKit
import AVFoundation
import CoreImage

final class FaceView: NSView, CameraFrameReceiver {
    private let faceTracker = FaceTracker()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let displayLayer = CALayer()
    private let shapeMask = CAShapeLayer()
    private let bottomCornerRadius: CGFloat = 28
    private let dockView = MirrorDockView(frame: NSRect(x: 0, y: 0, width: 84, height: 22))
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    /// Called when a drag begins (mouse down), before any movement.
    var onDragStart: (() -> Void)?
    /// Called when the mouse enters (true) or exits (false) the Mirror.
    var onHoverChange: ((Bool) -> Void)?
    /// Called on every drag update with the proposed new x origin (in screen coordinates);
    /// the owner is responsible for clamping it to the top edge / around the notch.
    var onDragMove: ((CGFloat) -> Void)?
    /// Called once the drag ends (mouse up), so the owner can persist the final position.
    var onDragEnd: (() -> Void)?
    /// Called when the Face/Eyes crop toggle changes.
    var onCropModeChange: ((CropMode) -> Void)?
    /// Called when the Transparent toggle changes.
    var onTransparencyChange: ((Bool) -> Void)?

    private var dragOriginWindowX: CGFloat = 0
    private var dragOriginMouseScreenX: CGFloat = 0
    private var currentCropMode: CropMode = .face
    private var isTransparent = false
    private var trackingArea: NSTrackingArea?
    private var blurSafetyTimer: Timer?

    // MARK: - Transition blur state
    //
    // Read/written from both the main queue (trigger/settle) and the camera's
    // background output queue (per-frame radius sampling in cameraController(_:didOutput:)),
    // so every access goes through `blurLock`.
    private let blurLock = NSLock()
    private var blurActive = false
    private var blurStartTime: CFAbsoluteTime = 0
    private var blurExitTime: CFAbsoluteTime?
    private var blurExitStartRadius: CGFloat = 0

    private let blurEnterDuration: CFAbsoluteTime = 0.15
    private let blurExitDuration: CFAbsoluteTime = 0.35
    private let blurBaseRadius: CGFloat = 14
    private let blurOscillationAmplitude: CGFloat = 5
    private let blurOscillationPeriod: CFAbsoluteTime = 1.3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.mask = shapeMask

        displayLayer.frame = bounds
        displayLayer.contentsGravity = .resizeAspectFill
        layer?.addSublayer(displayLayer)

        addSubview(dockView)
        dockView.onFaceTapped = { [weak self] in self?.setCropMode(.face) }
        dockView.onEyesTapped = { [weak self] in self?.setCropMode(.eyes) }
        dockView.onTransparentTapped = { [weak self] in self?.toggleTransparency() }

        statusLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        statusLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.isHidden = true
        addSubview(statusLabel)

        updateShapeMask()
        layoutDockView()
    }

    /// Explains why the feed is dark instead of leaving a silent black box —
    /// camera permission denied, or frames stopped arriving mid-run.
    func setFeedState(_ state: CameraFeedState) {
        switch state {
        case .running:
            statusLabel.isHidden = true
        case .accessDenied:
            statusLabel.stringValue = "Camera access needed\nSystem Settings → Privacy & Security → Camera"
            statusLabel.isHidden = false
        case .stalled:
            statusLabel.stringValue = "Camera unavailable"
            statusLabel.isHidden = false
        }
        needsLayout = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
        updateShapeMask()
        layoutDockView()

        let labelSize = statusLabel.sizeThatFits(NSSize(width: bounds.width - 16, height: bounds.height))
        statusLabel.frame = NSRect(
            x: 8,
            y: (bounds.height - labelSize.height) / 2,
            width: bounds.width - 16,
            height: labelSize.height
        )
    }

    // MARK: - Transition blur
    //
    // Masks the visible zoom/settle jank while a crop mode or camera switch takes
    // effect by blurring the live feed itself (rather than covering it with an
    // opaque overlay) — the blur radius ramps in, gently oscillates so there's
    // still visible "life" (real blurred motion) while tracking converges, then
    // ramps back to zero the instant `FaceTracker.awaitSettle` fires. A safety
    // timeout guards against Vision never quite converging (e.g. face out of frame).

    func beginTransitionBlur() {
        blurLock.lock()
        blurActive = true
        blurStartTime = CFAbsoluteTimeGetCurrent()
        blurExitTime = nil
        blurLock.unlock()
        blurSafetyTimer?.invalidate()

        faceTracker.awaitSettle { [weak self] in
            self?.beginBlurExit()
        }
        blurSafetyTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.beginBlurExit()
        }
    }

    private func beginBlurExit() {
        blurLock.lock()
        guard blurActive, blurExitTime == nil else {
            blurLock.unlock()
            return
        }
        blurExitStartRadius = lockedBlurRadius(at: CFAbsoluteTimeGetCurrent())
        blurExitTime = CFAbsoluteTimeGetCurrent()
        blurLock.unlock()

        blurSafetyTimer?.invalidate()
        blurSafetyTimer = nil
    }

    /// The blur radius at a given time: ramping in and oscillating while active,
    /// or ramping back down to zero once exiting. Callers must hold `blurLock`.
    private func lockedBlurRadius(at time: CFAbsoluteTime) -> CGFloat {
        guard blurActive else { return 0 }
        if let exitTime = blurExitTime {
            let t = min((time - exitTime) / blurExitDuration, 1)
            return blurExitStartRadius * CGFloat(1 - t)
        }
        let envelope = min((time - blurStartTime) / blurEnterDuration, 1)
        let oscillation = blurBaseRadius + blurOscillationAmplitude * CGFloat(sin(2 * .pi * (time - blurStartTime) / blurOscillationPeriod))
        return oscillation * CGFloat(envelope)
    }

    /// Samples the current radius and retires the blur once its exit ramp has
    /// finished. Called from the camera's background output queue once per frame.
    private func sampleBlurRadius(at time: CFAbsoluteTime) -> CGFloat {
        blurLock.lock()
        defer { blurLock.unlock() }
        let radius = lockedBlurRadius(at: time)
        if let exitTime = blurExitTime, time - exitTime >= blurExitDuration {
            blurActive = false
            blurExitTime = nil
        }
        return radius
    }

    private func layoutDockView() {
        let size = dockView.frame.size
        dockView.frame = NSRect(
            x: (bounds.width - size.width) / 2,
            y: 6,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Hover reveal

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        dockView.animator().alphaValue = 1
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        dockView.animator().alphaValue = 0
        onHoverChange?(false)
    }

    // MARK: - Mirror controls

    private func setCropMode(_ mode: CropMode) {
        guard mode != currentCropMode else { return }
        currentCropMode = mode
        faceTracker.mode = mode
        onCropModeChange?(mode)
    }

    private func toggleTransparency() {
        isTransparent.toggle()
        onTransparencyChange?(isTransparent)
    }

    /// Square top corners, rounded bottom corners — reads as flush-mounted against
    /// the top edge of the screen (or the underside of the notch) rather than floating.
    private func updateShapeMask() {
        let rect = bounds
        let radius = min(bottomCornerRadius, rect.width / 2, rect.height / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius, startAngle: 0, endAngle: -.pi / 2, clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius, startAngle: -.pi / 2, endAngle: .pi, clockwise: true
        )
        path.closeSubpath()
        shapeMask.frame = rect
        shapeMask.path = path
    }

    // MARK: - Manual window dragging
    //
    // isMovableByWindowBackground on a borderless NSPanel hands the drag off to a
    // WindowServer-level loop that never surfaces a normal mouseUp/windowDidMove to
    // the app, so we can't reliably detect "drag ended" to snap the window. Instead
    // we drive the window's frame ourselves and snap directly from our own mouseUp.

    override func mouseDown(with event: NSEvent) {
        dragOriginWindowX = window?.frame.origin.x ?? 0
        dragOriginMouseScreenX = NSEvent.mouseLocation.x
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        let deltaX = NSEvent.mouseLocation.x - dragOriginMouseScreenX
        onDragMove?(dragOriginWindowX + deltaX)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
    }

    func cameraController(_ controller: CameraController, didOutput sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        faceTracker.process(pixelBuffer: pixelBuffer)
        let cropRect = faceTracker.currentCropRect

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        let pixelCrop = CGRect(
            x: cropRect.origin.x * extent.width,
            y: cropRect.origin.y * extent.height,
            width: cropRect.width * extent.width,
            height: cropRect.height * extent.height
        ).intersection(extent)
        guard !pixelCrop.isEmpty else { return }

        let radius = sampleBlurRadius(at: CFAbsoluteTimeGetCurrent())

        let outputImage: CIImage
        if radius > 0.5 {
            // Blur needs source pixels beyond the crop edge to avoid falloff at the
            // border, so crop a padded region first, blur that, then render just
            // the original crop rect out of it.
            let padding = radius * 3
            let paddedCrop = pixelCrop.insetBy(dx: -padding, dy: -padding).intersection(extent)
            outputImage = ciImage.cropped(to: paddedCrop).applyingGaussianBlur(sigma: radius)
        } else {
            outputImage = ciImage
        }

        guard let cgImage = ciContext.createCGImage(outputImage, from: pixelCrop) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.displayLayer.contents = cgImage
        }
    }
}
