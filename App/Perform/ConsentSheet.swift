import SwiftUI

/// The yes to sending a topic to the AI providers (App Store guideline 5.1.2(i)). It names
/// every provider that receives data and says where the data goes.
struct ConsentSheet: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SpeakingOrb(mode: .breathing, size: 110)
                .frame(maxWidth: .infinity)
            Text("Before the first story")
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundStyle(Theme.cream)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 14) {
                row("text.quote", "Your topic and the style you pick go to Anthropic, which writes the story.")
                row("waveform", "The written story goes to ElevenLabs, which reads it aloud. If ElevenLabs is unavailable, OpenAI reads it instead.")
                row("lock.shield", "Everything passes through Fabrique Accounts, the sign-in service behind Baika. Stories and audio stay on this iPhone.")
                row("exclamationmark.bubble", "Stories are written by AI and can contain mistakes.")
            }
            Spacer(minLength: 0)
            Button("Agree and tell", action: onAgree)
                .buttonStyle(.primary)
            Button("Not now", action: onDecline)
                .font(.headline)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(24)
        .inkBackground()
        .presentationDetents([.large])
    }

    private func row(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.amber)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
