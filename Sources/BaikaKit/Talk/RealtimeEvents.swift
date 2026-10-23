import Foundation

// The Realtime API events the phone sends and reads, as the OpenAI SDKs spell them. Ported from
// Loco's `Voice.swift`, without the GPT-Live half and without the trip. An event this build does
// not know is `.other(type)`, kept rather than dropped, so a field the API grows cannot break
// the receive loop.

/// What the phone sends down the socket. Four events are the whole of it: the session is
/// configured when the secret is minted, and the server's turn detection does the committing.
public enum RealtimeClientEvent: Sendable, Hashable {
    /// `input_audio_buffer.append`: PCM16 bytes, base64. Never acknowledged.
    case appendAudio(Data)
    /// `response.cancel`: stop the answer in progress.
    case cancelResponse
    /// `input_audio_buffer.clear`: forget what was heard but not answered.
    case clearInput
    /// `conversation.item.truncate`: the person talked over the answer and only `audioEndMs` of
    /// it was played. Without this the model remembers the whole answer, including words that
    /// were never said aloud.
    case truncate(itemId: String, audioEndMs: Int)

    public var type: String {
        switch self {
        case .appendAudio: "input_audio_buffer.append"
        case .cancelResponse: "response.cancel"
        case .clearInput: "input_audio_buffer.clear"
        case .truncate: "conversation.item.truncate"
        }
    }

    /// The JSON text frame. Text, not binary: the API takes events as JSON, audio as base64.
    public var json: Data {
        var body: [String: Any] = ["type": type]
        switch self {
        case .appendAudio(let bytes): body["audio"] = bytes.base64EncodedString()
        case .truncate(let itemId, let ms):
            body["item_id"] = itemId
            body["content_index"] = 0
            body["audio_end_ms"] = max(0, ms)
        case .cancelResponse, .clearInput: break
        }
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    /// The text frame as a string, for `URLSessionWebSocketTask.Message.string`.
    public var text: String { String(decoding: json, as: UTF8.self) }
}

/// What the phone reads off the socket, reduced to what the screen and the speaker need.
public enum RealtimeServerEvent: Sendable, Hashable {
    /// `session.created`: the socket is live and the microphone may start.
    case sessionCreated
    /// `input_audio_buffer.speech_started`: the person is talking. Stop playing.
    case speechStarted
    /// `input_audio_buffer.speech_stopped`: and has stopped. An answer is coming.
    case speechStopped
    /// `input_audio_buffer.committed`: what was said is now a conversation item. Its words come
    /// later in `heard`, and can come after the answer; the id puts them in the right place.
    case committed(itemId: String)
    /// `conversation.item.input_audio_transcription.completed`: what was heard, as a separate
    /// transcription model heard it.
    case heard(itemId: String?, text: String)
    /// `conversation.item.input_audio_transcription.failed`: the words will never come.
    case transcriptionFailed(itemId: String?)
    /// `response.output_item.added`: the answer's item, before any of it is said. It is what
    /// `truncate` names when the person interrupts.
    case answerItem(String)
    /// `response.output_audio_transcript.delta`: the answer, as it is said.
    case sayingDelta(String)
    /// `response.output_audio_transcript.done`: the answer, whole.
    case said(String)
    /// `response.output_audio.delta`: PCM16 at 24 kHz, decoded.
    case audio(Data)
    /// `response.output_audio.done`: the last audio of this answer was sent.
    case audioDone
    /// `response.done`: the answer is over (completed, cancelled, failed or incomplete).
    case responseDone(status: String?)
    /// `error`: most are recoverable and the session stays open.
    case error(code: String?, message: String)
    /// An event this build does not know.
    case other(String)

