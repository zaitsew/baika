import BaikaKit
import FabriqueAccounts
import Foundation

/// The story script, streamed through the hub's metered `ai` function.
///
/// The hub speaks chat-completions and serves Claude on it. Nothing here holds a key: the
/// kit fetches the signed-in person's access token per call. Only `max_completion_tokens` and
/// `reasoning_effort` are sent besides the messages, never a sampling parameter (the hub drops
/// them) and never `product` (the kit sets it).
public struct HubScriptBackend: ScriptBackend {
    typealias Stream = @Sendable (String, [ChatMessage], [String: JSONValue]) -> AsyncThrowingStream<String, any Error>

    private let streamText: Stream

    /// `AccountsClient.ai` is a value over the client's wire layer, built once in
    /// `AccountsClient.init`; signing in and out changes the token it fetches per call, not the
    /// object, so capturing it is safe.
    @MainActor
    public init(_ accounts: AccountsClient) {
        let ai = accounts.ai
        self.init { model, messages, extra in ai.stream(model: model, messages: messages, extra: extra) }
    }

    init(stream: @escaping Stream) {
        self.streamText = stream
    }

    public func stream(model: String, system: String, user: String, maxOutputTokens: Int) -> AsyncThrowingStream<String, any Error> {
        let source = streamText(model, Self.messages(system: system, user: user), Self.extra(maxOutputTokens: maxOutputTokens))
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await delta in source { continuation.yield(delta) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.translate(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Request shape (internal, tested)

    static func messages(system: String, user: String) -> [ChatMessage] {
        [.system(system), .user(user)]
    }

    /// Thinking counts against the ceiling. A story needs little of it, so the effort is low:
    /// the first words reach the screen sooner.
    static func extra(maxOutputTokens: Int) -> [String: JSONValue] {
        ["max_completion_tokens": .number(Double(maxOutputTokens)), "reasoning_effort": .string("low")]
    }

    // MARK: Errors (internal, tested)

    /// The kit's typed errors become `BackendFailure`. A URLSession failure is read as
    /// "offline"; cancellation passes through untouched.
    static func translate(_ error: any Error) -> any Error {
        if error is CancellationError || error is BackendFailure { return error }
        if let refusal = error as? AccountsError { return failure(for: refusal) }
        if let failure = error as? URLError {
            return failure.code == .cancelled ? CancellationError() : BackendFailure.offline
        }
        return error
    }

    static func failure(for error: AccountsError) -> BackendFailure {
        switch error {
        case .notSignedIn: .signedOut
        case .budgetExhausted: .budgetExhausted
        case .rateLimited: .rateLimited
        case .productUnavailable(let product): .unavailable(status: 403, code: "product_unavailable:\(product)")
        case .misconfigured(let why): .unavailable(status: 0, code: "misconfigured:\(why)")
        case .billingNotConfigured, .keyRejected, .changed, .decoding: .unavailable(status: 0, code: nil)
        case .server(let status, let code, let message):
            switch status {
            case 401: .signedOut
            case 402: .budgetExhausted
            case 413: .tooLarge
            case 429: code == "cap_reached" ? .capReached : .rateLimited
            case 403: code == "cap_unknown" ? .capReached : .rejected(message.isEmpty ? (code ?? "forbidden") : message)
            case 400, 404, 422: .rejected(message.isEmpty ? (code ?? "bad request") : message)
            default: .unavailable(status: status, code: code)
            }
        }
    }
}
