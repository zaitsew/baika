import BaikaKit
import SwiftData
import SwiftUI

/// The Perform tab: choose a topic, a style, a length, a language and a voice, then tell.
/// While a story is being written and narrated the form gives way to the stage.
struct PerformView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    @State private var model = PerformModel()
    @State private var topic = ""
    @State private var customStyle = ""
    @State private var showConsent = false
    @FocusState private var focus: Field?

    @AppStorage("baika.styleID") private var styleID = StyleCatalog.defaultID
    @AppStorage("baika.length") private var lengthMinutes = StoryLength.default.rawValue
    @AppStorage("baika.language") private var languageRaw = StoryLanguage.default.rawValue
    @AppStorage("baika.voice") private var voiceID = VoiceCatalog.defaultID

    private enum Field { case topic, style }
    private static let customID = "custom"

    private var language: StoryLanguage { StoryLanguage(rawValue: languageRaw) ?? .default }
    private var length: StoryLength { StoryLength(rawValue: lengthMinutes) ?? .default }
    private var voice: Voice { VoiceCatalog.voice(id: voiceID) ?? VoiceCatalog.default }
    private var choice: StyleChoice {
        styleID == Self.customID ? .custom(customStyle) : .preset(styleID)
    }
    private var resolvedStyle: ResolvedStyle? { choice.resolve(languageCode: AppLanguage.code) }
    private var cleanTopic: String { topic.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canTell: Bool { !cleanTopic.isEmpty && resolvedStyle != nil }

    var body: some View {
        Group {
            if model.phase == .idle {
                form
            } else {
                StageView(
                    model: model,
                    onRetry: { model.retryNarration(app: app, context: context) },
                    onClose: { model.close(app: app) })
            }
        }
        .inkBackground()
        .animation(.easeInOut(duration: 0.25), value: model.phase == .idle)
        // "Perform this" in Talk fills the form: the person reads it, changes it, taps Tell.
        .onAppear(perform: takeDraft)
        .onChange(of: app.performDraft) { _, _ in takeDraft() }
        .sheet(isPresented: $showConsent) {
            ConsentSheet {
                app.setConsent(true)
                showConsent = false
                tell()
            } onDecline: {
                showConsent = false
            }
        }
    }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                topicSection
                styleSection
                lengthSection
                languageSection
                voiceSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: tell) {
                Text("Tell")
            }
            .buttonStyle(.primary)
            .disabled(!canTell)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Baika")
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundStyle(Theme.cream)
            Text("A story for the ear, on any topic.")
                .font(.callout)
                .foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Topic")
            TextField("What should the story be about?", text: $topic, axis: .vertical)
                .lineLimit(3...6)
                .font(.title3)
                .foregroundStyle(Theme.cream)
                .focused($focus, equals: .topic)
                .card()
                .onChange(of: topic) { _, new in
                    if new.count > StoryPrompt.maxTopicLength {
                        topic = String(new.prefix(StoryPrompt.maxTopicLength))
                    }
                }
            Text("Type, or tap the microphone on the keyboard to dictate.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Style")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(StyleCatalog.all) { preset in
                    Button {
                        styleID = preset.id
                    } label: {
                        Chip(
                            title: preset.name.resolved(languageCode: AppLanguage.code),
                            selected: styleID == preset.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    styleID = Self.customID
                    focus = .style
                } label: {
                    Chip(title: String(localized: "Your own style"), selected: styleID == Self.customID)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            if styleID == Self.customID {
                TextField("For example: a noir detective in the rain", text: $customStyle, axis: .vertical)
                    .lineLimit(1...3)
                    .foregroundStyle(Theme.cream)
                    .focused($focus, equals: .style)
                    .card()
                    .onChange(of: customStyle) { _, new in
                        if new.count > StyleCatalog.maxCustomLength {
                            customStyle = String(new.prefix(StyleCatalog.maxCustomLength))
                        }
                    }
            }
        }
    }

    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Length")
            HStack(spacing: 10) {
                ForEach(StoryLength.allCases) { option in
                    Button {
                        lengthMinutes = option.rawValue
                    } label: {
                        Chip(title: String(localized: "\(option.minutes) min"), selected: option == length)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var languageSection: some View {
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

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Voice")
            VStack(spacing: 10) {
                ForEach(VoiceCatalog.all) { option in
                    Button {
                        voiceID = option.id
                    } label: {
                        Chip(
                            title: option.name,
                            subtitle: option.summary.resolved(languageCode: AppLanguage.code),
                            selected: option.id == voice.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Action

    private func takeDraft() {
        guard let draft = app.performDraft else { return }
        app.performDraft = nil
        topic = String(draft.topic.prefix(StoryPrompt.maxTopicLength))
        styleID = draft.styleID
        languageRaw = draft.language.rawValue
    }

    private func tell() {
        guard canTell, let style = resolvedStyle, !model.isBusy else { return }
        focus = nil
        guard app.consented else {
            showConsent = true
            return
        }
        model.tell(
            topic: cleanTopic, style: style, length: length, language: language, voice: voice,
            app: app, context: context)
    }
}
