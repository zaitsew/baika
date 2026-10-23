import FabriqueAccounts
import Foundation

/// Where Baika's accounts live, compiled in.
///
/// No screen asks a person for any of this. The project URL and the publishable (anon) key are
/// public by design: every copy of the app ships them, and the gate is row-level security plus
/// the edge functions, not secrecy. The service role key exists only inside Supabase.
public enum BaikaHub {
    /// The Fabrique Accounts project (the hub is schema `accounts` inside it).
    public static let url = URL(string: "https://swgxlydagofazjtlqeiu.supabase.co")!

    /// Publishable, not secret. The same key Finca, Knut, Lumi and Wine Cave ship.
    public static let anonKey = "sb_publishable_qILoLtZ4ycJ3NIfl1cljYA_fnlG2gne"

    /// This app's row in `accounts.products`, sent as `product` in every body.
    public static let product = "baika"

    /// Where a sign-in link comes back to. The `baika` scheme is registered in `project.yml`.
    public static let redirectURL = URL(string: "baika://auth-callback")!

    /// True for the URL a sign-in flow returns on (`baika://auth-callback…`).
    public static func isAuthCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == redirectURL.scheme && url.host()?.lowercased() == redirectURL.host()
    }

    @MainActor
    public static func makeClient() -> AccountsClient {
        AccountsClient(url: url, anonKey: anonKey, product: product, redirectURL: redirectURL)
    }
}
