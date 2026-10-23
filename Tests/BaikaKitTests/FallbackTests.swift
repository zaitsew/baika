import Foundation
import Testing
@testable import BaikaKit

@Suite("Narration fallback decision")
struct NarrationFallbackTests {
    func body(_ json: String) -> Data { Data(json.utf8) }

    @Test func providerUnconfiguredOn503MovesToTheBackupVoice() {
        #expect(NarrationFallback.decide(status: 503, body: body(#"{"error":"provider_unconfigured"}"#)) == .useBackup)
        #expect(NarrationFallback.decide(status: 503, body: body(#"{"error":"provider_unconfigured","message":"no key"}"#)) == .useBackup)
    }

    @Test func otherOutagesAreSurfacedNotHidden() {
        #expect(NarrationFallback.decide(status: 503, body: body(#"{"error":"provider_unavailable"}"#))
            == .surface(.unavailable(status: 503, code: "provider_unavailable")))
        #expect(NarrationFallback.decide(status: 503, body: Data()) == .surface(.unavailable(status: 503, code: nil)))
        #expect(NarrationFallback.decide(status: 502, body: body(#"{"error":"provider_unconfigured"}"#))
            == .surface(.unavailable(status: 502, code: "provider_unconfigured")))
        #expect(NarrationFallback.decide(status: 500, body: body("not json")) == .surface(.unavailable(status: 500, code: nil)))
    }

    @Test func moneyAndSessionErrorsAreSurfaced() {
        #expect(NarrationFallback.decide(status: 401, body: Data()) == .surface(.signedOut))
        #expect(NarrationFallback.decide(status: 402, body: body(#"{"error":"budget_exhausted"}"#)) == .surface(.budgetExhausted))
        #expect(NarrationFallback.decide(status: 429, body: body(#"{"error":"cap_reached"}"#)) == .surface(.capReached))
        #expect(NarrationFallback.decide(status: 403, body: body(#"{"error":"cap_unknown"}"#)) == .surface(.capReached))
        #expect(NarrationFallback.decide(status: 429, body: body(#"{"error":"rate_limited"}"#)) == .surface(.rateLimited))
        #expect(NarrationFallback.decide(status: 413, body: Data()) == .surface(.tooLarge))
    }

    @Test func badRequestsCarryTheHubsMessage() {
        let failure = NarrationFallback.decide(status: 400, body: body(#"{"error":"bad_request","message":"unknown voice: x"}"#))
        #expect(failure == .surface(.rejected("unknown voice: x")))
        #expect(NarrationFallback.decide(status: 404, body: Data()) == .surface(.rejected("bad request")))
    }

    @Test func nestedProviderErrorsAreRead() {
        let nested = body(#"{"error":{"type":"rate_limit_error","message":"slow down"}}"#)
        #expect(NarrationFallback.errorCode(in: nested) == "rate_limit_error")
        #expect(NarrationFallback.message(in: nested) == "slow down")
    }

    @Test func narrateBodyUsesTheHubsFieldNames() throws {
        let body = NarrateRequestBody(
            product: "baika", input: "Hi.", voiceID: "JBFqnCBsd6RMkjVDRZzb", languageCode: "ru",
            previousText: "Before.", nextText: nil)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        #expect(json?["product"] as? String == "baika")
        #expect(json?["voice_id"] as? String == "JBFqnCBsd6RMkjVDRZzb")
        #expect(json?["model"] as? String == "eleven_v3")
        #expect(json?["language_code"] as? String == "ru")
        #expect(json?["previous_text"] as? String == "Before.")
        #expect(json?["next_text"] == nil)
        #expect(json?["input"] as? String == "Hi.")
    }

    @Test func ttsBodyUsesMarinMp3AndTheDeliveryNote() throws {
        let body = TTSRequestBody(product: "baika", input: "Hi.", instructions: "Calm.")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        #expect(json?["voice"] as? String == "marin")
        #expect(json?["format"] as? String == "mp3")
        #expect(json?["instructions"] as? String == "Calm.")
        #expect(json?["product"] as? String == "baika")
    }

    @Test func chunksFitBothEndpoints() {
        #expect(NarrationChunker.defaultMaxLength <= NarrateRequestBody.maxInputLength)
        #expect(NarrationChunker.defaultMaxLength <= TTSRequestBody.maxInputLength)
    }
}

/// A scripted model backend.
final class Scripted: ScriptBackend, @unchecked Sendable {
    enum Step { case text([String]), fail(BackendFailure), textThenFail([String], BackendFailure) }
    private let lock = NSLock()
    private var steps: [Step]
    private(set) var models: [String] = []

    init(_ steps: [Step]) { self.steps = steps }

    func stream(model: String, system: String, user: String, maxOutputTokens: Int) -> AsyncThrowingStream<String, any Error> {
        lock.lock()
        models.append(model)
        let step = steps.removeFirst()
        lock.unlock()
        return AsyncThrowingStream { continuation in
            switch step {
            case .text(let parts):
                parts.forEach { continuation.yield($0) }
                continuation.finish()
            case .fail(let failure):
                continuation.finish(throwing: failure)
            case .textThenFail(let parts, let failure):
                parts.forEach { continuation.yield($0) }
                continuation.finish(throwing: failure)
            }
        }
    }
}

@Suite("Script writer")
struct ScriptWriterTests {
    let request = StoryRequest(
        topic: "Lanzarote", style: StyleChoice.default.resolve()!, length: .short, language: .en)

    func collect(_ backend: Scripted) async throws -> (models: [String], text: String) {
        var models: [String] = [], text = ""
        for try await event in ScriptWriter(backend: backend).write(request) {
            switch event {
            case .model(let model): models.append(model)
            case .delta(let delta): text += delta
            }
        }
        return (models, text)
    }

    @Test func writesWithOpusWhenAllIsWell() async throws {
        let backend = Scripted([.text(["Hello ", "world"])])
        let result = try await collect(backend)
        #expect(result.models == ["claude-opus-5-5"])
        #expect(result.text == "Hello world")
    }

    @Test func fallsBackToSonnetOnAModelOrCapError() async throws {
        for failure in [BackendFailure.rejected("model has no price"), .capReached, .budgetExhausted] {
            let backend = Scripted([.fail(failure), .text(["ok"])])
            let result = try await collect(backend)
            #expect(result.models == ["claude-opus-5-5", "claude-sonnet-5-5"], "\(failure)")
            #expect(result.text == "ok")
        }
    }

    @Test func otherErrorsAreSurfacedWithoutASecondTry() async {
        for failure in [BackendFailure.signedOut, .offline, .rateLimited, .unavailable(status: 500, code: nil)] {
            let backend = Scripted([.fail(failure), .text(["never"])])
            await #expect(throws: BackendFailure.self) { _ = try await collect(backend) }
            #expect(backend.models == ["claude-opus-5-5"], "\(failure)")
        }
    }

    @Test func noFallbackOnceTextHasStarted() async {
        let backend = Scripted([.textThenFail(["Half a st"], .capReached), .text(["never"])])
        await #expect(throws: BackendFailure.self) { _ = try await collect(backend) }
        #expect(backend.models == ["claude-opus-5-5"])
    }

    @Test func theFallbackErrorIsTheOneShown() async {
        let backend = Scripted([.fail(.capReached), .fail(.budgetExhausted)])
        do {
            _ = try await collect(backend)
            Issue.record("expected a throw")
        } catch {
            #expect(error as? BackendFailure == .budgetExhausted)
        }
    }

    @Test func modelFallbackRuleCoversOnlyModelAndCapFailures() {
        #expect(ModelFallback.shouldFallBack(after: .rejected("x")))
        #expect(ModelFallback.shouldFallBack(after: .capReached))
        #expect(ModelFallback.shouldFallBack(after: .budgetExhausted))
        #expect(!ModelFallback.shouldFallBack(after: .signedOut))
        #expect(!ModelFallback.shouldFallBack(after: .offline))
    }
}