    /// The event in a text frame, or nil when the frame is not an event at all.
    public static func parse(_ data: Data) -> RealtimeServerEvent? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = root["type"] as? String else { return nil }
        switch type {
        case "session.created": return .sessionCreated
        case "input_audio_buffer.speech_started": return .speechStarted
        case "input_audio_buffer.speech_stopped": return .speechStopped
        case "input_audio_buffer.committed":
            guard let id = (root["item_id"] as? String)?.nonBlank else { return .other(type) }
            return .committed(itemId: id)
        case "conversation.item.input_audio_transcription.completed":
            return .heard(itemId: (root["item_id"] as? String)?.nonBlank, text: (root["transcript"] as? String) ?? "")
        case "conversation.item.input_audio_transcription.failed":
            return .transcriptionFailed(itemId: (root["item_id"] as? String)?.nonBlank)
        case "response.output_item.added":
            let item = root["item"] as? [String: Any] ?? [:]
            guard (item["type"] as? String) == "message", let id = (item["id"] as? String)?.nonBlank else {
                return .other(type)
            }
            return .answerItem(id)
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            return .sayingDelta((root["delta"] as? String) ?? "")
        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            return .said((root["transcript"] as? String) ?? "")
        case "response.output_audio.delta", "response.audio.delta":
            guard let b64 = root["delta"] as? String, let bytes = Data(base64Encoded: b64) else { return .audio(Data()) }
            return .audio(bytes)
        case "response.output_audio.done", "response.audio.done":
            return .audioDone
        case "response.done":
            let response = root["response"] as? [String: Any] ?? [:]
            return .responseDone(status: (response["status"] as? String)?.nonBlank)
        case "error":
            let error = root["error"] as? [String: Any] ?? [:]
            return .error(code: (error["code"] as? String)?.nonBlank, message: (error["message"] as? String)?.nonBlank ?? type)
        default:
            return .other(type)
        }
    }

    public static func parse(text: String) -> RealtimeServerEvent? { parse(Data(text.utf8)) }
}

extension String {
    /// Trimmed, or nil when nothing is left.
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - PCM16, between the microphone and the wire

/// Raw, headerless, mono, signed 16-bit little-endian samples, and the arithmetic the app needs
/// around them. Pure and here, not in the audio engine, so a test can hold it.
public enum PCM16 {
    /// Samples into wire bytes, little-endian whatever the machine is.
    public static func data(_ samples: [Int16]) -> Data {
        var out = Data(capacity: samples.count * 2)
        for s in samples {
            let v = UInt16(bitPattern: s)
            out.append(UInt8(v & 0xff))
            out.append(UInt8(v >> 8))
        }
        return out
    }

    /// Wire bytes into samples. A trailing odd byte, half a sample, is dropped.
    public static func samples(_ data: Data) -> [Int16] {
        let count = data.count / 2
        var out = [Int16](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                out[i] = Int16(bitPattern: UInt16(raw[i * 2]) | (UInt16(raw[i * 2 + 1]) << 8))
            }
        }
        return out
    }

    /// Samples into floats in -1...1, for the player.
    public static func floats(_ samples: [Int16]) -> [Float] {
        samples.map { Float($0) / 32_768 }
    }

    /// How many bytes one frame of `milliseconds` is at `sampleRate`.
    public static func bytes(milliseconds: Int, sampleRate: Int) -> Int {
        max(2, (sampleRate * milliseconds / 1000) * 2)
    }

    /// How long `data` plays for, in seconds.
    public static func seconds(_ data: Data, sampleRate: Int) -> Double {
        guard sampleRate > 0 else { return 0 }
        return Double(data.count / 2) / Double(sampleRate)
    }

    /// The loudness of a frame, 0...1, for the orb. Root mean square scaled up, since speech
    /// sits far below full scale.
    public static func level(_ samples: [Int16]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return min(1, (sum / Double(samples.count)).squareRoot() / 32_768 * 4)
    }

    /// The loudness of a chunk of PCM16 about to be played, sampling every fourth sample: an
    /// orb does not need more, and this runs once per chunk.
    public static func level(of pcm: Data) -> Double {
        let count = pcm.count / 2
        guard count > 0 else { return 0 }
        return pcm.withUnsafeBytes { raw in
            var sum = 0.0
            var n = 0
            var i = 0
            while i < count {
                let v = Double(Int16(bitPattern: UInt16(raw[i * 2]) | (UInt16(raw[i * 2 + 1]) << 8)))
                sum += v * v
                n += 1
                i += 4
            }
            return min(1, (sum / Double(n)).squareRoot() / 32_768 * 4)
        }
    }
}
