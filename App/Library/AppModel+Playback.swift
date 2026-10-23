import BaikaKit
import Foundation

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
            player.enqueue(index: index, url: cache.url(for: story.id, fileName: name))
        }
    }

    /// Removes a story, its audio, and stops it if it is the one playing.
    func forget(_ story: Story) {
        if player.storyID == story.id { player.stop() }
        try? cache.removeStory(story.id)
    }
}
