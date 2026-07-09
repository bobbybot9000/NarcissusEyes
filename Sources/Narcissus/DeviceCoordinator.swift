import AVFoundation
import AppKit
import CoreGraphics

/// Picks which camera and which screen Narcissus should use, preferring an
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
        guard let screen = preferredScreen(), displayID(for: screen) != lastScreenID else { return }
        lastScreenID = displayID(for: screen)
        onScreenChange?(screen)
    }

    private func preferredScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let external = screens.first(where: { !isBuiltIn($0) }) {
            return external
        }
        return screens.first(where: { isBuiltIn($0) }) ?? NSScreen.main
    }

    private func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let id = displayID(for: screen) else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
