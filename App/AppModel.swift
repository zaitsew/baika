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
    let player = NarrationPlayer()
    let cache = AudioCache.standard()
    let narrations = NarrationRegistry()
    let scriptWriter: ScriptWriter
    let narrator: any NarrationBackend

    /// True once the person agreed to the current wording of the AI consent.
    private(set) var consented: Bool
    @ObservationIgnored private let defaults: UserDefaults

    init(accounts: AccountsClient = BaikaHub.makeClient(), defaults: UserDefaults = .standard) {
        self.accounts = accounts
        self.defaults = defaults
        scriptWriter = ScriptWriter(backend: HubScriptBackend(accounts))
        narrator = HubAudioClient(accounts)
        consented = AIConsent.isGiven(in: defaults)
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

    /// Finishes a sign-in link. Returns false for any other URL.
    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard BaikaHub.isAuthCallback(url) else { return false }
        Task { _ = try? await accounts.handleOpenURL(url) }
        return true
    }
}

/// The device language as the style and voice catalogues want it.
enum AppLanguage {
    static var code: String? { Locale.current.language.languageCode?.identifier }
}
