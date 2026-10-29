import BaikaKit
import Foundation
import SwiftData

/// What the App Intents (Siri, Shortcuts, Spotlight) ask the app to do. Each intent opens the
/// app and calls one of these; the screens do the rest.
extension AppModel {
    enum ReplayOutcome: Equatable {
        case noStories
        /// Playing from the first second.
        case playing(title: String)
        /// The story is there but some of its audio is not on this device; its page is open.
        case needsAudio(title: String)
        /// A narration of the story is still running; its page is open.
        case narrating(title: String)
    }

    enum ContinueOutcome: Equatable {
        case noStories
        /// A paused story plays on from where it stopped.
        case resumed(title: String)
        /// The next part is being written; Perform is open.
        case writing(title: String)
    }

    /// The newest story in the library.
    func latestStory() -> Story? {
        var newest = FetchDescriptor<Story>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        newest.fetchLimit = 1
        return try? container.mainContext.fetch(newest).first
    }

    /// Asks Perform to write and narrate a story. The person's consent and sign-in still apply:
    /// Perform shows the AI consent first, and the sign-in screen holds the request until then.
    func requestStory(topic: String, style: String?) {
        let clean = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        pendingStory = PendingStory(topic: clean, style: StyleCatalog.choice(forSpoken: style))
        requestedTab = .perform
    }

    /// Plays the newest story from the start, from the files on the device.
    func replayLatest() -> ReplayOutcome {
        guard let story = latestStory() else { return .noStories }
        requestedStoryID = story.id
        requestedTab = .library
        if narrations.isNarrating(storyID: story.id) { return .narrating(title: story.title) }
        guard audioIsComplete(story) else { return .needsAudio(title: story.title) }
        playStored(story)
        return .playing(title: story.title)
    }

    /// A paused story plays on. Otherwise the newest story gets a next part, in its own style,
    /// language and voice.
    func continueLatest() -> ContinueOutcome {
        if player.state == .paused, let id = player.storyID {
            player.resume()
            requestedStoryID = id
            requestedTab = .library
            return .resumed(title: player.title)
        }
        guard let story = latestStory() else { return .noStories }
        let style = StyleCatalog.all.first { $0.name.en == story.style || $0.name.ru == story.style }
            .map { StyleChoice.preset($0.id) } ?? .custom(story.style)
        pendingStory = PendingStory(
            topic: story.topic, style: style, language: story.storyLanguage,
            voice: VoiceCatalog.all.first { $0.name == story.voice },
            continuing: StoryContinuation(title: story.title, readableScript: story.readableScript))
        requestedTab = .perform
        return .writing(title: story.title)
    }
}
