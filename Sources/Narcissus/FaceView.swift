import AppKit
import AVFoundation
import CoreImage

final class FaceView: NSView, CameraFrameReceiver {
    private let faceTracker = FaceTracker()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let displayLayer = CALayer()
    private let shapeMask = CAShapeLayer()
    private let bottomCornerRadius: CGFloat = 28

    /// Called when a drag begins (mouse down), before any movement.
    var onDragStart: (() -> Void)?
    /// Called on every drag update with the proposed new x origin (in screen coordinates);
    /// the owner is responsible for clamping it to the top edge / around the notch.
    var onDragMove: ((CGFloat) -> Void)?
    /// Called once the drag ends (mouse up), so the owner can persist the final position.
    var onDragEnd: (() -> Void)?

    private var dragOriginWindowX: CGFloat = 0
    private var dragOriginMouseScreenX: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.mask = shapeMask

        displayLayer.frame = bounds
        displayLayer.contentsGravity = .resizeAspectFill
        layer?.addSublayer(displayLayer)

        updateShapeMask()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
        updateShapeMask()
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

        guard !pixelCrop.isEmpty, let cgImage = ciContext.createCGImage(ciImage, from: pixelCrop) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.displayLayer.contents = cgImage
        }
    }
}
