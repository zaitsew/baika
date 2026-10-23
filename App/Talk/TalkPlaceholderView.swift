import SwiftUI

/// Talk is a live voice conversation with the storyteller. It arrives in a later version;
/// this tab holds its place.
struct TalkPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            SpeakingOrb(mode: .breathing, size: 160)
            Text("Talk is coming")
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundStyle(Theme.cream)
            Text("Soon you will be able to speak with the storyteller out loud, and steer the story as it goes.")
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkBackground()
    }
}
