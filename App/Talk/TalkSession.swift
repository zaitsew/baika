import BaikaKit
import Foundation
import Observation

/// One spoken conversation with the storyteller, as state.
///
/// The screen taps one button; this asks the hub for a client secret, opens a WebSocket to the
/// Realtime API with it, runs the microphone into the socket and the socket into the speaker, and
/// keeps the transcript. When the person starts talking over an answer, the queued audio is
/// dropped on the spot (the server cancels its side on its own) and the server is told how much
/// of the answer was actually heard, so its memory of the conversation matches the person's.
///
/// Ported from Loco's `VoiceSession`, without GPT-Live, the trip and the history outbox. The
/// pieces and where they run: this class on the main actor (the phase the screen draws, the
/// transcript, the timer, the socket's receive loop); `TalkAudio` also on the main actor, with
/// its tap block on a realtime audio thread handing frames back through an `AsyncStream`.
@MainActor
@Observable
final class TalkSession {
    enum Phase: Equatable {
        case idle
        /// Waiting on the microphone permission and the hub.
        case asking
        /// The socket is opening; `session.created` has not arrived.
        case connecting
        /// Live, and the person may talk.
        case listening
        /// Live, and the answer is playing.
        case answering
        case ended(TalkEnding)
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript = TalkTranscript()
    /// The microphone's loudness, 0...1, for the orb while it listens.
    private(set) var level: Double = 0
    /// The storyteller's voice loudness, 0...1, for the orb while it answers.
    private(set) var outLevel: Double = 0
    /// The microphone is muted: the storyteller keeps talking and the clock keeps running; only
    /// what the storyteller hears changes. Reset at every start.
    private(set) var isMuted = false

    var isLive: Bool { phase == .listening || phase == .answering }
    var isEnded: Bool {
        if case .ended = phase { return true }
        return false
    }
    /// True from the tap on Talk until the session is over: the screen shows the live layout.
    var isActive: Bool { phase != .idle && !isEnded }

    @ObservationIgnored private let backend: any RealtimeBackend
    @ObservationIgnored private let beforeStart: @MainActor () -> Void
    @ObservationIgnored private var talkClock = TalkClock()
    @ObservationIgnored private var gate = MuteGate()
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var audio: TalkAudio?
    @ObservationIgnored private var receiving: Task<Void, Never>?
    @ObservationIgnored private var sending: Task<Void, Never>?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var pinging: Task<Void, Never>?
    @ObservationIgnored private var handshake: Task<Void, Never>?
    /// What the last start was asked with, so Continue can start the same conversation again.
    @ObservationIgnored private var lastStyle: ResolvedStyle?
    @ObservationIgnored private var lastLanguage: StoryLanguage = .default
    /// Buffers scheduled on the player and not yet played back, for this answer.
    @ObservationIgnored private var buffersInFlight = 0
    /// Whether the server has sent the last audio of the current answer.
    @ObservationIgnored private var answerAudioDone = false
    /// The answer's conversation item, and how much of it has been played: what
    /// `conversation.item.truncate` needs when the person interrupts.
    @ObservationIgnored private var answerItemId: String?
    @ObservationIgnored private var playedSeconds: Double = 0
    /// Bumped by every start and every end, so a callback from a session that has ended (a late
    /// `receive`, a buffer that finished playing) cannot touch the one that replaced it.
    @ObservationIgnored private var generation = 0

    /// `beforeStart` runs when the person taps Talk: it stops Perform's playback, which holds the
    /// audio session in another category.
    init(backend: any RealtimeBackend, beforeStart: @escaping @MainActor () -> Void) {
        self.backend = backend
        self.beforeStart = beforeStart
    }

    // MARK: Starting

