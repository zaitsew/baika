import Foundation

/// Why a hub call failed, in terms the app can act on. The accounts bridge translates the
/// kit's own errors into these, so this module needs no network or kit types.
public enum BackendFailure: Error, Sendable, Equatable {
    /// No session, or the hub rejected it (401).
    case signedOut
    /// The month's AI budget is spent (402).
    case budgetExhausted
    /// More than the hub allows in a minute (429).
    case rateLimited
    /// A per-product cap, for example seconds of speech, is reached (429 `cap_reached`,
    /// 403 `cap_unknown`).
    case capReached
    /// The text sent was too long (413).
    case tooLarge
    /// The request was refused as invalid: an unknown model, a bad voice, a bad field.
    case rejected(String)
    /// The hub or a provider failed (5xx, or another unexpected status).
    case unavailable(status: Int, code: String?)
    /// The device could not reach the hub.
    case offline
    /// The audio came back empty or unreadable.
    case badAudio
}

/// Whether a failed script call should be retried on the cheaper model.
public enum ModelFallback {
    /// Only before any text arrived. A model the hub refuses, a cap or a budget that the
    /// dearer model tripped over: the cheaper model may still fit. If it fails too, that error
    /// is the one shown.
    public static func shouldFallBack(after failure: BackendFailure) -> Bool {
        switch failure {
        case .rejected, .capReached, .budgetExhausted: true
        case .signedOut, .rateLimited, .tooLarge, .unavailable, .offline, .badAudio: false
        }
    }
}
