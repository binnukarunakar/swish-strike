import AVFoundation
import CoreMedia

/// Owns the AVCaptureSession and emits throttled, timestamped sample buffers off
/// the main thread. The preview renders every frame; only every Nth frame is sent
/// downstream for detection. Capture rotation is locked to portrait so the
/// normalized detection space always matches the preview the user framed.
/// @unchecked Sendable: every mutable member is confined to `sessionQueue` /
/// `sampleQueue`; the class is its own synchronization domain.
final class CameraManager: NSObject, ObservableObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "swish.camera.session")
    private let sampleQueue = DispatchQueue(label: "swish.camera.samples")
    private var configured = false

    /// (sampleBuffer, timestampSeconds). Called on `sampleQueue`. The full sample
    /// buffer is forwarded because Vision's trajectory request needs frame timing.
    var onFrame: ((CMSampleBuffer, Double) -> Void)?

    /// Process roughly this many frames per second for detection (decoupled from
    /// the camera's capture rate). The engine math is resolution-independent.
    var targetDetectionFPS: Double = 15
    private var lastProcessed: Double = 0

    /// The current camera permission, for driving UI states.
    static var authorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    override init() {
        super.init()
        // A phone call or media-services reset stops the session without the
        // app doing anything; restart when the interruption clears so the feed
        // doesn't stay black until the user leaves and re-enters the game.
        for name in [AVCaptureSession.interruptionEndedNotification,
                     AVCaptureSession.runtimeErrorNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: session, queue: nil
            ) { [weak self] _ in self?.start() }
        }
    }

    func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func configure() {
        sessionQueue.async {
            guard !self.configured else { return }
            self.configured = true
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true   // backpressure
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sampleQueue)
            if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }
            // Lock buffers upright (portrait): detection coordinates and the
            // preview then share one frame of reference.
            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            self.session.commitConfiguration()
        }
    }

    func start() { sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop()  { sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } } }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        // Frame-skip throttle to the target detection rate.
        let minInterval = 1.0 / targetDetectionFPS
        guard t - lastProcessed >= minInterval else { return }
        lastProcessed = t
        onFrame?(sampleBuffer, t)
    }
}
