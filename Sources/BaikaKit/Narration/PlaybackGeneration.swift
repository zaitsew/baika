import Foundation

/// A counter the player bumps every time it starts or stops a story. Work that was started
/// under one generation (reading a chunk's length, say) checks its token before it writes
/// back, so a slow result for a story that is gone cannot touch the story that replaced it.
public struct PlaybackGeneration: Sendable, Equatable {
    public private(set) var value = 0

    public init() {}

    /// Starts a new generation and returns its token.
    @discardableResult
    public mutating func advance() -> Int {
        value += 1
        return value
    }

    /// The token belongs to the generation running now.
    public func isCurrent(_ token: Int) -> Bool { token == value }
}

/// Which chunks the shared player may take.
public enum ChunkOwnership {
    /// A chunk of `chunkStory` is accepted only while that story is the one the player holds.
    public static func accepts(chunkStory: UUID, playing: UUID?) -> Bool {
        playing == chunkStory
    }
}
