import Foundation
import Testing
@testable import BaikaKit

@Suite("Playback generation and chunk ownership")
struct PlaybackGenerationTests {
    @Test func aTokenIsCurrentOnlyUntilTheNextGeneration() {
        var generation = PlaybackGeneration()
        let first = generation.advance()
        #expect(generation.isCurrent(first))
        let second = generation.advance()
        #expect(!generation.isCurrent(first))
        #expect(generation.isCurrent(second))
    }

    @Test func aFreshCounterAcceptsNoIssuedToken() {
        var generation = PlaybackGeneration()
        let token = generation.advance()
        #expect(PlaybackGeneration().isCurrent(token) == false)
    }

    @Test func aChunkIsAcceptedOnlyForTheStoryThePlayerHolds() {
        let a = UUID()
        let b = UUID()
        #expect(ChunkOwnership.accepts(chunkStory: a, playing: a))
        #expect(!ChunkOwnership.accepts(chunkStory: a, playing: b))
        #expect(!ChunkOwnership.accepts(chunkStory: a, playing: nil))
    }
}
