import FabriqueAccounts
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            Form {
                if app.accounts.isSignedIn {
                    AccountSettingsSection(showsOwnKey: false, showsBilling: false)
                } else {
                    Section("Account") {
                        Text("You are not signed in. Sign in on the Perform tab to ask for stories. Your library works without an account.")
                            .font(.callout)
                            .foregroundStyle(Theme.muted)
                    }
                }

                Section {
                    Toggle(
                        "Send topics to AI providers",
                        isOn: Binding(get: { app.consented }, set: { app.setConsent($0) }))
                } header: {
                    Text("AI")
                } footer: {
                    Text("Anthropic writes the story. ElevenLabs reads it aloud, and OpenAI reads it if ElevenLabs is unavailable. Turn this off and Baika asks again before the next story.")
                }

                Section {
                    Toggle(
                        "Send my voice to OpenAI in Talk",
                        isOn: Binding(get: { app.talkConsented }, set: { app.setTalkConsent($0) }))
                } footer: {
                    Text("Talk streams your voice to OpenAI, through Fabrique Accounts, while a conversation is live. Baika does not record it. Turn this off and Baika asks again before the next conversation.")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    Text("Baika is an AI storyteller. Stories are written by AI and can contain mistakes.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .inkBackground()
            .navigationTitle("Settings")
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
