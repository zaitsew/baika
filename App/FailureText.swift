import BaikaKit
import Foundation

/// What the person reads when a call fails.
enum FailureText {
    static func message(for error: any Error) -> String {
        guard let failure = error as? BackendFailure else {
            if error is EmptyStory { return String(localized: "The story came back empty. Try again.") }
            return String(localized: "Something went wrong. Try again.")
        }
        switch failure {
        case .signedOut: return String(localized: "Your session has ended. Sign in again.")
        case .budgetExhausted: return String(localized: "This month's AI allowance is used up.")
        case .rateLimited: return String(localized: "Too many requests. Try again in a minute.")
        case .capReached: return String(localized: "The narration limit is reached for now. Try again later.")
        case .tooLarge: return String(localized: "That topic is too long. Shorten it.")
        case .rejected: return String(localized: "The service refused the request. Try again.")
        case .unavailable: return String(localized: "The service is unavailable right now. Try again in a moment.")
        case .offline: return String(localized: "No connection. Check the network and try again.")
        case .badAudio: return String(localized: "The voice returned no audio. Try again.")
        }
    }
}

/// The model finished without writing a story.
struct EmptyStory: Error {}
