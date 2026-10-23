import SwiftData
import SwiftUI

/// One stored story: play it offline, read it, share it, delete it.
struct StoryDetailView: View {
    let story: Story

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var finisher = PerformModel()
    @State private var confirmDelete = false
    @State private var sharedAudio: SharedFile?
    @State private var preparingAudio = false
    @State private var notice: String?

    private var player: NarrationPlayer { app.player }
    private var isCurrent: Bool { player.storyID == story.id }
    private var complete: Bool { app.audioIsComplete(story) }
    private var narrating: Bool { app.narrations.isNarrating(storyID: story.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(story.title)
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .foregroundStyle(Theme.cream)
                    Text(verbatim: "\(story.style) · \(story.voice) · \(story.storyLanguage.nativeName)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                player_

                if let message = finisher.error ?? notice {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Theme.danger)
                }

                Text(story.readableScript)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.cream.opacity(0.92))
                    .textSelection(.enabled)
            }
            .padding(20)
        }
        .inkBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { shareMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
            }
        }
        .confirmationDialog("Delete this story and its audio?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                app.forget(story)
                context.delete(story)
                try? context.save()
                dismiss()
            }
        }
        .sheet(item: $sharedAudio) { file in
            ShareSheet(items: [file.url])
        }
    }

    // MARK: Player

    @ViewBuilder
    private var player_: some View {
        if isCurrent {
            VStack(spacing: 16) {
                SpeakingOrb(mode: player.state == .playing ? .speaking : (player.state == .buffering ? .breathing : .still), size: 120)
                PlayerControls(player: player)
            }
            .card(padding: 20)
        }
        // Missing chunks can be narrated whether or not this story is the one loaded.
        if !isCurrent || !complete {
            Button(action: play) {
                Label(complete ? LocalizedStringKey("Play") : LocalizedStringKey("Finish the narration"), systemImage: complete ? "play.fill" : "waveform")
            }
            .buttonStyle(.primary)
            // Perform, or this page, is already narrating the story: a second run would pay for
            // the same chunks twice.
            .disabled(finisher.isBusy || narrating)
            if !complete {
                Text(narrating ? LocalizedStringKey("Narrating now.") : LocalizedStringKey("Part of the audio is not on this device."))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func play() {
        notice = nil
        if complete {
            app.playStored(story)
        } else if !app.isSignedIn {
            notice = String(localized: "Sign in to narrate the rest of this story.")
        } else if !app.consented {
            notice = String(localized: "Tell a story from the Perform tab once to agree to the AI terms.")
        } else {
            finisher.finishNarration(of: story, app: app, context: context)
        }
    }

    // MARK: Share

    private var shareText: String { "\(story.title)\n\n\(story.readableScript)" }

    private var shareMenu: some View {
        Menu {
            ShareLink(item: shareText, subject: Text(story.title)) {
                Label("Share text", systemImage: "text.quote")
            }
            if complete {
                Button {
                    shareAudio()
                } label: {
                    Label("Share audio", systemImage: "waveform")
                }
            }
        } label: {
            Image(systemName: preparingAudio ? "hourglass" : "square.and.arrow.up")
        }
        .accessibilityLabel("Share")
        .disabled(preparingAudio)
    }

    private func shareAudio() {
        preparingAudio = true
        notice = nil
        let urls = story.chunkFileNames.map { app.cache.url(for: story.id, fileName: $0) }
        let name = story.title
        Task {
            defer { preparingAudio = false }
            do {
                let merged = try await AudioTools.mergeToM4A(urls, name: name)
                sharedAudio = SharedFile(url: merged)
            } catch {
                notice = String(localized: "The audio could not be prepared for sharing.")
            }
        }
    }
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
