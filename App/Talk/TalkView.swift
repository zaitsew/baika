import BaikaKit
import SwiftUI

/// Talk: a live voice conversation with the storyteller.
///
/// Two layouts. The start screen picks a style and a language and has one big button. The live
/// screen is a big orb, one line of caption and three icon buttons: mute, end, and "Perform
/// this". Nothing else. (Ivan on Loco's voice screen: no mute button, a text "End" instead of an
/// icon, no big pulsing button showing that it is listening.)
struct TalkView: View {
    @Environment(AppModel.self) private var app

    @AppStorage("baika.talk.styleID") private var styleID = StyleCatalog.defaultID
    @AppStorage("baika.language") private var languageRaw = StoryLanguage.default.rawValue
    @State private var showConsent = false
    /// The consent sheet was opened by Continue, so agreeing continues the conversation.
    @State private var consentForContinue = false

    private var session: TalkSession { app.talk }
    private var language: StoryLanguage { StoryLanguage(rawValue: languageRaw) ?? .default }
    private var style: ResolvedStyle {
        StyleChoice.preset(styleID).resolve(languageCode: AppLanguage.code)
            ?? StyleChoice.default.resolve(languageCode: AppLanguage.code)!
    }

    /// The live layout stays up after a time-out or a dropped line, to offer Continue.
    private var showsLive: Bool {
        if session.isActive { return true }
        if case .ended(let ending) = session.phase { return ending.offersContinue }
        return false
    }

    var body: some View {
        Group {
            if showsLive {
                live
            } else {
                start
            }
        }
        .inkBackground()
        .animation(.easeInOut(duration: 0.25), value: showsLive)
        .sensoryFeedback(.impact, trigger: session.isMuted)
        .sheet(isPresented: $showConsent) {
            TalkConsentSheet {
                app.setTalkConsent(true)
                showConsent = false
                if consentForContinue {
                    consentForContinue = false
                    Task { await session.continueConversation() }
                } else {
                    begin()
                }
            } onDecline: {
                showConsent = false
                consentForContinue = false
            }
        }
    }

