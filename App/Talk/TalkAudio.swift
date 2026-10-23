import AVFoundation
import BaikaKit

/// One frame of the microphone, ready for the wire, with its loudness for the orb.
struct TalkFrame: Sendable {
    var pcm: Data
    var level: Double
}

/// The microphone into 24 kHz PCM16 frames, and PCM16 frames into the speaker.
///
/// Ported from Loco's `VoiceAudio`. On the main actor like its owner: the engine is started,
/// stopped and rebuilt from here and nowhere else. The tap block runs on a realtime audio thread
/// and must not wait on anything, so everything it touches is in `Tap`, created once the input
/// format is known and used by that thread alone from then on; frames leave it through the
/// continuation, which is `Sendable` by design.
///
/// The audio session is `.playAndRecord` in `.voiceChat` mode with the speaker as the default
/// route, and voice processing is on for echo cancellation: without it the speaker's answer
/// comes back in as the next question.
@MainActor
final class TalkAudio {
    enum Failure: Error {
        /// No input device at all (a simulator whose host has none). The engine would crash on
        /// the tap.
        case noInput
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    let sampleRate = TalkLimits.sampleRate
    /// What the wire carries: mono, 16-bit, at the session's rate.
    private let wireFormat: AVAudioFormat
    /// What the player takes: the same, as floats, which the mixer resamples.
    private let playFormat: AVAudioFormat
    private let frames: AsyncStream<TalkFrame>.Continuation
    private var tap: Tap?
    private var observers: [NSObjectProtocol] = []
    private var stopped = false

    /// Called once, from the main actor, when the audio is gone for good: an interruption began,
    /// or the engine's configuration changed and it could not be brought back.
    var onLost: (@Sendable () -> Void)?

    init(frames: AsyncStream<TalkFrame>.Continuation) {
        let rate = Double(TalkLimits.sampleRate)
        wireFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true)!
        playFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        self.frames = frames
    }

    /// The microphone permission, asked for on the first tap on Talk and never before.
    static func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        let input = engine.inputNode
        // Echo cancellation. Best effort: a device that cannot do it still works, with the phone
        // held closer.
        try? input.setVoiceProcessingEnabled(true)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)

        do {
            try installTap()
            engine.prepare()
            try engine.start()
        } catch {
            // Half a start is worse than none: the tap and the session would stay behind.
            teardown()
            throw error
        }
        player.play()
        observe()
    }

    /// The tap, on whatever the input node's format is right now. A format with no rate or no
    /// channels is a machine with no microphone, and `installTap` on it is an Objective-C
    /// assertion Swift cannot catch, so it is refused here instead.
    private func installTap() throws {
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let tap = Tap(
                from: inFormat, to: wireFormat,
                frameBytes: PCM16.bytes(milliseconds: TalkLimits.frameMilliseconds, sampleRate: sampleRate),
                frames: frames)
        else {
            throw Failure.noInput
        }
        self.tap = tap
        // `@Sendable` matters: this class is on the main actor, and a plain closure formed here
        // would inherit that isolation. Swift 6 would then assert the main queue when the block
        // runs on the realtime audio thread, and the first microphone buffer would crash.
        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { @Sendable buffer, _ in
            tap.push(buffer)
        }
    }

    /// The two ways the audio is taken away while a conversation runs.
    ///
    /// A **configuration change** (AirPods in or out, a cable) stops the engine and changes the
    /// input format under the tap; the engine is rebuilt on the new format and restarted, and the
    /// person notices at most a missed word. An **interruption** (a call, Siri) is the end: by the
    /// time it is over, the server has long since decided the person went quiet.
    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.configurationChanged() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.lose() }
        })
    }

    private func configurationChanged() {
        guard !stopped else { return }
        engine.inputNode.removeTap(onBus: 0)
        tap = nil
        do {
            try installTap()
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            player.play()
        } catch {
            lose()
        }
    }

    private func lose() {
        guard !stopped else { return }
        let lost = onLost
        onLost = nil
        lost?()
    }

    /// Queues one chunk of the answer. `done` is called once it has been played back, or dropped
    /// by `stopPlayback`, on the engine's queue.
    func play(_ pcm: Data, done: @escaping @Sendable () -> Void) {
        let samples = PCM16.samples(pcm)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData
        else {
            done()
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let floats = PCM16.floats(samples)
        floats.withUnsafeBufferPointer { src in
            channel[0].update(from: src.baseAddress!, count: samples.count)
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in done() }
        if !player.isPlaying { player.play() }
    }

    /// Drops whatever is queued. The player starts again at once so the next answer needs
    /// nothing.
    func stopPlayback() {
        player.stop()
        player.play()
    }

    func stop() {
        stopped = true
        onLost = nil
        teardown()
    }

    private func teardown() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        engine.inputNode.removeTap(onBus: 0)
        tap = nil
        player.stop()
        engine.stop()
        frames.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// What the tap block owns: the converter, the bytes not yet a whole frame, and the way out.
    /// `@unchecked Sendable` because the SDK requires the block to be, and because the invariant
    /// that makes it safe (one thread, the audio thread, from install to removal) is not one the
    /// compiler can see.
    private final class Tap: @unchecked Sendable {
        private let converter: AVAudioConverter
        private let wire: AVAudioFormat
        private let frameBytes: Int
        private let frames: AsyncStream<TalkFrame>.Continuation
        private var pending = Data()

        /// Nil when no converter exists between the two formats: the no-microphone case again.
        init?(from input: AVAudioFormat, to wire: AVAudioFormat, frameBytes: Int, frames: AsyncStream<TalkFrame>.Continuation) {
            guard let converter = AVAudioConverter(from: input, to: wire) else { return nil }
            self.converter = converter
            self.wire = wire
            self.frameBytes = frameBytes
            self.frames = frames
        }

        func push(_ buffer: AVAudioPCMBuffer) {
            guard buffer.frameLength > 0 else { return }
            let ratio = wire.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: wire, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, out.frameLength > 0, let channels = out.int16ChannelData else { return }
            let count = Int(out.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channels[0], count: count))
            pending.append(PCM16.data(samples))
            while pending.count >= frameBytes {
                let frame = Data(pending.prefix(frameBytes))
                pending.removeFirst(frameBytes)
                frames.yield(TalkFrame(pcm: frame, level: PCM16.level(PCM16.samples(frame))))
            }
        }
    }
}
