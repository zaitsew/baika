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

@Suite("Narration claims")
struct NarrationClaimsTests {
    @Test func aSecondNarratorIsRefusedForTheSameStory() {
        var claims = NarrationClaims<Int>()
        let story = UUID()
        let first = claims.claim(story, for: 1)
        let second = claims.claim(story, for: 2)
        #expect(first)
        #expect(!second)
        #expect(claims.owner(of: story) == 1)
    }

    @Test func theSameNarratorMayClaimAgain() {
        var claims = NarrationClaims<Int>()
        let story = UUID()
        let first = claims.claim(story, for: 1)
        let again = claims.claim(story, for: 1)
        #expect(first && again)
    }

    @Test func otherStoriesAreIndependent() {
        var claims = NarrationClaims<Int>()
        let a = claims.claim(UUID(), for: 1)
        let b = claims.claim(UUID(), for: 2)
        #expect(a && b)
    }

    @Test func onlyTheHolderCanRelease() {
        var claims = NarrationClaims<Int>()
        let story = UUID()
        claims.claim(story, for: 1)
        claims.release(story, for: 2)
        #expect(claims.isClaimed(story))
        claims.release(story, for: 1)
        #expect(!claims.isClaimed(story))
        let next = claims.claim(story, for: 2)
        #expect(next)
    }

    @Test func revokeFreesTheStoryForAnyone() {
        var claims = NarrationClaims<Int>()
        let story = UUID()
        claims.claim(story, for: 1)
        let revoked = claims.revoke(story)
        let next = claims.claim(story, for: 2)
        let none = claims.revoke(UUID())
        #expect(revoked == 1)
        #expect(next)
        #expect(none == nil)
    }
}
