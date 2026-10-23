import Foundation

/// The session's own timer. A session runs for the minutes the hub charged for; when they are
/// up the screen offers Continue, which mints a new session.
public struct TalkClock: Sendable, Equatable {
    public let minutes: Int
    public private(set) var secondsLeft: Int

    public init(minutes: Int = TalkLimits.defaultMinutes) {
        self.minutes = min(max(minutes, 1), TalkLimits.maxMinutes)
        secondsLeft = self.minutes * 60
    }

    public var isOver: Bool { secondsLeft <= 0 }

    /// One second passes. True on the tick that ran the time out, once.
    public mutating func tick() -> Bool {
        guard secondsLeft > 0 else { return false }
        secondsLeft -= 1
        return secondsLeft == 0
    }

    /// A new session: the full time again.
    public mutating func restart() { secondsLeft = minutes * 60 }
}

/// Why a Talk session is not live any more.
public enum TalkEnding: Sendable, Equatable {
    /// The person ended it.
    case reader
    /// The minutes ran out.
    case timeUp
    /// The socket closed under a live session, or the audio was taken away (a call came in).
    case dropped
    /// No microphone permission, or no microphone at all.
    case micDenied
    /// The session could not be opened, or the hub refused.
    case fault(TalkFault)

    /// A new session can pick the conversation up: the time ran out or the line dropped.
    public var offersContinue: Bool {
        switch self {
        case .timeUp, .dropped: true
        case .reader, .micDenied, .fault: false
        }
    }

    /// Tapping Talk again is a sensible next step (anything but the person's own end).
    public var offersRetry: Bool {
        switch self {
        case .reader, .timeUp, .dropped, .micDenied: false
        case .fault: true
        }
    }
}

public enum TalkFault: Sendable, Equatable {
    /// The hub said no, or could not be reached.
    case hub(BackendFailure)
    /// OpenAI's socket refused or did not answer.
    case connection
    /// The audio engine would not start.
    case audio
}
