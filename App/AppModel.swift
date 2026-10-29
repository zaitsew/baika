import BaikaAccounts
import BaikaKit
import FabriqueAccounts
import Foundation
import Observation
import SwiftData

/// What the screens share: who is signed in, the hub backends, the player, the audio folder
/// and the AI consent.
@MainActor
@Observable
final class AppModel {
    /// The one model of the process. The scene and the App Intents share it: an intent that
    /// launches the app cold finds the same player, library and pending request the screens do.
    static let shared = AppModel()

    let container: ModelContainer
    let accounts: AccountsClient
    let player: NarrationPlayer
    let cache = AudioCache.standard()
    let narrations = NarrationRegistry()
    let scriptWriter: ScriptWriter
    let narrator: any NarrationBackend
    let talk: TalkSession

    /// True once the person agreed to the current wording of the AI consent.
    private(set) var consented: Bool
    /// True once the person agreed to sending their voice to OpenAI for Talk.
    private(set) var talkConsented: Bool

    /// What "Perform this" in Talk hands to the Perform tab. Perform takes it once.
    var performDraft: PerformDraft?
    /// A screen asks for another tab; the tab bar follows and clears it.
    var requestedTab: RootTab?
    /// A story an App Intent asked for. Perform takes it once, when it is on screen and the
    /// person is signed in; until then it waits.
    var pendingStory: PendingStory?
    /// The library opens this story's page (an App Intent replayed or continued it).
    var requestedStoryID: UUID?
    @ObservationIgnored private let defaults: UserDefaults

    init(accounts: AccountsClient = BaikaHub.makeClient(), defaults: UserDefaults = .standard) {
        self.accounts = accounts
        self.defaults = defaults
        // The same store the scene shows. Without it the app has nothing to show.
        container = try! ModelContainer(for: Story.self)
        let player = NarrationPlayer()
        self.player = player
        scriptWriter = ScriptWriter(backend: HubScriptBackend(accounts))
        narrator = HubAudioClient(accounts)
        // Talk takes the audio session: a story that is playing stops when the person taps Talk.
        talk = TalkSession(backend: HubRealtimeClient(accounts), beforeStart: { player.stop() })
        consented = AIConsent.isGiven(in: defaults)
        talkConsented = AIConsent.isTalkGiven(in: defaults)
    }

    /// Signed in to Fabrique Accounts. A debug build started with `BAIKA_UI_PREVIEW=1` shows
    /// the signed-in screens without a session, for screenshots; nothing it starts can reach the
    /// hub. Release builds compile the switch out.
    var isSignedIn: Bool { accounts.isSignedIn || Self.uiPreview }

    static var uiPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["BAIKA_UI_PREVIEW"] == "1"
        #else
        false
        #endif
    }

    func setConsent(_ given: Bool) {
        AIConsent.set(given, in: defaults)
        consented = AIConsent.isGiven(in: defaults)
    }

    func setTalkConsent(_ given: Bool) {
        AIConsent.setTalk(given, in: defaults)
        talkConsented = AIConsent.isTalkGiven(in: defaults)
    }

    /// Opens Perform with a topic and a style filled in, from a Talk conversation.
    func perform(_ draft: PerformDraft) {
        performDraft = draft
        requestedTab = .perform
    }

    /// Finishes a sign-in link. Returns false for any other URL.
    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard BaikaHub.isAuthCallback(url) else { return false }
        Task { _ = try? await accounts.handleOpenURL(url) }
        return true
    }
}

/// A story to prepare in Perform: the topic and the style of a Talk conversation.
struct PerformDraft: Equatable {
    var topic: String
    var styleID: String
    var language: StoryLanguage
}

/// A story to start without the form: what an App Intent asks for. Anything left nil comes from
/// the person's saved choices on the Perform tab.
struct PendingStory: Equatable {
    var topic: String
    var style: StyleChoice?
    var language: StoryLanguage?
    var voice: Voice?
    /// The earlier story this one carries on.
    var continuing: StoryContinuation?
    var askedAt = Date()

    /// A request nobody picked up (the person never signed in) must not start a story days later.
    static let lifetime: TimeInterval = 10 * 60
    func isFresh(at now: Date = Date()) -> Bool { now.timeIntervalSince(askedAt) < Self.lifetime }
}

/// The device language as the style and voice catalogues want it.
enum AppLanguage {
    static var code: String? { Locale.current.language.languageCode?.identifier }
}
