import AVFoundation
import AppKit

protocol CameraFrameReceiver: AnyObject {
    func cameraController(_ controller: CameraController, didOutput sampleBuffer: CMSampleBuffer)
}

final class CameraController: NSObject {
    let session = AVCaptureSession()
    private let videoOutputQueue = DispatchQueue(label: "narcissus.camera.output")
    private let videoOutput = AVCaptureVideoDataOutput()

    weak var frameReceiver: CameraFrameReceiver?

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
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
