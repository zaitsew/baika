import Foundation

/// Limits of a Talk session, in one place.
public enum TalkLimits {
    /// Where the phone connects with the secret; `?model=` is what the API asks for.
    public static let socketURL = "wss://api.openai.com/v1/realtime"
    public static let model = "gpt-realtime-2.1"
    /// Both ways, 24 kHz mono PCM16: the only rate `audio/pcm` supports.
    public static let sampleRate = 24_000
    /// How long one session runs before Continue is offered. The hub reserves for exactly this.
    public static let defaultMinutes = 10
    /// The hub refuses more than this.
    public static let maxMinutes = 30
    /// Frames of this length are what the server's turn detection likes without chattering.
    public static let frameMilliseconds = 100
    /// How often a quiet socket is pinged, so a pause is not read as a dead connection.
    public static let pingSeconds = 10
    /// How long the socket may take to answer `session.created` before the attempt is dropped.
    public static let handshakeSeconds = 15
}

/// What the hub is asked for: a ten-minute session with these instructions.
public struct RealtimeSessionRequest: Sendable, Equatable {
    public var minutes: Int
    public var instructions: String
    public var voice: String

    public init(minutes: Int = TalkLimits.defaultMinutes, instructions: String, voice: String = TalkPersona.voice) {
        self.minutes = min(max(minutes, 1), TalkLimits.maxMinutes)
        self.instructions = instructions
        self.voice = voice
    }
}

/// The JSON for `POST {hub}/functions/v1/ai/realtime`. The `session` is forwarded to OpenAI's
/// `client_secrets` as given. Server VAD with `interrupt_response`: the model stops when the
/// person starts talking, which is the whole difference between a conversation and a recording.
/// Settings ported from Loco's `voiceSession`.
public struct RealtimeMintBody: Encodable, Sendable, Equatable {
    public let product: String
    public let minutes: Int
    public let session: Session

    public init(product: String, request: RealtimeSessionRequest) {
        self.product = product
        self.minutes = request.minutes
        self.session = Session(instructions: request.instructions, voice: request.voice)
    }

    public struct Session: Encodable, Sendable, Equatable {
        public let type = "realtime"
        public let model = TalkLimits.model
        public let instructions: String
        public let outputModalities = ["audio"]
        public let audio: Audio
        /// The hub lowers this to its own ceiling (2,048); a long answer is a story of about a
        /// minute and a half, which fits.
        public let maxOutputTokens = 2048
        /// GPT-Realtime-2.x reasons before it speaks, and the thinking is latency the person hears
        /// as silence. A conversation needs little of it.
        public let reasoning = Reasoning(effort: "low")

        init(instructions: String, voice: String) {
            self.instructions = instructions
            self.audio = Audio(output: .init(voice: voice))
        }

        enum CodingKeys: String, CodingKey {
            case type, model, instructions, audio, reasoning
            case outputModalities = "output_modalities"
            case maxOutputTokens = "max_output_tokens"
        }
    }

    public struct Reasoning: Encodable, Sendable, Equatable { public let effort: String }

    public struct Audio: Encodable, Sendable, Equatable {
        public let input = Input()
        public let output: Output
    }

    public struct Format: Encodable, Sendable, Equatable {
        public let type = "audio/pcm"
        public let rate = TalkLimits.sampleRate
    }

    public struct Input: Encodable, Sendable, Equatable {
        public let format = Format()
        public let noiseReduction = NoiseReduction()
        public let transcription = Transcription()
        public let turnDetection = TurnDetection()

        enum CodingKeys: String, CodingKey {
            case format, transcription
            case noiseReduction = "noise_reduction"
            case turnDetection = "turn_detection"
        }
    }

    public struct NoiseReduction: Encodable, Sendable, Equatable { public let type = "near_field" }
    /// Guidance for the caption and for Perform's topic, not what the model itself heard.
    public struct Transcription: Encodable, Sendable, Equatable { public let model = "gpt-transcribe" }

    public struct TurnDetection: Encodable, Sendable, Equatable {
        public let type = "server_vad"
        public let createResponse = true
        public let interruptResponse = true
        public let silenceDurationMs = 600

        enum CodingKeys: String, CodingKey {
            case type
            case createResponse = "create_response"
            case interruptResponse = "interrupt_response"
            case silenceDurationMs = "silence_duration_ms"
        }
    }

    public struct Output: Encodable, Sendable, Equatable {
        public let format = Format()
        public let voice: String
    }
}

/// OpenAI's ephemeral client secret for one session: `{ value, expires_at, session }`.
///
/// Bound to the session it was minted for and worthless after `expiresAt`, two minutes out. It
/// is minted right before the socket opens and never stored.
public struct RealtimeGrant: Sendable, Equatable {
    public let secret: String
    public let expiresAt: Date

    public init(secret: String, expiresAt: Date) {
        self.secret = secret
        self.expiresAt = expiresAt
    }

    /// The grant out of a 200. No secret or no expiry is no grant.
    public static func parse(_ data: Data) throws -> RealtimeGrant {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let secret = (root["value"] as? String)?.nonBlank,
              let expires = (root["expires_at"] as? NSNumber)?.doubleValue, expires > 0 else {
            throw BackendFailure.unavailable(status: 200, code: "bad_realtime_grant")
        }
        return RealtimeGrant(secret: secret, expiresAt: Date(timeIntervalSince1970: expires))
    }

    /// Whether the secret can still open a session. Five seconds of slack for the handshake.
    public func isUsable(at now: Date = .now) -> Bool {
        expiresAt.timeIntervalSince(now) > 5
    }

    /// The WebSocket to open: the model in the URL, the secret as a bearer.
    public var socketRequest: URLRequest {
        var components = URLComponents(string: TalkLimits.socketURL)!
        components.queryItems = [URLQueryItem(name: "model", value: TalkLimits.model)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        // URLSession applies the timeout to every wait for data, and a conversation has long
        // quiet stretches. The session's own clock is the only clock; the phone pings.
        request.timeoutInterval = TimeInterval(TalkLimits.maxMinutes * 60)
        return request
    }
}

/// Mints the client secret for a session through the accounts hub.
public protocol RealtimeBackend: Sendable {
    func mint(_ request: RealtimeSessionRequest) async throws -> RealtimeGrant
}
