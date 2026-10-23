import Foundation

/// The JSON for `POST {hub}/functions/v1/ai/narrate` (ElevenLabs).
public struct NarrateRequestBody: Encodable, Sendable, Equatable {
    public let product: String
    public let input: String
    public let voiceID: String?
    public let model: String?
    public let languageCode: String?
    public let previousText: String?
    public let nextText: String?

    public static let defaultModel = "eleven_v3"
    /// The hub's limit on `input`.
    public static let maxInputLength = 3000

    public init(
        product: String, input: String, voiceID: String?, languageCode: String?,
        previousText: String?, nextText: String?, model: String? = NarrateRequestBody.defaultModel
    ) {
        self.product = product
        self.input = input
        self.voiceID = voiceID
        self.model = model
        self.languageCode = languageCode
        self.previousText = previousText
        self.nextText = nextText
    }

    private enum CodingKeys: String, CodingKey {
        case product, input, model
        case voiceID = "voice_id"
        case languageCode = "language_code"
        case previousText = "previous_text"
        case nextText = "next_text"
    }
}

/// The JSON for `POST {hub}/functions/v1/ai/tts` (OpenAI), the backup voice.
public struct TTSRequestBody: Encodable, Sendable, Equatable {
    public let product: String
    public let input: String
    public let voice: String
    public let instructions: String?
    public let format: String

    public static let defaultVoice = "marin"
    /// The hub refuses more than this many characters in `input`.
    public static let maxInputLength = 4096

    public init(product: String, input: String, instructions: String?, voice: String = TTSRequestBody.defaultVoice, format: String = "mp3") {
        self.product = product
        self.input = input
        self.voice = voice
        self.instructions = instructions
        self.format = format
    }
}

/// What the narration endpoint answered.
public struct NarrationAudio: Sendable, Equatable {
    public let data: Data
    /// True when the backup voice (OpenAI) spoke instead of ElevenLabs.
    public let usedBackup: Bool

    public init(data: Data, usedBackup: Bool) {
        self.data = data
        self.usedBackup = usedBackup
    }
}

/// What a chunk request needs besides the chunk.
public struct NarrationSettings: Sendable, Hashable {
    public let voice: Voice
    public let style: ResolvedStyle
    public let language: StoryLanguage
    /// True once the backup voice answered earlier in this story: do not ask ElevenLabs again.
    public var preferBackup: Bool

    public init(voice: Voice, style: ResolvedStyle, language: StoryLanguage, preferBackup: Bool = false) {
        self.voice = voice
        self.style = style
        self.language = language
        self.preferBackup = preferBackup
    }
}

/// Turns a chunk of script into mp3 bytes.
public protocol NarrationBackend: Sendable {
    func narrate(_ chunk: NarrationChunk, settings: NarrationSettings) async throws -> NarrationAudio
}

/// Reads a failed hub response.
public enum NarrationFallback {
    public enum Decision: Equatable, Sendable {
        /// ElevenLabs is not configured on the hub (503 `provider_unconfigured`): ask `/ai/tts`.
        case useBackup
        /// Show this to the person. Never retried on another voice.
        case surface(BackendFailure)
    }

    /// Only one answer moves to the backup voice: HTTP 503 with `{"error":"provider_unconfigured"}`.
    /// Every other failure is shown, including other 503s: a provider that is configured but
    /// down is an outage, not a missing key, and a silent switch of voice would hide it.
    public static func decide(status: Int, body: Data) -> Decision {
        if status == 503, errorCode(in: body) == "provider_unconfigured" { return .useBackup }
        return .surface(classify(status: status, body: body))
    }

    /// The failure for a non-success status, shared by `/ai/narrate` and `/ai/tts`.
    public static func classify(status: Int, body: Data) -> BackendFailure {
        let code = errorCode(in: body)
        switch status {
        case 401: return .signedOut
        case 402: return .budgetExhausted
        case 413: return .tooLarge
        case 429: return code == "cap_reached" ? .capReached : .rateLimited
        case 403: return code == "cap_unknown" ? .capReached : .rejected(message(in: body) ?? code ?? "forbidden")
        case 400, 404, 422: return .rejected(message(in: body) ?? code ?? "bad request")
        default: return .unavailable(status: status, code: code)
        }
    }

    static func errorCode(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        if let code = object["error"] as? String { return code }
        if let nested = object["error"] as? [String: Any] { return (nested["code"] ?? nested["type"]) as? String }
        return nil
    }

    static func message(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        if let text = object["message"] as? String { return text }
        if let nested = object["error"] as? [String: Any] { return nested["message"] as? String }
        return nil
    }
}
