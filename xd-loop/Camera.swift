import AVFoundation
import os

// The webcam, shrunk to a small grid of brightness values for the Webcam pattern.
// It only runs while that pattern is on screen. Frames arrive on a background queue,
// so this class isn't tied to the main thread
nonisolated final class CameraFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let shared = CameraFeed()

    // Each frame becomes this many brightness samples (0-255), mirrored like a selfie view
    static let width = 160
    static let height = 120

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "xd-loop.camera")
    private let frame = OSAllocatedUnfairLock<[UInt8]?>(initialState: nil)
    private var configured = false

    // The newest frame, or nil before the first one arrives
    var latest: [UInt8]? { frame.withLock { $0 } }

    static var status: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    func start() {
        queue.async { [self] in
            if !configured { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            frame.withLock { $0 = nil }
        }
    }

    private func configure() {
        configured = true
        session.sessionPreset = .vga640x480
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        // Ask for the brightness plane directly, so there's no colour conversion to do
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }

        let w = CVPixelBufferGetWidthOfPlane(pixels, 0)
        let h = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)

        var small = [UInt8](repeating: 0, count: Self.width * Self.height)
        for y in 0..<Self.height {
            let sy = y * h / Self.height
            for x in 0..<Self.width {
                let sx = (Self.width - 1 - x) * w / Self.width   // mirrored
                small[y * Self.width + x] = luma[sy * rowBytes + sx]
            }
        }
        let finished = small
        frame.withLock { $0 = finished }
    }
}
