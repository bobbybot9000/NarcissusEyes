import AVFoundation
import AppKit
import CoreGraphics

/// Picks which camera and which screen LookNice should use, preferring an
/// external webcam + external display when present and falling back to the
/// built-in laptop camera + screen otherwise. Re-resolves live as devices are
/// connected or disconnected.
final class DeviceCoordinator {
    var onCameraChange: ((AVCaptureDevice) -> Void)?
    var onScreenChange: ((NSScreen) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var lastCameraID: String?
    private var lastScreenID: CGDirectDisplayID?
    private var pendingResolve: DispatchWorkItem?

    /// A dock unplug/replug enumerates several sub-peripherals (camera, display,
    /// etc.) as separate near-simultaneous notifications. Debouncing collapses
    /// that whole burst into a single settle instead of resolving repeatedly
    /// against a half-updated device list.
    private let debounceInterval: TimeInterval = 0.3

    init() {
        let center = NotificationCenter.default
        for name: Notification.Name in [.AVCaptureDeviceWasConnected, .AVCaptureDeviceWasDisconnected, NSApplication.didChangeScreenParametersNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleResolve()
            })
        }
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach { center.removeObserver($0) }
        pendingResolve?.cancel()
    }

    /// Resolves both camera and screen once, immediately, without waiting for a
    /// change notification. Call this after wiring up `onCameraChange`/`onScreenChange`
    /// to get the initial pick.
    func resolveInitial() {
        resolveCamera()
        resolveScreen()
    }

    private func scheduleResolve() {
        pendingResolve?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.resolveCamera()
            self?.resolveScreen()
        }
        pendingResolve = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    // MARK: - Camera

    private func resolveCamera() {
        guard let device = preferredCamera(), device.uniqueID != lastCameraID else { return }
        lastCameraID = device.uniqueID
        onCameraChange?(device)
    }

    private func preferredCamera() -> AVCaptureDevice? {
        let devices = discoverCameras()
        if let external = devices.first(where: { $0.deviceType != .builtInWideAngleCamera }) {
            return external
        }
        return devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? devices.first
    }

    private func discoverCameras() -> [AVCaptureDevice] {
        if #available(macOS 14.0, *) {
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                mediaType: .video,
                position: .unspecified
            )
            return session.devices
        }
        // Pre-macOS 14 has no non-deprecated way to enumerate external cameras
        // specifically, so fall back to the full (deprecated) device list.
        return AVCaptureDevice.devices(for: .video)
    }

    // MARK: - Screen

    private func resolveScreen() {
        guard let screen = preferredScreen(), screen.displayIdentifier != lastScreenID else { return }
        lastScreenID = screen.displayIdentifier
        onScreenChange?(screen)
    }

    private func preferredScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let external = screens.first(where: { !$0.isBuiltIn }) {
            return external
        }
        return screens.first(where: { $0.isBuiltIn }) ?? NSScreen.main
    }

    // MARK: - Manual relocation (user dragged the Mirror onto a different screen)

    /// Called when the user deliberately drags the Mirror onto a different screen.
    /// Forces the camera to match that screen (built-in cam for the built-in
    /// display, else the usual "prefer external" pick) and updates the dedupe
    /// bookkeeping so a later automatic re-resolve (from an unrelated device
    /// event) doesn't fight the user's placement by snapping the camera back.
    func userRelocated(to screen: NSScreen) {
        lastScreenID = screen.displayIdentifier

        let devices = discoverCameras()
        let device = screen.isBuiltIn
            ? devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            : (devices.first(where: { $0.deviceType != .builtInWideAngleCamera }) ?? devices.first)
        guard let device else { return }
        lastCameraID = device.uniqueID
        onCameraChange?(device)
    }
}

extension NSScreen {
    var isBuiltIn: Bool {
        guard let id = displayIdentifier else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    var displayIdentifier: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
