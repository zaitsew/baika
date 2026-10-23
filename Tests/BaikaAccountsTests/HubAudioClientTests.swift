import BaikaKit
import FabriqueAccounts
import Foundation
import Testing
@testable import BaikaAccounts

/// Records the requests a stub transport saw and plays scripted answers.
private final class Wire: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [(Int, Data)]
    private var seen: [URLRequest] = []

    init(_ answers: [(Int, Data)]) { self.answers = answers }

    var requests: [URLRequest] { lock.withLock { seen } }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.withLock {
            seen.append(request)
            let answer = answers.removeFirst()
            return (answer.1, answer.0)
        }
    }
}

private let mp3 = Data(repeating: 0xFF, count: 4096)
private func json(_ text: String) -> Data { Data(text.utf8) }

private func client(_ wire: Wire, token: @escaping @Sendable () async throws -> String = { "tok" }) -> HubAudioClient {
    HubAudioClient(
        functionsURL: URL(string: "https://hub.example.com/functions/v1")!, anonKey: "anon", product: "baika",
        accessToken: token, send: { try await wire.send($0) })
}

private let chunk = NarrationChunk(index: 1, text: "Hello. [pause] World.", previousText: "Before.", nextText: "After.")
private let settings = NarrationSettings(
    voice: VoiceCatalog.default, style: StyleChoice.default.resolve()!, language: .ru)

private func body(of request: URLRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
}

@Suite("Hub audio client")
struct HubAudioClientTests {
    @Test func narrateSendsTheContractToTheNarrateEndpointWithTheBearer() async throws {
        let wire = Wire([(200, mp3)])
        let audio = try await client(wire).narrate(chunk, settings: settings)
        #expect(audio == NarrationAudio(data: mp3, usedBackup: false))
        let request = try #require(wire.requests.first)
        #expect(request.url?.absoluteString == "https://hub.example.com/functions/v1/ai/narrate")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
        let sent = body(of: request)
        #expect(sent["product"] as? String == "baika")
        #expect(sent["input"] as? String == "Hello. [pause] World.")
        #expect(sent["voice_id"] as? String == "JBFqnCBsd6RMkjVDRZzb")
        #expect(sent["model"] as? String == "eleven_v3")
        #expect(sent["language_code"] as? String == "ru")
        #expect(sent["previous_text"] as? String == "Before.")
        #expect(sent["next_text"] as? String == "After.")
    }

