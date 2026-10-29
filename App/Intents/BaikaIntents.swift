import AppIntents
import BaikaKit

// Baika's App Intents: what Siri, Shortcuts and Spotlight can ask of the app. Each one opens the
// app (the stage, the player and the AI consent live there) and hands the work to `AppModel`.
// There is no directory listing for them: audio generation is not accepted by the AI
// directories, so these are the AI integration (docs/INTENTS.md).

struct TellStoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Tell a story"
    static let description = IntentDescription(
        "Write a story on a topic in a style, narrate it aloud and open the player.",
        categoryName: "Stories")
    static let supportedModes: IntentModes = .foreground

    @Parameter(
        title: "Topic", description: "What the story is about.",
        requestValueDialog: IntentDialog("What should the story be about?"))
    var topic: String

    @Parameter(
        title: "Style", description: "A writer or a manner, for example Dovlatov or a noir detective. Empty keeps your last choice.")
    var style: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Tell a story about \(\.$topic) in the style of \(\.$style)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clean = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw $topic.needsValueError(IntentDialog("What should the story be about?"))
        }
        AppModel.shared.requestStory(topic: clean, style: style)
        return .result(dialog: IntentDialog("Telling a story about \(clean)."))
    }
}

struct ReplayLastStoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Replay my last story"
    static let description = IntentDescription(
        "Play your newest story again from the start. It plays offline.",
        categoryName: "Stories")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch AppModel.shared.replayLatest() {
        case .noStories:
            return .result(dialog: IntentDialog("You have no stories yet. Ask for one first."))
        case .playing(let title):
            return .result(dialog: IntentDialog("Playing \(title)."))
        case .needsAudio(let title):
            return .result(dialog: IntentDialog("Part of the audio for \(title) is not downloaded yet. I opened it."))
        case .narrating(let title):
            return .result(dialog: IntentDialog("\(title) is still being narrated. I opened it."))
        }
    }
}

struct ContinueStoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue the story"
    static let description = IntentDescription(
        "Play on a story you paused, or write and narrate the next part of your latest story.",
        categoryName: "Stories")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch AppModel.shared.continueLatest() {
        case .noStories:
            return .result(dialog: IntentDialog("You have no stories yet. Ask for one first."))
        case .resumed(let title):
            return .result(dialog: IntentDialog("Continuing \(title)."))
        case .writing(let title):
            return .result(dialog: IntentDialog("Writing the next part of \(title)."))
        }
    }
}

/// The phrases Siri and Spotlight know. A phrase can only hold the app name, not free text, so
/// Siri asks "What should the story be about?" once the shortcut starts.
struct BaikaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TellStoryIntent(),
            phrases: [
                "Tell me a story with \(.applicationName)",
                "Tell a story in \(.applicationName)",
                "Ask \(.applicationName) for a story",
            ],
            shortTitle: "Tell a story", systemImageName: "theatermasks")
        AppShortcut(
            intent: ReplayLastStoryIntent(),
            phrases: [
                "Replay my last story in \(.applicationName)",
                "Play my last \(.applicationName) story again",
            ],
            shortTitle: "Replay my last story", systemImageName: "gobackward")
        AppShortcut(
            intent: ContinueStoryIntent(),
            phrases: [
                "Continue the story in \(.applicationName)",
                "Continue my story with \(.applicationName)",
            ],
            shortTitle: "Continue the story", systemImageName: "forward.fill")
    }
}