    /// Asks for the microphone, starts the engine, mints a secret, opens the socket. Returns when
    /// the session is live or over; the screen watches `phase`.
    func start(style: ResolvedStyle, language: StoryLanguage, continuing: Bool = false) async {
        guard phase == .idle || isEnded else { return }
        generation += 1
        let gen = generation
        let recap = continuing ? transcript.spoken : []
        if !continuing { transcript = TalkTranscript() }
        lastStyle = style
        lastLanguage = language
        level = 0
        outLevel = 0
        isMuted = false
        gate = MuteGate()
        buffersInFlight = 0
        answerAudioDone = false
        answerItemId = nil
        playedSeconds = 0
        phase = .asking
        beforeStart()

        // The permission first, before anything is paid for: a secret minted for a microphone
        // that is never opened is a reservation for nothing.
        guard await TalkAudio.requestMicrophone() else {
            guard gen == generation else { return }
            phase = .ended(.micDenied)
            return
        }
        guard gen == generation else { return }

        // The engine next, for the same reason: audio that cannot start must not cost a session.
        let (frames, continuation) = AsyncStream.makeStream(of: TalkFrame.self, bufferingPolicy: .bufferingNewest(64))
        let engine = TalkAudio(frames: continuation)
        engine.onLost = { [weak self] in
            Task { @MainActor in self?.lost(gen: gen) }
        }
        do {
            try engine.start()
        } catch TalkAudio.Failure.noInput {
            continuation.finish()
            phase = .ended(.micDenied)
            return
        } catch {
            continuation.finish()
            phase = .ended(.fault(.audio))
            return
        }
        audio = engine
        sending = Task { [weak self] in await self?.pump(frames, gen: gen) }

        // Mint right before connecting: the secret opens a session for two minutes only.
        let request = RealtimeSessionRequest(
            instructions: TalkPersona.instructions(style: style, language: language, recap: recap))
        let grant: RealtimeGrant
        do {
            grant = try await backend.mint(request)
        } catch is CancellationError {
            return
        } catch let failure as BackendFailure {
            guard gen == generation else { return }
            end(.fault(.hub(failure)))
            return
        } catch {
            guard gen == generation else { return }
            end(.fault(.hub(.offline)))
            return
        }
        guard gen == generation else { return }
        guard grant.isUsable() else {
            end(.fault(.connection))
            return
        }

        phase = .connecting
        talkClock = TalkClock(minutes: request.minutes)
        let task = URLSession.shared.webSocketTask(with: grant.socketRequest)
        socket = task
        task.resume()

        receiving = Task { [weak self] in await self?.receive(gen: gen) }
        handshake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(TalkLimits.handshakeSeconds))
            guard let self, self.generation == gen, !Task.isCancelled, self.phase == .connecting else { return }
            self.end(.fault(.connection))
        }
        // A quiet socket is a socket something in between may close. The pause after an answer
        // is the person thinking; the ping says so.
        pinging = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(TalkLimits.pingSeconds))
                guard let self, self.generation == gen, !Task.isCancelled, let socket = self.socket else { return }
                socket.sendPing { _ in }
            }
        }
    }

    /// Starts a new session that picks the conversation up after a time-out or a dropped line:
    /// the same style and language, and the earlier turns in the new session's instructions.
    func continueConversation() async {
        guard isEnded, let style = lastStyle else { return }
        await start(style: style, language: lastLanguage, continuing: true)
    }

    // MARK: Mute

    /// Mutes or unmutes the microphone. The session and its clock keep running.
    func setMuted(_ on: Bool) {
        guard on != isMuted else { return }
        isMuted = on
        gate.setMuted(on)
        level = 0
    }

    func toggleMute() { setMuted(!isMuted) }

    // MARK: Ending

    /// Ends the conversation, whoever asked. Safe to call twice.
    func end(_ reason: TalkEnding = .reader) {
        guard !isEnded, phase != .idle else { return }
        generation += 1
        receiving?.cancel()
        sending?.cancel()
        clock?.cancel()
        pinging?.cancel()
        handshake?.cancel()
        receiving = nil
        sending = nil
        clock = nil
        pinging = nil
        handshake = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        audio?.stop()
        audio = nil
        level = 0
        outLevel = 0
        buffersInFlight = 0
        phase = .ended(reason)
    }

    /// Leaves the end screen for the start screen. A live session is not touched.
    func dismissEnded() {
        guard isEnded else { return }
        phase = .idle
    }

    /// The engine lost the audio: a phone call, the route changed and could not be rebuilt. A
    /// screen that looked live while the minutes counted down would be worse than an honest end.
    private func lost(gen: Int) {
        guard gen == generation else { return }
        end(.dropped)
    }

    // MARK: Microphone to socket

    private func pump(_ frames: AsyncStream<TalkFrame>, gen: Int) async {
        for await frame in frames {
            guard generation == gen else { return }
            level = isMuted ? 0 : frame.level
            // Nothing goes up before `session.created`: the server would refuse it, and the
            // person has not been told to talk yet.
            guard isLive, let socket else { continue }
            // Muted: a second of silence in place of the first frames, so the server commits what
            // was said just before the tap; then nothing while the tap keeps draining here.
            guard let pcm = gate.outgoing(frame.pcm) else { continue }
            try? await socket.send(.string(RealtimeClientEvent.appendAudio(pcm).text))
        }
    }

    // MARK: The socket

    private func receive(gen: Int) async {
        while !Task.isCancelled, let socket {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                guard gen == generation else { return }
                // A close under a live session is a drop; one while opening is a refusal (the
                // secret was stale, or the session was not accepted).
                end(isLive ? .dropped : .fault(.connection))
                return
            }
            guard gen == generation else { return }
            let data: Data
            switch message {
            case .string(let text): data = Data(text.utf8)
            case .data(let bytes): data = bytes
            @unknown default: continue
            }
            guard let event = RealtimeServerEvent.parse(data) else { continue }
            handle(event, gen: gen)
        }
    }

    private func handle(_ event: RealtimeServerEvent, gen: Int) {
        transcript.apply(event)
        switch event {
        case .sessionCreated:
            guard phase == .connecting else { return }
            phase = .listening
            handshake?.cancel()
            handshake = nil
            startClock(gen: gen)
        case .answerItem(let id):
            answerItemId = id
            playedSeconds = 0
            answerAudioDone = false
        case .speechStarted:
            // The person is talking over the answer. What is queued on the phone is dropped now;
            // the server cancels its own side (`interrupt_response`). The server is also told how
            // much was heard: it generates faster than the phone plays, so by now the whole
            // answer is usually in its conversation, most of it never spoken aloud.
            if let id = answerItemId, buffersInFlight > 0 || !answerAudioDone {
                send(.truncate(itemId: id, audioEndMs: Int(playedSeconds * 1000)))
            }
            answerItemId = nil
            audio?.stopPlayback()
            buffersInFlight = 0
            outLevel = 0
            answerAudioDone = false
            if phase == .answering { phase = .listening }
        case .audio(let pcm):
            guard !pcm.isEmpty, let audio else { return }
            answerAudioDone = false
            if phase == .listening { phase = .answering }
            buffersInFlight += 1
            outLevel = PCM16.level(of: pcm)
            let seconds = PCM16.seconds(pcm, sampleRate: audio.sampleRate)
            audio.play(pcm) { [weak self] in
                Task { @MainActor in self?.played(gen: gen, seconds: seconds) }
            }
        case .audioDone:
            answerAudioDone = true
            if buffersInFlight == 0, phase == .answering { phase = .listening }
        case .responseDone:
            // Whatever the answer's fate (completed, cancelled, failed) no more audio is coming
            // for it. A failed one may never have said `output_audio.done`.
            answerAudioDone = true
            if buffersInFlight == 0, phase == .answering { phase = .listening }
        case .error(_, let message):
            // Most errors are recoverable and the session stays open, so an error is logged, not
            // an ending. The one that is an ending: an error before the session was created.
            debugLog("talk: \(message)")
            if phase == .connecting { end(.fault(.connection)) }
        case .speechStopped, .committed, .heard, .transcriptionFailed, .sayingDelta, .said, .other:
            break
        }
    }

    private func send(_ event: RealtimeClientEvent) {
        guard let socket else { return }
        socket.send(.string(event.text)) { _ in }
    }

    /// One buffer finished playing. The answer is over when the server has sent its last audio
    /// and the phone has played its last buffer.
    private func played(gen: Int, seconds: Double) {
        guard gen == generation else { return }
        playedSeconds += seconds
        buffersInFlight = max(0, buffersInFlight - 1)
        if buffersInFlight == 0 { outLevel = 0 }
        if buffersInFlight == 0, answerAudioDone, phase == .answering { phase = .listening }
    }

    // MARK: The session's clock

    private func startClock(gen: Int) {
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.generation == gen, !Task.isCancelled else { return }
                if self.talkClock.tick() {
                    self.end(.timeUp)
                    return
                }
            }
        }
    }

    private nonisolated func debugLog(_ line: String) {
        #if DEBUG
        print(line)
        #endif
    }
}
