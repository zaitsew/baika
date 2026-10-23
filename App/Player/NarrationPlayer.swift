import AVFoundation
import BaikaKit
import MediaPlayer
import Observation

/// Plays a story's mp3 chunks back to back, while later chunks may still be arriving.
///
/// One `AVQueuePlayer`, the `.playback` audio session (so it keeps playing with the screen
/// locked and the silent switch on), lock-screen Now Playing info, and play, pause and skip
/// plus or minus 15 seconds from the lock screen and headphones.
///
/// Time is counted across the whole story: chunk lengths are summed, using the real duration of
/// a chunk once its file is read and an estimate before that.
@MainActor
@Observable
final class NarrationPlayer {
    enum State: Equatable {
        case idle
        case playing
        case paused
        /// Waiting for the next chunk to arrive.
        case buffering
        case finished
    }

    private(set) var state: State = .idle
    private(set) var title = ""
    private(set) var storyID: UUID?
    /// The chunk playing now.
    private(set) var currentChunk = 0
    /// Seconds into the whole story.
    private(set) var elapsed: TimeInterval = 0
    /// Seconds in the whole story: exact once every chunk is read, an estimate before that.
    private(set) var duration: TimeInterval = 0
    /// Chunks the story will have, or will have if the narration is cut short.
    private(set) var expectedChunks = 0

    var isPlaying: Bool { state == .playing }
    var isActive: Bool { state != .idle }

    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private var urls: [URL?] = []
    @ObservationIgnored private var durations: [TimeInterval?] = []
    @ObservationIgnored private var estimates: [TimeInterval] = []
    @ObservationIgnored private var nextToQueue = 0
    @ObservationIgnored private var wantsPlay = true
    @ObservationIgnored private var indexOfItem: [ObjectIdentifier: Int] = [:]
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var commandsInstalled = false
    @ObservationIgnored private var lastNowPlayingSecond = -1
    @ObservationIgnored private var generation = PlaybackGeneration()
    /// Playback was running when an interruption began, so it may resume when it ends.
    @ObservationIgnored private var playingBeforeInterruption = false

