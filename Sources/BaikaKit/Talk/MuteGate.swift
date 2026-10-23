import Foundation

/// What the microphone sends while muted. Mute keeps the session alive (the storyteller keeps
/// talking and the clock keeps running); only what the storyteller hears changes.
///
/// A person who mutes right after a sentence has not yet been followed by the silence the
/// server's turn detection waits for, so the first second after the tap is sent as zeroed
/// frames: the server hears the sentence end and answers. After that nothing is sent at all,
/// and no silence is billed. Ported from Loco's mute (its D210).
public struct MuteGate: Sendable, Equatable {
    /// One second of frames at the frame size the microphone tap produces.
    public static let tailFrames = max(1, 1000 / TalkLimits.frameMilliseconds)

    public private(set) var isMuted = false
    private var owed = 0

    public init() {}

    public mutating func setMuted(_ on: Bool) {
        guard on != isMuted else { return }
        isMuted = on
        owed = on ? Self.tailFrames : 0
    }

    /// What to send for one microphone frame. `capturedMuted` is the mute state when the frame
    /// was recorded, not when it is dequeued: a send that stalls must not let a frame recorded
    /// while muted go out after the person unmutes. A frame recorded live is sent as it is;
    /// one recorded muted becomes silence of the same length for the tail, then nothing.
    public mutating func outgoing(_ frame: Data, capturedMuted: Bool) -> Data? {
        guard capturedMuted else { return frame }
        guard owed > 0 else { return nil }
        owed -= 1
        return Data(count: frame.count)
    }
}