    // MARK: Start

    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Talk")
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.cream)
                    Text("Ask for a story. Interrupt it. Steer it.")
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .combine)

                SpeakingOrb(mode: .breathing, size: 170)
                    .frame(maxWidth: .infinity)

                if let problem = startProblem { problem }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Style")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(StyleCatalog.all) { preset in
                            Button {
                                styleID = preset.id
                            } label: {
                                Chip(title: preset.name.resolved(languageCode: AppLanguage.code), selected: styleID == preset.id)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Language")
                    HStack(spacing: 10) {
                        ForEach(StoryLanguage.allCases) { option in
                            Button {
                                languageRaw = option.rawValue
                            } label: {
                                Chip(title: option.nativeName, selected: option == language)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: begin) {
                Label("Talk", systemImage: "mic.fill")
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    /// Why the last attempt stopped, in one line. Nothing when it did not.
    private var startProblem: AnyView? {
        guard case .ended(let ending) = session.phase else { return nil }
        switch ending {
        case .micDenied:
            // One line, and the way out of it.
            let url = URL(string: UIApplication.openSettingsURLString)!
            return AnyView(
                Link(destination: url) {
                    Text("Microphone access is off. Open Settings.")
                        .font(.callout)
                        .foregroundStyle(Theme.amber)
                        .underline()
                })
        case .fault(let fault):
            return AnyView(Text(faultText(fault)).font(.callout).foregroundStyle(Theme.danger))
        case .reader, .timeUp, .dropped:
            return nil
        }
    }

    private func faultText(_ fault: TalkFault) -> String {
        switch fault {
        case .hub(let failure): FailureText.message(for: failure)
        case .connection: String(localized: "Could not connect. Try again.")
        case .audio: String(localized: "The microphone or speaker could not start.")
        }
    }

    private func begin() {
        guard !session.isActive else { return }
        guard app.talkConsented else {
            showConsent = true
            return
        }
        let style = style
        let language = language
        Task { await session.start(style: style, language: language) }
    }

    // MARK: Live

    private var live: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            SpeakingOrb(mode: orbMode, size: 280, level: orbLevel)
            caption
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .top)
            Spacer(minLength: 16)
            footer
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
        }
    }

    private var orbMode: SpeakingOrb.Mode {
        switch session.phase {
        case .idle, .ended: .still
        case .asking, .connecting: .breathing
        case .answering: .speaking
        case .listening: session.isMuted ? .muted : .listening
        }
    }

    private var orbLevel: Double {
        switch session.phase {
        case .listening: session.isMuted ? 0 : session.level
        case .answering: session.outLevel
        default: 0
        }
    }

    @ViewBuilder
    private var caption: some View {
        if case .ended(let ending) = session.phase {
            Text(endText(ending))
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        } else if session.phase == .asking || session.phase == .connecting {
            Text("Connecting…")
                .font(.callout)
                .foregroundStyle(Theme.muted)
        } else if !session.transcript.caption.isEmpty {
            Text(session.transcript.caption)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Theme.cream)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .animation(.easeOut(duration: 0.2), value: session.transcript.caption)
        } else if session.isLive && !session.transcript.hasPersonSpeech {
            Text("Say something…")
                .font(.callout)
                .foregroundStyle(Theme.muted)
        }
    }

    private func endText(_ ending: TalkEnding) -> String {
        switch ending {
        case .timeUp: String(localized: "The ten minutes are up.")
        default: String(localized: "The conversation was interrupted.")
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 20) {
            if session.isEnded {
                Button(action: resume) {
                    Text("Continue")
                }
                .buttonStyle(.primary)
            }
            HStack(spacing: 28) {
                if !session.isEnded {
                    Button {
                        session.toggleMute()
                    } label: {
                        Image(systemName: session.isMuted ? "mic.slash.fill" : "mic.fill")
                    }
                    .buttonStyle(.icon(size: 72, filled: session.isMuted))
                    .accessibilityLabel(LocalizedStringKey(session.isMuted ? "Unmute" : "Mute"))
                }
                Button {
                    if session.isEnded { session.dismissEnded() } else { session.end() }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.icon(size: 72))
                .accessibilityLabel(LocalizedStringKey(session.isEnded ? "Close" : "End"))

                Button(action: performThis) {
                    Image(systemName: "theatermasks")
                }
                .buttonStyle(.icon(size: 72))
                .disabled(performTopic == nil)
                .opacity(performTopic == nil ? 0.4 : 1)
                .accessibilityLabel("Perform this")
            }
        }
    }

    /// Continue is a new session, so it needs the consent like a first one: it may have been
    /// withdrawn in Settings since.
    private func resume() {
        guard app.talkConsented else {
            consentForContinue = true
            showConsent = true
            return
        }
        Task { await session.continueConversation() }
    }

    private var performTopic: String? { TalkTopic.derive(from: session.transcript.lines) }

    /// Takes the conversation's topic and the style to the Perform tab.
    private func performThis() {
        guard let topic = performTopic else { return }
        let draft = PerformDraft(topic: topic, styleID: styleID, language: language)
        session.end()
        app.perform(draft)
    }
}

/// The yes to sending the person's voice to OpenAI (App Store guideline 5.1.2(i)). It says where
/// the voice goes and what Baika keeps.
struct TalkConsentSheet: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SpeakingOrb(mode: .breathing, size: 110)
                .frame(maxWidth: .infinity)
            Text("Before you talk")
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundStyle(Theme.cream)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 14) {
                row("mic", "Your voice is sent live to OpenAI, which answers in a spoken voice.")
                row("lock.shield", "It passes through Fabrique Accounts, the sign-in service behind Baika. Baika does not record the conversation.")
                row("exclamationmark.bubble", "The storyteller is an AI and can make mistakes.")
            }
            Spacer(minLength: 0)
            Button("Agree and talk", action: onAgree)
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
