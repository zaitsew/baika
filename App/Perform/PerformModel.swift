import BaikaKit
import Foundation
import Observation
import SwiftData

/// One Perform run: write the script, save the story, narrate chunk by chunk while the
/// player plays what has arrived.
@MainActor
@Observable
final class PerformModel {
    enum Phase: Equatable {
        case idle
        /// The script is streaming in.
        case writing
        /// The script is done; chunks are being narrated and played.
        case narrating
        /// Every chunk is narrated and saved.
        case done
        /// A call failed. The text on screen is still there; `error` says why.
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var title = ""
    /// The script so far, as a person reads it.
    private(set) var text = ""
    private(set) var error: String?
    /// The backup voice spoke at least one chunk.
    private(set) var usedBackupVoice = false

    private struct Run {
        let story: Story
        let chunks: [NarrationChunk]
        let settings: NarrationSettings
    }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var run: Run?

    var isBusy: Bool { phase == .writing || phase == .narrating }
    /// A failed narration can be retried; a failed script cannot (there is nothing to narrate).
    var canRetryNarration: Bool { phase == .failed && run != nil }

    // MARK: Start

    func tell(
        topic: String, style: ResolvedStyle, length: StoryLength, language: StoryLanguage, voice: Voice,
        app: AppModel, context: ModelContext
    ) {
        guard !isBusy else { return }
        resetScreen()
        phase = .writing
        let request = StoryRequest(topic: topic, style: style, length: length, language: language)
        task = Task { [weak self] in
            await self?.write(request, voice: voice, app: app, context: context)
        }
    }

    /// Narrate again from the first missing chunk, after a failure.
    func retryNarration(app: AppModel, context: ModelContext) {
        guard canRetryNarration, let run else { return }
        error = nil
        phase = .narrating
        task = Task { [weak self] in
            await self?.narrate(run, app: app, context: context)
        }
    }

    /// Narrates the chunks a saved story is missing (a narration that failed half way, or audio
    /// that was deleted), then plays it from the start.
    func finishNarration(of story: Story, app: AppModel, context: ModelContext) {
        guard !isBusy else { return }
        resetScreen()
        title = story.title
        text = story.readableScript
        let choice: StyleChoice =
            StyleCatalog.all.first { $0.name.en == story.style || $0.name.ru == story.style }
            .map { StyleChoice.preset($0.id) } ?? .custom(story.style)
        guard let style = choice.resolve(languageCode: AppLanguage.code) else {
            fail(EmptyStory())
            return
        }
        let voice = VoiceCatalog.all.first { $0.name == story.voice } ?? VoiceCatalog.default
        let chunks = NarrationChunker().chunks(for: story.script)
        // Files are named by position; a chunker change would shift them, so the story keeps
        // its own list and only a matching count is narrated again.
        guard chunks.count == story.chunkFileNames.count else {
            fail(EmptyStory())
            return
        }
        let run = Run(
            story: story, chunks: chunks,
            settings: NarrationSettings(voice: voice, style: style, language: story.storyLanguage))
        self.run = run
        phase = .narrating
        task = Task { [weak self] in
            await self?.narrate(run, app: app, context: context)
        }
    }

    /// Stops everything and returns to the form. A story already saved stays in the library.
    func close(app: AppModel) {
        task?.cancel()
        task = nil
        app.player.stop()
        run = nil
        resetScreen()
    }

    /// The story was deleted: stop narrating it and leave the screen.
    func abandon(storyID: UUID) {
        guard run?.story.id == storyID else { return }
        task?.cancel()
        task = nil
        run = nil
        resetScreen()
    }

    private func resetScreen() {
        phase = .idle
        title = ""
        text = ""
        error = nil
        usedBackupVoice = false
    }

    // MARK: Script

    private func write(_ request: StoryRequest, voice: Voice, app: AppModel, context: ModelContext) async {
        do {
            var stream = StoryStream()
            for try await event in app.scriptWriter.write(request) {
                guard case .delta(let delta) = event else { continue }
                stream.append(delta)
                let live = stream.live
                title = live.title
                text = live.readableScript
            }
            let final = stream.final
            guard !final.script.isEmpty else { throw EmptyStory() }
            title = final.title.isEmpty ? Self.fallbackTitle(for: request.topic) : final.title
            text = final.readableScript

            let chunks = NarrationChunker().chunks(for: final.script)
            let story = Story(
                title: title, topic: request.topic, style: request.style.name, language: request.language.rawValue,
                voice: voice.name, script: final.script, chunkFileNames: AudioCache.fileNames(count: chunks.count))
            context.insert(story)
            try? context.save()

            let settings = NarrationSettings(voice: voice, style: request.style, language: request.language)
            let run = Run(story: story, chunks: chunks, settings: settings)
            self.run = run
            phase = .narrating
            await narrate(run, app: app, context: context)
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    static func fallbackTitle(for topic: String) -> String {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(60))
    }

    // MARK: Narration

    private func narrate(_ run: Run, app: AppModel, context: ModelContext) async {
        let story = run.story
        let id = story.id
        let player = app.player
        app.narrations.register(self, storyID: id)
        defer { app.narrations.unregister(self, storyID: id) }
        player.start(
            storyID: id, title: story.title,
            chunkEstimates: run.chunks.map { NarrationPlayer.estimate(characters: $0.text.utf16.count) })
        var settings = run.settings
        settings.preferBackup = settings.preferBackup || usedBackupVoice
        do {
            for chunk in run.chunks {
                try Task.checkCancellation()
                // Another story took the player: stop here, nobody is listening to this one.
                guard player.storyID == id else { return stepAside() }
                let name = AudioCache.fileName(forChunk: chunk.index)
                if !app.cache.exists(storyID: id, fileName: name) {
                    // Chunk n+1 is requested once chunk n-1 has started playing, so there is
                    // always one chunk ahead and a person who pauses does not pay for the rest.
                    while !player.hasStarted(chunk: chunk.index - 1) {
                        try await Task.sleep(for: .milliseconds(250))
                        guard player.storyID == id else { return stepAside() }
                    }
                    try Task.checkCancellation()
                    let audio = try await app.narrator.narrate(chunk, settings: settings)
                    try Task.checkCancellation()
                    try app.cache.write(audio.data, storyID: id, chunkIndex: chunk.index)
                    if audio.usedBackup {
                        usedBackupVoice = true
                        settings.preferBackup = true
                    }
                }
                player.enqueue(storyID: id, index: chunk.index, url: app.cache.url(for: id, fileName: name))
            }
            let urls = run.chunks.map { app.cache.url(for: id, fileName: AudioCache.fileName(forChunk: $0.index)) }
            let total = await AudioTools.totalDuration(of: urls)
            try Task.checkCancellation()
            story.durationSeconds = total
            try? context.save()
            if phase == .narrating { phase = .done }
        } catch is CancellationError {
            return
        } catch {
            // A cancelled request can surface as a URL error: the story is gone, say nothing.
            if Task.isCancelled { return }
            // What arrived keeps playing; the player treats it as the whole story.
            player.endProduction()
            fail(error)
        }
    }

    /// The player now holds another story. What was narrated stays saved; the story's page can
    /// finish the rest.
    private func stepAside() {
        run = nil
        resetScreen()
    }

    private func fail(_ error: any Error) {
        self.error = FailureText.message(for: error)
        phase = .failed
    }
}
