import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var faceWindow: FaceWindow!
    private var cameraController: CameraController!
    private var deviceCoordinator: DeviceCoordinator!
    private var toggleItem: NSMenuItem!

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
        cameraController.onFeedStateChange = { [weak self] state in
            self?.faceWindow.setFeedState(state)
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
        // Synchronous so the camera indicator light never outlives the app.
        cameraController.stopSync()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        toggleItem = NSMenuItem(title: "Hide Mirror", action: #selector(toggleWindow), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let resetItem = NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About Narcissus", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Narcissus", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = faceWindow.isMirrorVisible ? "Hide Mirror" : "Show Mirror"
    }

    @objc private func toggleWindow() {
        // Stop the capture session while hidden: no camera indicator light and no
        // CPU spent detecting/rendering frames nobody can see.
        if faceWindow.isMirrorVisible {
            faceWindow.hideWindow()
            cameraController.stop()
        } else {
            cameraController.start()
            faceWindow.showWindow()
            faceWindow.beginTransitionBlur()
        }
    }

    @objc private func resetPosition() {
        faceWindow.resetPosition()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
