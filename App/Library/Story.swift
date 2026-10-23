import BaikaKit
import Foundation
import SwiftData

/// A story in the library: the script, how it was asked for, and where its audio is.
@Model
final class Story {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var topic: String = ""
    /// The style as it was named when the story was made ("Zhvanetsky", or the free text).
    var style: String = ""
    /// `StoryLanguage.rawValue`.
    var language: String = "ru"
    /// The voice's name ("George").
    var voice: String = ""
    /// The script with its audio tags, as it was narrated.
    var script: String = ""
    /// One file per narration chunk, in `AudioCache`'s folder for this story.
    var chunkFileNames: [String] = []
    var createdAt: Date = Date()
    var durationSeconds: Double = 0

    init(
        id: UUID = UUID(), title: String, topic: String, style: String, language: String, voice: String,
        script: String, chunkFileNames: [String], createdAt: Date = Date(), durationSeconds: Double = 0
    ) {
        self.id = id
        self.title = title
        self.topic = topic
        self.style = style
        self.language = language
        self.voice = voice
        self.script = script
        self.chunkFileNames = chunkFileNames
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
    }

    /// The script as a person reads it: no audio tags.
    var readableScript: String { StorySanitizer.spokenText(script) }

    var storyLanguage: StoryLanguage { StoryLanguage(rawValue: language) ?? .ru }

    /// Estimated seconds per chunk, from the script, for the player before it reads the files.
    func chunkEstimates() -> [TimeInterval] {
        NarrationChunker().chunks(for: script).map { NarrationPlayer.estimate(characters: $0.text.utf16.count) }
    }
}
