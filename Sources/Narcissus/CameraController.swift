import AVFoundation
import AppKit

protocol CameraFrameReceiver: AnyObject {
    func cameraController(_ controller: CameraController, didOutput sampleBuffer: CMSampleBuffer)
}

final class CameraController: NSObject {
    let session = AVCaptureSession()
    private let videoOutputQueue = DispatchQueue(label: "narcissus.camera.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var currentInput: AVCaptureDeviceInput?

    weak var frameReceiver: CameraFrameReceiver?

    /// The device currently feeding the session, if any.
    var activeDevice: AVCaptureDevice? { currentInput?.device }

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
        if let currentInput {
            session.removeInput(currentInput)
        }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentInput = newInput
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
                }
            }
        default:
            break
        }
    }

    private func startSession() {
        videoOutputQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        videoOutputQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameReceiver?.cameraController(self, didOutput: sampleBuffer)
    }
}
