import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var faceWindow: FaceWindow!
    private var cameraController: CameraController!
    private var deviceCoordinator: DeviceCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        deviceCoordinator = DeviceCoordinator()
        cameraController = CameraController()
        faceWindow = FaceWindow(cameraController: cameraController)

        deviceCoordinator.onCameraChange = { [weak self] device in
            self?.cameraController.reconfigure(device: device)
            self?.faceWindow.beginTransitionBlur()
        }
        deviceCoordinator.onScreenChange = { [weak self] screen in
            self?.faceWindow.setPreferredScreen(screen)
        }
        faceWindow.onUserRelocatedToScreen = { [weak self] screen in
            self?.deviceCoordinator.userRelocated(to: screen)
        }
        deviceCoordinator.resolveInitial()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "eye.circle", accessibilityDescription: "Narcissus")
        }
        statusItem.menu = buildMenu()

        cameraController.start()
        faceWindow.showWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cameraController.stop()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "Show/Hide", action: #selector(toggleWindow), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let resetItem = NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Narcissus", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func toggleWindow() {
        faceWindow.toggleVisibility()
    }

    @objc private func resetPosition() {
        faceWindow.resetPosition()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
