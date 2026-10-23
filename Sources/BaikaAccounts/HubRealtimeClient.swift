import BaikaKit
import FabriqueAccounts
import Foundation

/// Mints the client secret for a Talk session: `POST {hub}/functions/v1/ai/realtime`.
///
/// The hub charges for the session up front and answers with OpenAI's `{ value, expires_at,
/// session }`; the phone then opens a WebSocket to OpenAI itself, the hub is not on it. The
/// bearer is the signed-in person's access token, read from the kit's Supabase session at call
/// time and never stored. Redirects are refused, so the token cannot follow one to another host.
public struct HubRealtimeClient: RealtimeBackend {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, Int)
    typealias AccessToken = @Sendable () async throws -> String

    private let functionsURL: URL
    private let anonKey: String
    private let product: String
    private let accessToken: AccessToken
    private let send: Send

    @MainActor
    public init(_ accounts: AccountsClient) {
        let supabase = accounts.supabase
        self.init(
            functionsURL: accounts.configuration.functionsURL,
            anonKey: accounts.configuration.anonKey,
            product: accounts.configuration.product,
            accessToken: {
                do { return try await supabase.auth.session.accessToken } catch { throw BackendFailure.signedOut }
            },
            send: Self.urlSessionSend)
    }

    init(functionsURL: URL, anonKey: String, product: String, accessToken: @escaping AccessToken, send: @escaping Send) {
        self.functionsURL = functionsURL
        self.anonKey = anonKey
        self.product = product
        self.accessToken = accessToken
        self.send = send
    }

    public func mint(_ session: RealtimeSessionRequest) async throws -> RealtimeGrant {
        let token = try await accessToken()
        let request = try request(for: session, token: token)
        let data: Data
        let status: Int
        do {
            (data, status) = try await send(request)
        } catch let failure as BackendFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as URLError {
            if failure.code == .cancelled { throw CancellationError() }
            throw BackendFailure.offline
        }
        guard (200..<300).contains(status) else { throw NarrationFallback.classify(status: status, body: data) }
        return try RealtimeGrant.parse(data)
    }

    // MARK: Request (internal, tested)

    func request(for session: RealtimeSessionRequest, token: String) throws -> URLRequest {
        guard functionsURL.scheme?.lowercased() == "https" else {
            // Nothing is sent over plain http: a downgraded URL never sees a token.
            throw BackendFailure.unavailable(status: 0, code: "insecure_hub_url")
        }
        var request = URLRequest(url: functionsURL.appending(path: "ai/realtime"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(RealtimeMintBody(product: product, request: session))
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static let urlSessionSend: Send = { request in
        let (data, response) = try await URLSession.shared.data(for: request, delegate: RefuseRedirects())
        guard let http = response as? HTTPURLResponse else { throw BackendFailure.unavailable(status: 0, code: "not_http") }
        return (data, http.statusCode)
    }
}
