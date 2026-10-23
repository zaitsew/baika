import BaikaKit
import Foundation
import Observation

/// The Perform models that are narrating a story, so deleting the story can stop them and a
/// second narrator of the same story is refused. Observable: a story's page hides "Finish the
/// narration" while any narration of that story runs.
@MainActor
@Observable
final class NarrationRegistry {
    private final class Entry {
        weak var model: PerformModel?
        init(_ model: PerformModel) { self.model = model }
    }

    private var claims = NarrationClaims<ObjectIdentifier>()
    @ObservationIgnored private var models: [UUID: Entry] = [:]

    /// Takes the story for `model`. False when a different live model already narrates it.
    @discardableResult
    func register(_ model: PerformModel, storyID: UUID) -> Bool {
        // A model that went away without unregistering does not hold the story.
        if let entry = models[storyID], entry.model == nil { drop(storyID) }
        guard claims.claim(storyID, for: ObjectIdentifier(model)) else { return false }
        models[storyID] = Entry(model)
        return true
    }

    func unregister(_ model: PerformModel, storyID: UUID) {
        claims.release(storyID, for: ObjectIdentifier(model))
        if !claims.isClaimed(storyID) { models[storyID] = nil }
    }

    /// Some narration of the story is running now.
    func isNarrating(storyID: UUID) -> Bool {
        guard claims.isClaimed(storyID) else { return false }
        return models[storyID]?.model != nil
    }

    /// Cancels the narration of the story and returns its screen to idle.
    func abandon(storyID: UUID) {
        let model = models[storyID]?.model
        drop(storyID)
        model?.abandon(storyID: storyID)
    }

    private func drop(_ storyID: UUID) {
        claims.revoke(storyID)
        models[storyID] = nil
    }
}

extension AppModel {
    /// Every chunk file of the story is on this device.
    func audioIsComplete(_ story: Story) -> Bool {
        !story.chunkFileNames.isEmpty
            && cache.missingChunks(storyID: story.id, fileNames: story.chunkFileNames).isEmpty
    }

    /// Plays a stored story from the first second, from the files on the device: no network.
    func playStored(_ story: Story) {
        let names = story.chunkFileNames
        guard !names.isEmpty else { return }
        var estimates = story.chunkEstimates()
        if estimates.count != names.count {
            // The chunker changed since this story was made: spread the estimate evenly.
            let each = NarrationPlayer.estimate(characters: story.script.utf16.count) / Double(names.count)
            estimates = Array(repeating: each, count: names.count)
        }
        player.start(storyID: story.id, title: story.title, chunkEstimates: estimates)
        for (index, name) in names.enumerated() {
            player.enqueue(storyID: story.id, index: index, url: cache.url(for: story.id, fileName: name))
        }
    }

    /// Removes a story, its audio, and stops it if it is the one playing. Any narration still
    /// running for it is cancelled first, so it cannot recreate the folder or order more audio.
    func forget(_ story: Story) {
        narrations.abandon(storyID: story.id)
        if player.storyID == story.id { player.stop() }
        try? cache.removeStory(story.id)
    }
}
