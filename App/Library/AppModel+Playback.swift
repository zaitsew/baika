import BaikaKit
import Foundation

/// The Perform models that are narrating a story, so deleting the story can stop them.
@MainActor
final class NarrationRegistry {
    private final class Entry {
        weak var model: PerformModel?
        init(_ model: PerformModel) { self.model = model }
    }

    private var entries: [UUID: [Entry]] = [:]

    func register(_ model: PerformModel, storyID: UUID) {
        entries[storyID, default: []].removeAll { $0.model == nil }
        entries[storyID, default: []].append(Entry(model))
    }

    func unregister(_ model: PerformModel, storyID: UUID) {
        entries[storyID]?.removeAll { $0.model == nil || $0.model === model }
        if entries[storyID]?.isEmpty == true { entries[storyID] = nil }
    }

    /// Cancels every narration of the story and returns those screens to idle.
    func abandon(storyID: UUID) {
        let models = (entries.removeValue(forKey: storyID) ?? []).compactMap(\.model)
        for model in models { model.abandon(storyID: storyID) }
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