    /// How far a skip button jumps.
    nonisolated static let skipSeconds: TimeInterval = 15
    /// A calm narrator speaks about this many characters a second; only used before a chunk's
    /// real length is known.
    nonisolated static let charactersPerSecond = 14.0

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let item = note.object as? AVPlayerItem
            Task { @MainActor in if let item { self?.itemDidEnd(item) } }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in self?.interruption(type: type, options: options) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                // Headphones pulled out: stop talking into the room.
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
            }
        })
    }

    // MARK: Loading

    /// Starts a story. Chunks arrive later through `enqueue`; a stored story passes all its
    /// files straight after.
    func start(storyID: UUID, title: String, chunkEstimates: [TimeInterval]) {
        reset()
        self.storyID = storyID
        self.title = title
        estimates = chunkEstimates
        expectedChunks = chunkEstimates.count
        urls = Array(repeating: nil, count: expectedChunks)
        durations = Array(repeating: nil, count: expectedChunks)
        duration = chunkEstimates.reduce(0, +)
        wantsPlay = true
        state = .buffering
        activateSession()
        installRemoteCommands()
        updateNowPlaying()
    }

    /// Estimated seconds of speech for a chunk of this many characters.
    nonisolated static func estimate(characters: Int) -> TimeInterval {
        max(1, Double(characters) / charactersPerSecond)
    }

    /// A chunk's file is ready. A chunk of a story the player no longer holds is dropped.
    func enqueue(storyID: UUID, index: Int, url: URL) {
        guard ChunkOwnership.accepts(chunkStory: storyID, playing: self.storyID) else { return }
        guard urls.indices.contains(index) else { return }
        urls[index] = url
        let token = generation.value
        Task { [weak self] in
            let seconds = try? await AVURLAsset(url: url).load(.duration).seconds
            guard let self, self.generation.isCurrent(token) else { return }
            if let seconds, seconds.isFinite, seconds > 0 { self.setDuration(seconds, for: index) }
        }
        queueAvailable()
    }

    /// No more chunks will arrive (an error ended the narration early). What has arrived is the
    /// whole story as far as the player is concerned.
    func endProduction() {
        let arrived = urls.prefix { $0 != nil }.count
        guard arrived < expectedChunks else { return }
        expectedChunks = arrived
        urls = Array(urls.prefix(arrived))
        durations = Array(durations.prefix(arrived))
        estimates = Array(estimates.prefix(arrived))
        if state == .buffering, nextToQueue >= expectedChunks, player.currentItem == nil {
            finish()
        }
        tick()
    }

    /// Chunk `index` or a later one has started playing, or nothing is playing any more.
    func hasStarted(chunk index: Int) -> Bool {
        currentChunk >= index || state == .idle || state == .finished
    }

    // MARK: Controls

    func pause() {
        wantsPlay = false
        player.pause()
        if state == .playing || state == .buffering { state = .paused }
        updateNowPlaying()
    }

    func resume() {
        wantsPlay = true
        switch state {
        case .idle:
            return
        case .finished:
            seek(toGlobal: 0)
            return
        case .playing, .paused, .buffering:
            if player.currentItem != nil {
                player.play()
                state = .playing
            } else {
                state = .buffering
                queueAvailable()
            }
        }
        updateNowPlaying()
    }

    func togglePlayPause() {
        if state == .playing || (state == .buffering && wantsPlay) {
            pause()
        } else {
            resume()
        }
    }

    func skip(by seconds: TimeInterval) {
        guard state != .idle else { return }
        seek(toGlobal: elapsed + seconds)
    }

    func stop() {
        reset()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Queue

    private func reset() {
        generation.advance()
        playingBeforeInterruption = false
        player.pause()
        player.removeAllItems()
        indexOfItem.removeAll()
        urls = []
        durations = []
        estimates = []
        nextToQueue = 0
        expectedChunks = 0
        currentChunk = 0
        elapsed = 0
        duration = 0
        storyID = nil
        title = ""
        state = .idle
        lastNowPlayingSecond = -1
    }

    private func queueAvailable() {
        while nextToQueue < urls.count, let url = urls[nextToQueue] {
            insert(url, index: nextToQueue)
            nextToQueue += 1
        }
        guard wantsPlay, state == .buffering, player.currentItem != nil else { return }
        player.play()
        state = .playing
        updateNowPlaying()
    }

    private func insert(_ url: URL, index: Int) {
        let item = AVPlayerItem(url: url)
        indexOfItem[ObjectIdentifier(item)] = index
        player.insert(item, after: nil)
    }

    private func setDuration(_ seconds: TimeInterval, for index: Int) {
        guard durations.indices.contains(index) else { return }
        durations[index] = seconds
        duration = totalDuration()
    }

    private func itemDidEnd(_ item: AVPlayerItem) {
        guard let index = indexOfItem[ObjectIdentifier(item)] else { return }
        indexOfItem[ObjectIdentifier(item)] = nil
        if index + 1 >= expectedChunks {
            finish()
        } else if index + 1 >= nextToQueue {
            // The next chunk has not arrived: wait for it.
            state = wantsPlay ? .buffering : .paused
            updateNowPlaying()
        }
    }

    private func finish() {
        state = .finished
        wantsPlay = false
        elapsed = totalDuration()
        duration = elapsed
        updateNowPlaying()
    }

    // MARK: Time

    private func length(of index: Int) -> TimeInterval {
        durations[index] ?? (estimates.indices.contains(index) ? estimates[index] : 0)
    }

    private func start(of index: Int) -> TimeInterval {
        (0..<min(index, durations.count)).reduce(0) { $0 + length(of: $1) }
    }

    private func totalDuration() -> TimeInterval { start(of: durations.count) }

    private func tick() {
        guard state != .idle else { return }
        guard let item = player.currentItem, let index = indexOfItem[ObjectIdentifier(item)] else { return }
        let seconds = item.currentTime().seconds
        currentChunk = index
        elapsed = start(of: index) + (seconds.isFinite ? max(0, seconds) : 0)
        duration = totalDuration()
        if Int(elapsed) != lastNowPlayingSecond {
            lastNowPlayingSecond = Int(elapsed)
            updateNowPlaying()
        }
    }

    /// Jumps to a time in the whole story, clamped to the audio that has arrived.
    private func seek(toGlobal time: TimeInterval) {
        let available = urls.prefix { $0 != nil }.count
        guard available > 0 else { return }
        let end = start(of: available)
        let target = min(max(0, time), end)
        var chunk = 0
        var offset = target
        for index in 0..<available {
            let length = length(of: index)
            if target < start(of: index) + length || index == available - 1 {
                chunk = index
                offset = max(0, min(target - start(of: index), length))
                break
            }
        }
        let wasFinished = state == .finished
        if wasFinished || chunk != currentChunk || player.currentItem == nil {
            player.removeAllItems()
            indexOfItem.removeAll()
            nextToQueue = chunk
            while nextToQueue < urls.count, let url = urls[nextToQueue] {
                insert(url, index: nextToQueue)
                nextToQueue += 1
            }
            currentChunk = chunk
        }
        if wasFinished { wantsPlay = true }
        player.seek(to: CMTime(seconds: offset, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        elapsed = start(of: chunk) + offset
        if wantsPlay, player.currentItem != nil {
            player.play()
            state = .playing
        } else if state == .finished {
            state = .paused
        }
        updateNowPlaying()
    }

    // MARK: System

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    private func interruption(type: UInt?, options: UInt?) {
        guard let type, let kind = AVAudioSession.InterruptionType(rawValue: type) else { return }
        switch kind {
        case .began:
            playingBeforeInterruption = state == .playing
            if state == .playing { pause() }
        case .ended:
            let resume = AVAudioSession.InterruptionOptions(rawValue: options ?? 0).contains(.shouldResume)
            let wasPlaying = playingBeforeInterruption
            playingBeforeInterruption = false
            if resume, wasPlaying, state == .paused { self.resume() }
        @unknown default:
            break
        }
    }

    private func installRemoteCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipSeconds)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: Self.skipSeconds) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipSeconds)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -Self.skipSeconds) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
            Task { @MainActor in self?.seek(toGlobal: position) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard state != .idle else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Baika",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }
}
