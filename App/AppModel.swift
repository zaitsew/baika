import BaikaAccounts
import BaikaKit
import FabriqueAccounts
import Foundation
import Observation

/// What the screens share: who is signed in, the hub backends, the player, the audio folder
/// and the AI consent.
@MainActor
@Observable
final class AppModel {
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
    @ObservationIgnored private let defaults: UserDefaults

    init(accounts: AccountsClient = BaikaHub.makeClient(), defaults: UserDefaults = .standard) {
        self.accounts = accounts
        self.defaults = defaults
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

/// The device language as the style and voice catalogues want it.
enum AppLanguage {
    static var code: String? { Locale.current.language.languageCode?.identifier }
}
