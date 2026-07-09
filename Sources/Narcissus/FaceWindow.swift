import AppKit

final class FaceWindow: NSObject {
    private enum DockMode: String {
        case topEdge
        case belowNotch
    }

    private static let faceSize = NSSize(width: 140, height: 140)
    private static let eyesSize = NSSize(width: 200, height: 40)
    private static let normalAlpha: CGFloat = 1.0
    private static let transparentAlpha: CGFloat = 0.35

    private let panel: NSPanel
    private let faceView: FaceView

    private static let positionKey = "narcissus.windowOriginX"
    private static let dockModeKey = "narcissus.dockMode"

    private var currentSize = FaceWindow.faceSize
    private var preferredScreen: NSScreen?
    private var dragStartScreen: NSScreen?

    /// Called when a drag ends having landed on a different screen than it
    /// started on, so the owner can force the camera to match (built-in cam for
    /// the built-in display, external otherwise).
    var onUserRelocatedToScreen: ((NSScreen) -> Void)?

    // Drag-follow state (the "sticky" lag while actively dragging).
    private var dragTicker: Timer?
    private var targetX: CGFloat = 0
    private var currentX: CGFloat = 0
    private var currentY: CGFloat = 0
    private var currentWidth: CGFloat = FaceWindow.faceSize.width
    private var dockMode: DockMode = .topEdge

    // Settle-spring state (the organic bounce/ooze once the drag ends).
    private var settleTicker: Timer?
    private var settleVelocityX: CGFloat = 0
    private var settleVelocityY: CGFloat = 0
    private var settleVelocityWidth: CGFloat = 0
    private var settleTargetX: CGFloat = 0
    private var settleTargetY: CGFloat = 0
    private var settleTargetWidth: CGFloat = 0

    private let tickInterval: TimeInterval = 1.0 / 60.0
    private let dragFollowFactor: CGFloat = 0.35
    private let springStiffness: CGFloat = 300
    private let springDamping: CGFloat = 24
    /// How far the Mirror's top sits *behind* the notch's bottom edge while docked
    /// below it. The notch is a true hardware cutout with no visible pixels, so
    /// this overlap is invisible — it hides any seam from the notch's rounded
    /// corners not matching the Mirror's square top corners, without needing to
    /// know the notch's exact corner radius.
    private let notchOverlap: CGFloat = 5

    init(cameraController: CameraController) {
        faceView = FaceView(frame: NSRect(origin: .zero, size: FaceWindow.faceSize))

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: FaceWindow.faceSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.sharingType = .none // excludes this window from screen capture / screen share
        panel.contentView = faceView

        super.init()

        cameraController.frameReceiver = faceView
        faceView.onDragStart = { [weak self] in
            self?.beginDrag()
        }
        faceView.onDragMove = { [weak self] proposedX in
            self?.targetX = proposedX
        }
        faceView.onDragEnd = { [weak self] in
            self?.endDrag()
        }
        faceView.onCropModeChange = { [weak self] mode in
            self?.applyCropMode(mode)
        }
        faceView.onTransparencyChange = { [weak self] transparent in
            self?.applyTransparency(transparent)
        }

        positionAtTop(restoringSavedX: true)
    }

    func showWindow() {
        panel.orderFrontRegardless()
    }

