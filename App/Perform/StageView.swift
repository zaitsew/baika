import SwiftUI

/// The storyteller on stage: the orb shows what is happening, the script appears as it is
/// written, and the controls play it.
struct StageView: View {
    let model: PerformModel
    let onRetry: () -> Void
    let onClose: () -> Void

    @Environment(AppModel.self) private var app

    private var player: NarrationPlayer { app.player }

    private var orbMode: SpeakingOrb.Mode {
        switch model.phase {
        case .idle: .still
        case .writing: .breathing
        case .narrating, .done, .failed:
            switch player.state {
            case .playing: .speaking
            case .buffering: model.phase == .failed ? .still : .breathing
            case .idle, .paused, .finished: .still
            }
        }
    }

    private var caption: LocalizedStringKey {
        switch model.phase {
        case .idle: ""
        case .writing: "Writing your story…"
        case .failed: "Something stopped"
        case .narrating, .done:
            switch player.state {
            case .playing: "Telling"
            case .buffering: "Preparing the voice…"
            case .paused: "Paused"
            case .finished: "The end"
            case .idle: ""
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            SpeakingOrb(mode: orbMode, size: 150)
                .padding(.top, 4)
            VStack(spacing: 6) {
                Text(model.title.isEmpty ? " " : model.title)
                    .font(.system(.title, design: .serif, weight: .bold))
                    .foregroundStyle(Theme.cream)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                if model.usedBackupVoice {
                    Label("Narrated with the backup voice", systemImage: "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            script
            footer
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.icon(size: 44))
            .accessibilityLabel("Close")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var script: some View {
        ScrollView {
            Text(model.text)
                .font(.system(.body, design: .serif))
                .lineSpacing(6)
                .foregroundStyle(Theme.cream.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .defaultScrollAnchor(model.phase == .writing ? .bottom : .top)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                    .init(color: .black, location: 0.94), .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 14) {
            if model.phase == .failed, let message = model.error {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isStaticText)
                HStack(spacing: 12) {
                    if model.canRetryNarration {
                        Button("Try again", action: onRetry)
                            .buttonStyle(.primary)
                    } else {
                        Button("Back", action: onClose)
                            .buttonStyle(.primary)
                    }
                }
            }
            if player.isActive {
                PlayerControls(player: player)
            } else if model.phase == .writing {
                ProgressView().tint(Theme.amber)
                    .frame(minHeight: 44)
            }
            if model.phase == .done, player.state == .finished || player.state == .paused {
                Button("New story", action: onClose)
                    .font(.headline)
                    .foregroundStyle(Theme.amber)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .padding(.top, 8)
    }
}
