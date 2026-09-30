import AVFoundation
import AppKit

protocol CameraFrameReceiver: AnyObject {
    func cameraController(_ controller: CameraController, didOutput sampleBuffer: CMSampleBuffer)
}

/// Why the feed has no frames, so the UI can explain instead of showing black.
enum CameraFeedState {
    case running
    /// Permission denied or restricted (parental controls / MDM).
    case accessDenied
    /// Session should be running but frames stopped arriving (device yanked,
    /// permission revoked mid-run, etc.).
    case stalled
}

final class CameraController: NSObject {
    let session = AVCaptureSession()
    private let videoOutputQueue = DispatchQueue(label: "looknice.camera.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var currentInput: AVCaptureDeviceInput?

    weak var frameReceiver: CameraFrameReceiver?

    /// Fired on the main queue whenever the feed's availability changes.
    var onFeedStateChange: ((CameraFeedState) -> Void)?

    // Stall watchdog: lastFrameTime is written on the camera queue, read on the
    // main queue by the watchdog timer; guarded by the lock below.
    private let stateLock = NSLock()
    private var lastFrameTime: CFAbsoluteTime = 0
    private var shouldBeRunning = false
    private var reportedState: CameraFeedState = .running
    private var stallWatchdog: Timer?
    private let stallThreshold: CFAbsoluteTime = 3.0

    init(preferredDevice: AVCaptureDevice? = nil) {
        super.init()
        configureOutput()
        let device = preferredDevice ?? AVCaptureDevice.default(for: .video)
        if let device {
            setInput(device: device)
        }
    }

    private func configureOutput() {
        session.beginConfiguration()
        session.sessionPreset = .high

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
    }

    /// Swaps the active capture device without tearing down the session, so it can
    /// be called live when a preferred camera connects/disconnects.
    func reconfigure(device: AVCaptureDevice) {
        guard device.uniqueID != currentInput?.device.uniqueID else { return }
        setInput(device: device)
    }

    private func setInput(device: AVCaptureDevice) {
        guard let newInput = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        let previousInput = currentInput
        if let previousInput {
            session.removeInput(previousInput)
        }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentInput = newInput
        } else if let previousInput, session.canAddInput(previousInput) {
            // The new device was rejected — restore the old input rather than
            // leaving the session with no input at all (a permanently dead feed).
            session.addInput(previousInput)
        } else {
            currentInput = nil
        }

        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        session.commitConfiguration()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.startSession()
                } else {
                    self?.reportFeedState(.accessDenied)
                }
            }
        default:
            reportFeedState(.accessDenied)
        }
    }

    private func startSession() {
        stateLock.lock()
        shouldBeRunning = true
        lastFrameTime = CFAbsoluteTimeGetCurrent()
        stateLock.unlock()

        videoOutputQueue.async { [weak self] in
            self?.session.startRunning()
        }
        DispatchQueue.main.async { [weak self] in
            self?.startStallWatchdog()
        }
        reportFeedState(.running)
    }

    func stop() {
        stateLock.lock()
        shouldBeRunning = false
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.stallWatchdog?.invalidate()
            self?.stallWatchdog = nil
        }
        videoOutputQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    /// Blocking stop for app termination, so the camera indicator light never
    /// outlives the app.
    func stopSync() {
        stateLock.lock()
        shouldBeRunning = false
        stateLock.unlock()

        stallWatchdog?.invalidate()
        stallWatchdog = nil
        videoOutputQueue.sync { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Stall detection

    private func startStallWatchdog() {
        stallWatchdog?.invalidate()
        stallWatchdog = Timer.scheduledTimer(withTimeInterval: stallThreshold, repeats: true) { [weak self] _ in
            self?.checkForStall()
        }
    }

    private func checkForStall() {
        stateLock.lock()
        let running = shouldBeRunning
        let sinceLastFrame = CFAbsoluteTimeGetCurrent() - lastFrameTime
        stateLock.unlock()

        guard running else { return }
        reportFeedState(sinceLastFrame > stallThreshold ? .stalled : .running)
    }

    private func reportFeedState(_ state: CameraFeedState) {
        stateLock.lock()
        let changed = reportedState != state
        reportedState = state
        stateLock.unlock()
        guard changed else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onFeedStateChange?(state)
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        stateLock.lock()
        lastFrameTime = CFAbsoluteTimeGetCurrent()
        let wasStalled = reportedState == .stalled
        stateLock.unlock()
        if wasStalled {
            reportFeedState(.running)
        }
        frameReceiver?.cameraController(self, didOutput: sampleBuffer)
    }
}