    @Test func providerUnconfiguredFallsBackToTtsWithoutTagsAndWithTheDeliveryNote() async throws {
        let wire = Wire([(503, json(#"{"error":"provider_unconfigured"}"#)), (200, mp3)])
        let audio = try await client(wire).narrate(chunk, settings: settings)
        #expect(audio.usedBackup)
        #expect(wire.requests.count == 2)
        let second = try #require(wire.requests.last)
        #expect(second.url?.absoluteString == "https://hub.example.com/functions/v1/ai/tts")
        let sent = body(of: second)
        #expect(sent["input"] as? String == "Hello. World.")
        #expect(sent["voice"] as? String == "marin")
        #expect(sent["format"] as? String == "mp3")
        #expect(sent["product"] as? String == "baika")
        #expect((sent["instructions"] as? String)?.isEmpty == false)
        #expect(second.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func preferBackupSkipsElevenLabsEntirely() async throws {
        let wire = Wire([(200, mp3)])
        var backup = settings
        backup.preferBackup = true
        let audio = try await client(wire).narrate(chunk, settings: backup)
        #expect(audio.usedBackup)
        #expect(wire.requests.map { $0.url?.lastPathComponent } == ["tts"])
    }

    @Test func otherErrorsAreSurfacedAndNeverReachTts() async {
        let cases: [(Int, String, BackendFailure)] = [
            (503, #"{"error":"provider_unavailable"}"#, .unavailable(status: 503, code: "provider_unavailable")),
            (402, #"{"error":"budget_exhausted"}"#, .budgetExhausted),
            (401, "{}", .signedOut),
            (429, #"{"error":"cap_reached"}"#, .capReached),
            (500, "boom", .unavailable(status: 500, code: nil)),
        ]
        for (status, text, expected) in cases {
            let wire = Wire([(status, json(text)), (200, mp3)])
            do {
                _ = try await client(wire).narrate(chunk, settings: settings)
                Issue.record("expected \(expected)")
            } catch {
                #expect(error as? BackendFailure == expected)
            }
            #expect(wire.requests.count == 1, "status \(status) must not try the backup voice")
        }
    }

    @Test func aFailingBackupVoiceIsSurfaced() async {
        let wire = Wire([(503, json(#"{"error":"provider_unconfigured"}"#)), (429, json(#"{"error":"cap_reached"}"#))])
        do {
            _ = try await client(wire).narrate(chunk, settings: settings)
            Issue.record("expected a throw")
        } catch {
            #expect(error as? BackendFailure == .capReached)
        }
    }

    @Test func aSuccessThatIsNotAudioIsRejected() async {
        for payload in [Data(), json(#"{"error":"x"}"#), Data(repeating: 1, count: 10)] {
            let wire = Wire([(200, payload)])
            do {
                _ = try await client(wire).narrate(chunk, settings: settings)
                Issue.record("expected a throw")
            } catch {
                #expect(error as? BackendFailure == .badAudio)
            }
        }
    }

    @Test func noSessionMeansNothingIsSent() async {
        let wire = Wire([(200, mp3)])
        let signedOut = client(wire, token: { throw BackendFailure.signedOut })
        do {
            _ = try await signedOut.narrate(chunk, settings: settings)
            Issue.record("expected a throw")
        } catch {
            #expect(error as? BackendFailure == .signedOut)
        }
        #expect(wire.requests.isEmpty)
    }

    @Test func plainHttpNeverSeesTheToken() async {
        let wire = Wire([(200, mp3)])
        let insecure = HubAudioClient(
            functionsURL: URL(string: "http://hub.example.com/functions/v1")!, anonKey: "a", product: "baika",
            accessToken: { "tok" }, send: { try await wire.send($0) })
        do {
            _ = try await insecure.narrate(chunk, settings: settings)
            Issue.record("expected a throw")
        } catch {
            #expect(error as? BackendFailure == .unavailable(status: 0, code: "insecure_hub_url"))
        }
        #expect(wire.requests.isEmpty)
    }

    @Test func aNetworkErrorIsOfflineAndCancellationIsKept() async {
        let offline = HubAudioClient(
            functionsURL: URL(string: "https://h.example.com/functions/v1")!, anonKey: "a", product: "baika",
            accessToken: { "t" }, send: { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await offline.narrate(chunk, settings: settings)
            Issue.record("expected a throw")
        } catch {
            #expect(error as? BackendFailure == .offline)
        }
        let cancelled = HubAudioClient(
            functionsURL: URL(string: "https://h.example.com/functions/v1")!, anonKey: "a", product: "baika",
            accessToken: { "t" }, send: { _ in throw URLError(.cancelled) })
        do {
            _ = try await cancelled.narrate(chunk, settings: settings)
            Issue.record("expected a throw")
        } catch {
            #expect(error is CancellationError)
        }
    }
}

@Suite("Hub script backend")
struct HubScriptBackendTests {
    @Test func requestShapeIsTheHubsChatContract() {
        let messages = HubScriptBackend.messages(system: "S", user: "U")
        #expect(messages.count == 2)
        #expect(messages[0].role == .system && messages[0].content == "S")
        #expect(messages[1].role == .user && messages[1].content == "U")
        let extra = HubScriptBackend.extra(maxOutputTokens: 6000)
        #expect(extra["max_completion_tokens"] == .number(6000))
        #expect(extra["reasoning_effort"] == .string("low"))
        #expect(extra["product"] == nil && extra["temperature"] == nil)
    }

    @Test func kitErrorsBecomeBackendFailures() {
        func map(_ error: AccountsError) -> BackendFailure { HubScriptBackend.failure(for: error) }
        #expect(map(.notSignedIn) == .signedOut)
        #expect(map(.budgetExhausted(BudgetExhausted(remainingEURMonth: 0, plan: "free"))) == .budgetExhausted)
        #expect(map(.rateLimited(retryAfter: nil)) == .rateLimited)
        #expect(map(.server(status: 401, code: nil, message: "")) == .signedOut)
        #expect(map(.server(status: 429, code: "cap_reached", message: "")) == .capReached)
        #expect(map(.server(status: 403, code: "cap_unknown", message: "")) == .capReached)
        #expect(map(.server(status: 400, code: "bad_request", message: "model x has no price on this hub")) == .rejected("model x has no price on this hub"))
        #expect(map(.server(status: 502, code: nil, message: "")) == .unavailable(status: 502, code: nil))
    }

    @Test func urlErrorsAreOfflineAndCancellationPasses() {
        #expect(HubScriptBackend.translate(URLError(.notConnectedToInternet)) as? BackendFailure == .offline)
        #expect(HubScriptBackend.translate(URLError(.cancelled)) is CancellationError)
        #expect(HubScriptBackend.translate(CancellationError()) is CancellationError)
    }

    @Test func theStreamPassesDeltasAndTranslatesAFailure() async throws {
        let backend = HubScriptBackend(stream: { _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield("Hel")
                continuation.yield("lo")
                continuation.finish(throwing: AccountsError.server(status: 429, code: "cap_reached", message: ""))
            }
        })
        var text = ""
        do {
            for try await delta in backend.stream(model: "m", system: "s", user: "u", maxOutputTokens: 100) { text += delta }
            Issue.record("expected a throw")
        } catch {
            #expect(error as? BackendFailure == .capReached)
        }
        #expect(text == "Hello")
    }
}

private final class MintWire: @unchecked Sendable {
    private let lock = NSLock()
    private let answer: (Int, Data)
    private var seen: [URLRequest] = []
    init(_ status: Int, _ body: String) { answer = (status, Data(body.utf8)) }
    var requests: [URLRequest] { lock.withLock { seen } }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.withLock { seen.append(request) }
        return (answer.1, answer.0)
    }
}

private func realtime(_ wire: MintWire, token: @escaping @Sendable () async throws -> String = { "tok" }) -> HubRealtimeClient {
    HubRealtimeClient(
        functionsURL: URL(string: "https://hub.example.com/functions/v1")!, anonKey: "anon", product: "baika",
        accessToken: token, send: { try await wire.send($0) })
}

@Suite("Hub realtime client")
struct HubRealtimeClientTests {
    private let session = RealtimeSessionRequest(instructions: "persona")

    @Test func mintPostsTheContractWithTheBearerAndReturnsTheSecret() async throws {
        let wire = MintWire(200, #"{"value":"ek_1","expires_at":1800000000,"session":{}}"#)
        let grant = try await realtime(wire).mint(session)
        #expect(grant.secret == "ek_1")
        let request = try #require(wire.requests.first)
        #expect(request.url?.absoluteString == "https://hub.example.com/functions/v1/ai/realtime")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
        let sent = body(of: request)
        #expect(sent["product"] as? String == "baika")
        #expect(sent["minutes"] as? Int == 10)
        let inner = sent["session"] as? [String: Any]
        #expect(inner?["model"] as? String == "gpt-realtime-2.1")
        #expect(((inner?["audio"] as? [String: Any])?["output"] as? [String: Any])?["voice"] as? String == "cedar")
    }

    @Test func hubErrorsBecomeBackendFailures() async {
        let cases: [(Int, String, BackendFailure)] = [
            (402, #"{"error":"budget_exhausted"}"#, .budgetExhausted),
            (401, "{}", .signedOut),
            (429, #"{"error":"cap_reached"}"#, .capReached),
            (400, #"{"error":"session_too_long","message":"too long"}"#, .rejected("too long")),
            (502, "bad gateway", .unavailable(status: 502, code: nil)),
        ]
        for (status, text, expected) in cases {
            do {
                _ = try await realtime(MintWire(status, text)).mint(session)
                Issue.record("expected \(expected)")
            } catch {
                #expect(error as? BackendFailure == expected)
            }
        }
    }

    @Test func aSuccessWithoutASecretIsRefused() async {
        do {
            _ = try await realtime(MintWire(200, "{}")).mint(session)
            Issue.record("expected a throw")
        } catch {
            #expect(error is BackendFailure)
        }
    }

    @Test func noSessionMeansNothingIsSent() async {
        let wire = MintWire(200, "{}")
        do {
            _ = try await realtime(wire, token: { throw BackendFailure.signedOut }).mint(session)
            Issue.record("expected a throw")
        } catch {
            #expect(error as? BackendFailure == .signedOut)
        }
        #expect(wire.requests.isEmpty)
    }

    @Test func aPlainHttpHubNeverSeesTheToken() async {
        let wire = MintWire(200, "{}")
        let insecure = HubRealtimeClient(
            functionsURL: URL(string: "http://hub.example.com/functions/v1")!, anonKey: "anon", product: "baika",
            accessToken: { "tok" }, send: { try await wire.send($0) })
        do {
            _ = try await insecure.mint(session)
            Issue.record("expected a throw")
        } catch {
            #expect(error as? BackendFailure == .unavailable(status: 0, code: "insecure_hub_url"))
        }
        #expect(wire.requests.isEmpty)
    }
}
