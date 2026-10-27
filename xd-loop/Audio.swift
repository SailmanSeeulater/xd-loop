import AVFoundation
import os

// Listens to the microphone while the cover is up and turns loudness into a 0...1 "beat" level.
// Only the loudness number is kept; no audio is stored or sent anywhere.
// The audio arrives on a background thread, so this class isn't tied to the main thread
nonisolated final class AudioMeter: @unchecked Sendable {
    static let shared = AudioMeter()

    private let engine = AVAudioEngine()
    private let envelope = OSAllocatedUnfairLock(initialState: Float(0))
    private var running = false

    // Jumps up instantly on a loud moment, then falls back over about a second
    var level: Double { Double(envelope.withLock { $0 }) }

    static var isAllowed: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    func start() {
        guard !running, Self.isAllowed else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }   // no microphone

        let envelope = self.envelope
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            let rms = (sum / Float(max(count, 1))).squareRoot()
            // Quiet room (about -50 dB) is 0, loud music (about -10 dB) is 1
            let loudness = min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 50) / 40))
            envelope.withLock { $0 = max(loudness, $0 * 0.85) }
        }
        do {
            try engine.start()
            running = true
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        envelope.withLock { $0 = 0 }
    }
}
