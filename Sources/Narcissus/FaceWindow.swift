import AppKit

final class FaceWindow: NSObject {
    private enum DockMode: String {
        case topEdge
        case belowNotch
    }

    private let panel: NSPanel
    private let faceView: FaceView
    private let size: CGFloat = 140

    private static let positionKey = "narcissus.windowOriginX"
    private static let dockModeKey = "narcissus.dockMode"

    // Drag-follow state (the "sticky" lag while actively dragging).
    private var dragTicker: Timer?
    private var targetX: CGFloat = 0
    private var currentX: CGFloat = 0
    private var currentY: CGFloat = 0
    private var dockMode: DockMode = .topEdge

    // Settle-spring state (the organic bounce/ooze once the drag ends).
    private var settleTicker: Timer?
    private var settleVelocityX: CGFloat = 0
    private var settleVelocityY: CGFloat = 0
    private var settleTargetX: CGFloat = 0
    private var settleTargetY: CGFloat = 0

    private let tickInterval: TimeInterval = 1.0 / 60.0
    private let dragFollowFactor: CGFloat = 0.35
    private let springStiffness: CGFloat = 300
    private let springDamping: CGFloat = 24

    init(cameraController: CameraController) {
        faceView = FaceView(frame: NSRect(x: 0, y: 0, width: size, height: size))

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
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

    // MARK: - Initial / restored positioning

    private func positionAtTop(restoringSavedX: Bool) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let savedX = restoringSavedX ? UserDefaults.standard.object(forKey: Self.positionKey) as? CGFloat : nil
        if restoringSavedX, let savedModeRaw = UserDefaults.standard.string(forKey: Self.dockModeKey),
           let savedMode = DockMode(rawValue: savedModeRaw) {
            dockMode = savedMode
        }
        let defaultX = screen.frame.midX - size / 2
        let resolved = resolveDock(for: savedX ?? defaultX, on: screen, previousMode: dockMode)
        dockMode = resolved.mode
        currentX = resolved.x
        currentY = resolved.y
        targetX = resolved.x
        panel.setFrameOrigin(NSPoint(x: resolved.x, y: resolved.y))
    }

    // MARK: - Dock resolution

    /// Decides whether the window should hug the plain top edge (sliding around the
    /// notch) or tuck directly beneath the notch, based on how close the proposed
    /// x is to the notch's horizontal span. Applies hysteresis so it doesn't
    /// flicker between modes right at the boundary.
    private func resolveDock(for x: CGFloat, on screen: NSScreen, previousMode: DockMode) -> (mode: DockMode, x: CGFloat, y: CGFloat) {
        let screenFrame = screen.frame
        let clampedTopEdgeX = clampedTopEdgeX(x, on: screen)
        let topEdgeResult: (DockMode, CGFloat, CGFloat) = (.topEdge, clampedTopEdgeX, screenFrame.maxY - size)

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

        let proposedCenterX = x + size / 2
        guard abs(proposedCenterX - notchCenterX) <= halfWidth else {
            return topEdgeResult
        }

        let notchBottomY = left.minY
        var belowNotchX = notchCenterX - size / 2
        belowNotchX = min(max(belowNotchX, screenFrame.minX), screenFrame.maxX - size)
        return (.belowNotch, belowNotchX, notchBottomY - size)
    }

    /// Clamp an x origin so the window sits at the very top of the screen while
    /// sliding left/right around any notch/camera-housing area.
    private func clampedTopEdgeX(_ x: CGFloat, on screen: NSScreen) -> CGFloat {
        let screenFrame = screen.frame
        var proposed = min(max(x, screenFrame.minX), screenFrame.maxX - size)

        if #available(macOS 12.0, *) {
            let windowRect = NSRect(x: proposed, y: screenFrame.maxY - size, width: size, height: size)
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let notchGap = NSRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX, height: left.height)
                if windowRect.intersects(notchGap) {
                    let distanceToLeft = abs(windowRect.minX - notchGap.minX)
                    let distanceToRight = abs(notchGap.maxX - windowRect.maxX)
                    proposed = distanceToLeft <= distanceToRight ? (notchGap.minX - size) : notchGap.maxX
                    proposed = min(max(proposed, screenFrame.minX), screenFrame.maxX - size)
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

        dragTicker?.invalidate()
        dragTicker = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.stepDrag()
        }
        if let dragTicker {
            RunLoop.main.add(dragTicker, forMode: .common)
        }
    }

    private func stepDrag() {
        guard let screen = screenUnderMouse() ?? panel.screen ?? NSScreen.main else { return }
        let screenFrame = screen.frame
        currentX += (targetX - currentX) * dragFollowFactor
        // Follow the mouse freely during the drag itself — only clamp to the screen
        // bounds. We deliberately don't fight the cursor to avoid the notch here;
        // staying flush against the top (below) means the window just visually
        // disappears "behind" the notch cutout as it passes underneath. Which dock
        // (top-edge vs below-notch) it resolves to is only decided once, on release.
        currentX = min(max(currentX, screenFrame.minX), screenFrame.maxX - size)
        currentY = screenFrame.maxY - size
        panel.setFrameOrigin(NSPoint(x: currentX, y: currentY))
    }

    private func endDrag() {
        dragTicker?.invalidate()
        dragTicker = nil

        guard let screen = screenUnderMouse() ?? panel.screen ?? NSScreen.main else { return }
        let resolved = resolveDock(for: currentX, on: screen, previousMode: dockMode)
        dockMode = resolved.mode
        beginSettle(toX: resolved.x, toY: resolved.y)

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

    private func beginSettle(toX targetX: CGFloat, toY targetY: CGFloat) {
        settleTargetX = targetX
        settleTargetY = targetY
        settleVelocityX = 0
        settleVelocityY = 0

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

        panel.setFrameOrigin(NSPoint(x: currentX, y: currentY))

        let settled = abs(displacementX) < 0.5 && abs(settleVelocityX) < 0.5
            && abs(displacementY) < 0.5 && abs(settleVelocityY) < 0.5
        if settled {
            currentX = settleTargetX
            currentY = settleTargetY
            panel.setFrameOrigin(NSPoint(x: currentX, y: currentY))
            timer.invalidate()
            settleTicker = nil
        }
    }
}