    func toggleVisibility() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.positionKey)
        UserDefaults.standard.removeObject(forKey: Self.dockModeKey)
        dockMode = .topEdge
        positionAtTop(restoringSavedX: false)
    }

    /// Called by DeviceCoordinator when the preferred screen (built-in vs external
    /// display) changes. Re-docks the Mirror onto the new screen. This must force
    /// the relocation rather than going through `resolveScreen()` — that helper
    /// intentionally favors the screen the panel is *already* on (so in-place
    /// operations like a crop-mode toggle don't get yanked onto a different
    /// display), but a device hot-swap is exactly the case where we *do* want to
    /// move: e.g. replugging a dock should bring the Mirror back to the external
    /// display, not leave it stranded on the laptop's notch.
    func setPreferredScreen(_ screen: NSScreen) {
        preferredScreen = screen
        dockMode = .topEdge
        positionAtTop(restoringSavedX: false, on: screen)
    }

    /// Briefly blurs the Mirror's feed to mask the visible zoom/settle jank while a
    /// crop mode or camera switch takes effect.
    func beginTransitionBlur() {
        faceView.beginTransitionBlur()
    }

    // MARK: - Crop mode / transparency

    private func applyCropMode(_ mode: CropMode) {
        faceView.beginTransitionBlur()

        let targetSize = mode == .face ? FaceWindow.faceSize : FaceWindow.eyesSize
        guard targetSize != currentSize else { return }
        // Preserve the horizontal *center*, not the left edge — face (140pt) and
        // eyes (200pt) are different widths, so keeping the same left edge would
        // shift the visual center sideways, drifting away from wherever the user
        // deliberately anchored the Mirror under their webcam.
        let centerX = currentX + currentSize.width / 2
        currentSize = targetSize
        let proposedX = centerX - currentSize.width / 2

        guard let screen = resolveScreen() else { return }
        let resolved = resolveDock(for: proposedX, on: screen, previousMode: dockMode)
        dockMode = resolved.mode

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(NSRect(x: resolved.x, y: resolved.y, width: resolved.width, height: currentSize.height), display: true)
        }
        currentX = resolved.x
        currentY = resolved.y
        currentWidth = resolved.width
        targetX = resolved.x
    }

    private func applyTransparency(_ transparent: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = transparent ? FaceWindow.transparentAlpha : FaceWindow.normalAlpha
        }
    }

    // MARK: - Initial / restored positioning

    private func positionAtTop(restoringSavedX: Bool) {
        guard let screen = resolveScreen() else { return }
        positionAtTop(restoringSavedX: restoringSavedX, on: screen)
    }

    private func positionAtTop(restoringSavedX: Bool, on screen: NSScreen) {
        let savedX = restoringSavedX ? UserDefaults.standard.object(forKey: Self.positionKey) as? CGFloat : nil
        if restoringSavedX, let savedModeRaw = UserDefaults.standard.string(forKey: Self.dockModeKey),
           let savedMode = DockMode(rawValue: savedModeRaw) {
            dockMode = savedMode
        }
        let defaultX = screen.frame.midX - currentSize.width / 2
        let resolved = resolveDock(for: savedX ?? defaultX, on: screen, previousMode: dockMode)
        dockMode = resolved.mode
        currentX = resolved.x
        currentY = resolved.y
        currentWidth = resolved.width
        targetX = resolved.x
        panel.setFrame(NSRect(x: resolved.x, y: resolved.y, width: resolved.width, height: currentSize.height), display: true)
    }

    /// The screen the panel is actually docked on always wins for in-place
    /// operations (repositioning, mode toggles, drag/settle) — a mode toggle must
    /// never silently re-target onto DeviceCoordinator's "preferred" external
    /// display out from under a deliberate notch dock. `preferredScreen` is only
    /// authoritative via the explicit `setPreferredScreen(_:)` re-dock call.
    private func resolveScreen() -> NSScreen? {
        panel.screen ?? preferredScreen ?? NSScreen.main
    }

    // MARK: - Dock resolution

    /// Decides whether the window should hug the plain top edge (sliding around the
    /// notch) or tuck directly beneath the notch, based on how close the proposed
    /// x is to the notch's horizontal span. Applies hysteresis so it doesn't
    /// flicker between modes right at the boundary. When docking below the notch,
    /// the width matches the notch's actual physical width for this Mac (reported
    /// by macOS via auxiliaryTopLeftArea/auxiliaryTopRightArea) instead of the
    /// Mirror's normal size, so it reads as a native fit regardless of hardware.
    private func resolveDock(for x: CGFloat, on screen: NSScreen, previousMode: DockMode) -> (mode: DockMode, x: CGFloat, y: CGFloat, width: CGFloat) {
        let screenFrame = screen.frame
        let clampedTopEdgeX = clampedTopEdgeX(x, on: screen)
        let topEdgeResult: (DockMode, CGFloat, CGFloat, CGFloat) = (.topEdge, clampedTopEdgeX, screenFrame.maxY - currentSize.height, currentSize.width)

        guard #available(macOS 12.0, *),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return topEdgeResult
        }

        let notchCenterX = (left.maxX + right.minX) / 2
        let notchHalfWidth = (right.minX - left.maxX) / 2
        let captureMargin: CGFloat = 40
        let hysteresisBonus: CGFloat = 24
        let halfWidth = notchHalfWidth + captureMargin + (previousMode == .belowNotch ? hysteresisBonus : 0)

        let proposedCenterX = x + currentSize.width / 2
        guard abs(proposedCenterX - notchCenterX) <= halfWidth else {
            return topEdgeResult
        }

        guard let forced = forcedBelowNotchDock(on: screen) else {
            return topEdgeResult
        }
        return forced
    }

    /// The below-notch dock geometry regardless of horizontal proximity — used
    /// both by `resolveDock`'s normal proximity-based resolution and to force a
    /// notch dock outright when the Mirror is deliberately dragged onto this
    /// screen. Returns nil if this screen has no notch to dock under.
    private func forcedBelowNotchDock(on screen: NSScreen) -> (mode: DockMode, x: CGFloat, y: CGFloat, width: CGFloat)? {
        guard #available(macOS 12.0, *),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return nil
        }
        let screenFrame = screen.frame
        let notchWidth = right.minX - left.maxX
        let notchBottomY = left.minY
        let belowNotchX = min(max(left.maxX, screenFrame.minX), screenFrame.maxX - notchWidth)
        return (.belowNotch, belowNotchX, notchBottomY - currentSize.height + notchOverlap, notchWidth)
    }

    /// Clamp an x origin so the window sits at the very top of the screen while
    /// sliding left/right around any notch/camera-housing area.
    private func clampedTopEdgeX(_ x: CGFloat, on screen: NSScreen) -> CGFloat {
        let screenFrame = screen.frame
        var proposed = min(max(x, screenFrame.minX), screenFrame.maxX - currentSize.width)

        if #available(macOS 12.0, *) {
            let windowRect = NSRect(x: proposed, y: screenFrame.maxY - currentSize.height, width: currentSize.width, height: currentSize.height)
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let notchGap = NSRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX, height: left.height)
                if windowRect.intersects(notchGap) {
                    let distanceToLeft = abs(windowRect.minX - notchGap.minX)
                    let distanceToRight = abs(notchGap.maxX - windowRect.maxX)
                    proposed = distanceToLeft <= distanceToRight ? (notchGap.minX - currentSize.width) : notchGap.maxX
                    proposed = min(max(proposed, screenFrame.minX), screenFrame.maxX - currentSize.width)
                }
            }
        }
        return proposed
    }

    // MARK: - Dragging (sticky lag while the mouse moves)

    private func beginDrag() {
        settleTicker?.invalidate()
        settleTicker = nil
        targetX = currentX
        dragStartScreen = screenUnderMouse() ?? resolveScreen()

        dragTicker?.invalidate()
        dragTicker = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.stepDrag()
        }
        if let dragTicker {
            RunLoop.main.add(dragTicker, forMode: .common)
        }
    }

    private func stepDrag() {
        guard let screen = screenUnderMouse() ?? resolveScreen() else { return }
        let screenFrame = screen.frame
        currentX += (targetX - currentX) * dragFollowFactor
        // Follow the mouse freely during the drag itself — only clamp to the screen
        // bounds. We deliberately don't fight the cursor to avoid the notch here;
        // staying flush against the top (below) means the window just visually
        // disappears "behind" the notch cutout as it passes underneath. Which dock
        // (top-edge vs below-notch, and its matching width) is only decided once,
        // on release, and the width settles in via the spring below.
        currentX = min(max(currentX, screenFrame.minX), screenFrame.maxX - currentSize.width)
        currentY = screenFrame.maxY - currentSize.height
        currentWidth = currentSize.width
        panel.setFrame(NSRect(x: currentX, y: currentY, width: currentWidth, height: currentSize.height), display: true)
    }

    private func endDrag() {
        dragTicker?.invalidate()
        dragTicker = nil

        guard let screen = screenUnderMouse() ?? resolveScreen() else { return }

        // Landing on a different screen than the drag started on is a deliberate
        // "move me here" gesture — force the camera to match, and if it's the
        // built-in display, force the notch dock outright regardless of exactly
        // where on the screen it was dropped, so the user doesn't have to
        // fine-tune the drop position for the anchor to take.
        let landedOnNewScreen = dragStartScreen.map { $0 !== screen } ?? false
        if landedOnNewScreen {
            onUserRelocatedToScreen?(screen)
        }

        let resolved: (mode: DockMode, x: CGFloat, y: CGFloat, width: CGFloat)
        if landedOnNewScreen, screen.isBuiltIn, let forced = forcedBelowNotchDock(on: screen) {
            resolved = forced
        } else {
            resolved = resolveDock(for: currentX, on: screen, previousMode: dockMode)
        }
        dockMode = resolved.mode
        beginSettle(toX: resolved.x, toY: resolved.y, toWidth: resolved.width)

        UserDefaults.standard.set(resolved.x, forKey: Self.positionKey)
        UserDefaults.standard.set(dockMode.rawValue, forKey: Self.dockModeKey)
    }

    /// While dragging near a screen edge, panel.screen can lag; find the screen
    /// under the current mouse location so multi-monitor drags snap correctly.
    private func screenUnderMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    // MARK: - Settle (organic spring bounce / ooze once the drag ends)

    private func beginSettle(toX targetX: CGFloat, toY targetY: CGFloat, toWidth targetWidth: CGFloat) {
        settleTargetX = targetX
        settleTargetY = targetY
        settleTargetWidth = targetWidth
        settleVelocityX = 0
        settleVelocityY = 0
        settleVelocityWidth = 0

        settleTicker?.invalidate()
        settleTicker = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.stepSettle(timer: timer)
        }
        if let settleTicker {
            RunLoop.main.add(settleTicker, forMode: .common)
        }
    }

    private func stepSettle(timer: Timer) {
        let displacementX = currentX - settleTargetX
        let forceX = -springStiffness * displacementX - springDamping * settleVelocityX
        settleVelocityX += forceX * tickInterval
        currentX += settleVelocityX * tickInterval

        let displacementY = currentY - settleTargetY
        let forceY = -springStiffness * displacementY - springDamping * settleVelocityY
        settleVelocityY += forceY * tickInterval
        currentY += settleVelocityY * tickInterval

        let displacementWidth = currentWidth - settleTargetWidth
        let forceWidth = -springStiffness * displacementWidth - springDamping * settleVelocityWidth
        settleVelocityWidth += forceWidth * tickInterval
        currentWidth += settleVelocityWidth * tickInterval

        panel.setFrame(NSRect(x: currentX, y: currentY, width: currentWidth, height: currentSize.height), display: true)

        let settled = abs(displacementX) < 0.5 && abs(settleVelocityX) < 0.5
            && abs(displacementY) < 0.5 && abs(settleVelocityY) < 0.5
            && abs(displacementWidth) < 0.5 && abs(settleVelocityWidth) < 0.5
        if settled {
            currentX = settleTargetX
            currentY = settleTargetY
            currentWidth = settleTargetWidth
            panel.setFrame(NSRect(x: currentX, y: currentY, width: currentWidth, height: currentSize.height), display: true)
            timer.invalidate()
            settleTicker = nil
        }
    }
}
