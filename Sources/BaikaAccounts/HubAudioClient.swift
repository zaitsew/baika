import BaikaKit
import FabriqueAccounts
import Foundation

/// Narration through the hub: `POST {hub}/functions/v1/ai/narrate` (ElevenLabs), and when the
/// hub says ElevenLabs is not configured, `POST {hub}/functions/v1/ai/tts` (OpenAI).
///
/// The kit's own request helper is private, so this makes the two calls itself. The bearer is
/// the signed-in person's access token, read from the kit's Supabase session
/// (`accounts.supabase.auth.session`, which refreshes an expired token) at call time and never
/// stored. Redirects are refused, so the token cannot follow a redirect to another host.
public struct HubAudioClient: NarrationBackend {
    /// One HTTP exchange: the request, and the status and body of the answer.
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

    public func narrate(_ chunk: NarrationChunk, settings: NarrationSettings) async throws -> NarrationAudio {
        if !settings.preferBackup {
            let body = NarrateRequestBody(
                product: product, input: chunk.text, voiceID: settings.voice.voiceID,
                languageCode: settings.language.code, previousText: chunk.previousText, nextText: chunk.nextText)
            let (data, status) = try await post(path: "ai/narrate", body: body)
            if (200..<300).contains(status) { return try audio(data, usedBackup: false) }
            switch NarrationFallback.decide(status: status, body: data) {
            case .useBackup: break
            case .surface(let failure): throw failure
            }
        }
        // The backup voice would read an audio tag aloud, so the tags go.
        let body = TTSRequestBody(
            product: product,
            input: String(StorySanitizer.spokenText(chunk.text).prefix(TTSRequestBody.maxInputLength)),
            instructions: String(settings.style.deliveryNote.prefix(StyleCatalog.maxDeliveryNoteLength)))
        let (data, status) = try await post(path: "ai/tts", body: body)
        guard (200..<300).contains(status) else { throw NarrationFallback.classify(status: status, body: data) }
        return try audio(data, usedBackup: true)
    }

    // MARK: Request (internal, tested)

    func request(path: String, body: some Encodable, token: String) throws -> URLRequest {
        guard functionsURL.scheme?.lowercased() == "https" else {
            // Nothing is sent over plain http: a downgraded URL never sees a token.
            throw BackendFailure.unavailable(status: 0, code: "insecure_hub_url")
        }
        var request = URLRequest(url: functionsURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // ElevenLabs v3 takes a while on 2,500 characters.
        request.timeoutInterval = 180
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        return request
    }

    private func post(path: String, body: some Encodable) async throws -> (Data, Int) {
        let token = try await accessToken()
        let request = try request(path: path, body: body, token: token)
        do {
            return try await send(request)
        } catch let failure as BackendFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as URLError {
            if failure.code == .cancelled { throw CancellationError() }
            throw BackendFailure.offline
        }
    }

    private func audio(_ data: Data, usedBackup: Bool) throws -> NarrationAudio {
        // A real mp3 is far above a kilobyte; a JSON error body on a 200 is not audio.
        guard data.count > 1024, data.first != UInt8(ascii: "{") else { throw BackendFailure.badAudio }
        return NarrationAudio(data: data, usedBackup: usedBackup)
    }

    // MARK: Transport

    private static let urlSessionSend: Send = { request in
        let (data, response) = try await URLSession.shared.data(for: request, delegate: RefuseRedirects())
        guard let http = response as? HTTPURLResponse else { throw BackendFailure.unavailable(status: 0, code: "not_http") }
        return (data, http.statusCode)
    }
}

/// A redirect would carry the bearer token to another host. The hub never redirects.
private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
