import Foundation
import Testing
@testable import BaikaKit

private let zhvanetsky = StyleChoice.preset("zhvanetsky").resolve(languageCode: "ru")!

@Suite("Talk persona")
struct TalkPersonaTests {
    @Test func theInstructionsCarryTheStyleTheLanguageAndTheRules() {
        let text = TalkPersona.instructions(style: zhvanetsky, language: .ru)
        #expect(text.contains("STYLE: Жванецкий"))
        #expect(text.contains(zhvanetsky.brief))
        #expect(text.contains(zhvanetsky.deliveryNote))
        #expect(text.contains("Speak Russian by default"))
        #expect(text.contains("Never reproduce, quote or closely paraphrase"))
        #expect(text.contains("every fact must be accurate"))
        #expect(text.contains("answer briefly"))
        #expect(!text.contains("EARLIER IN THIS CONVERSATION"))
    }

    @Test func theLanguageFollowsTheStoryLanguage() {
        #expect(TalkPersona.instructions(style: zhvanetsky, language: .en).contains("Speak English by default"))
        #expect(TalkPersona.instructions(style: zhvanetsky, language: .es).contains("Speak Spanish by default"))
    }

    @Test func aCustomStyleIsUsedAsGiven() {
        let custom = StyleChoice.custom("a noir detective in the rain").resolve()!
        let text = TalkPersona.instructions(style: custom, language: .en)
        #expect(text.contains("STYLE: a noir detective in the rain"))
    }

    @Test func aContinuedSessionIsRemindedOfTheConversation() {
        let lines = [
            TalkLine(id: 1, speaker: .person, text: "Расскажи про Канары"),
            TalkLine(id: 2, speaker: .storyteller, text: "Это вулканы."),
        ]
        let text = TalkPersona.instructions(style: zhvanetsky, language: .ru, recap: lines)
        #expect(text.contains("EARLIER IN THIS CONVERSATION"))
        #expect(text.contains("Person: Расскажи про Канары\nYou: Это вулканы."))
    }

    @Test func theRecapKeepsTheNewestLinesWithinTheLimit() {
        let lines = (0..<100).map { TalkLine(id: $0, speaker: .person, text: "turn number \($0) with some padding words") }
        let recap = TalkPersona.recapBlock(lines)
        #expect(recap.contains("turn number 99 "))
        #expect(!recap.contains("turn number 0 "))
        #expect(recap.count < TalkPersona.maxRecapLength + 400)
    }

    @Test func blankLinesMakeNoRecap() {
        #expect(TalkPersona.recapBlock([TalkLine(id: 1, speaker: .person, text: "  ", partial: true)]) == "")
    }
}

@Suite("Realtime session request")
struct RealtimeSessionTests {
    private func encoded(_ request: RealtimeSessionRequest = RealtimeSessionRequest(instructions: "persona")) throws -> [String: Any] {
        let data = try JSONEncoder().encode(RealtimeMintBody(product: "baika", request: request))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func theBodyMatchesTheHubContract() throws {
        let body = try encoded()
        #expect(body["product"] as? String == "baika")
        #expect(body["minutes"] as? Int == 10)
        let session = try #require(body["session"] as? [String: Any])
        #expect(session["type"] as? String == "realtime")
        #expect(session["model"] as? String == "gpt-realtime-2.1")
        #expect(session["instructions"] as? String == "persona")
        let audio = try #require(session["audio"] as? [String: Any])
        let output = try #require(audio["output"] as? [String: Any])
        #expect(output["voice"] as? String == "cedar")
    }

    @Test func serverVadInterruptsAndWaitsSixHundredMilliseconds() throws {
        let session = try #require(try encoded()["session"] as? [String: Any])
        let input = try #require((session["audio"] as? [String: Any])?["input"] as? [String: Any])
        let vad = try #require(input["turn_detection"] as? [String: Any])
        #expect(vad["type"] as? String == "server_vad")
        #expect(vad["interrupt_response"] as? Bool == true)
        #expect(vad["create_response"] as? Bool == true)
        #expect(vad["silence_duration_ms"] as? Int == 600)
        #expect((input["format"] as? [String: Any])?["rate"] as? Int == 24_000)
        #expect((input["transcription"] as? [String: Any])?["model"] as? String == "gpt-transcribe")
        #expect((session["reasoning"] as? [String: Any])?["effort"] as? String == "low")
        #expect(session["output_modalities"] as? [String] == ["audio"])
        #expect(session["tools"] == nil)
    }

    @Test func minutesAreClampedToWhatTheHubAccepts() throws {
        #expect(RealtimeSessionRequest(minutes: 0, instructions: "x").minutes == 1)
        #expect(RealtimeSessionRequest(minutes: 999, instructions: "x").minutes == TalkLimits.maxMinutes)
        #expect(try encoded(RealtimeSessionRequest(minutes: 5, instructions: "x"))["minutes"] as? Int == 5)
    }

    @Test func aGrantParsesOpenAIsShape() throws {
        let data = Data(#"{"value":"ek_abc","expires_at":1800000000,"session":{"model":"gpt-realtime-2.1"}}"#.utf8)
        let grant = try RealtimeGrant.parse(data)
        #expect(grant.secret == "ek_abc")
        #expect(grant.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func aGrantWithoutASecretOrExpiryIsRefused() {
        for text in [#"{}"#, #"{"value":"","expires_at":1}"#, #"{"value":"ek"}"#, "nope"] {
            #expect(throws: BackendFailure.self) { try RealtimeGrant.parse(Data(text.utf8)) }
        }
    }

    @Test func aSecretIsUsableUntilFiveSecondsBeforeItExpires() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(RealtimeGrant(secret: "s", expiresAt: now.addingTimeInterval(60)).isUsable(at: now))
        #expect(!RealtimeGrant(secret: "s", expiresAt: now.addingTimeInterval(4)).isUsable(at: now))
        #expect(!RealtimeGrant(secret: "s", expiresAt: now.addingTimeInterval(-1)).isUsable(at: now))
    }

    @Test func theSocketGoesToOpenAIWithTheSecretAsABearer() {
        let request = RealtimeGrant(secret: "ek_abc", expiresAt: .now).socketRequest
        #expect(request.url?.absoluteString == "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ek_abc")
    }
}

@Suite("Talk clock and endings")
struct TalkClockTests {
    @Test func aSessionRunsForTheMinutesItWasChargedFor() {
        var clock = TalkClock()
        #expect(clock.minutes == 10)
        #expect(clock.secondsLeft == 600)
        var ran = 0
        while !clock.isOver { ran += 1; _ = clock.tick() }
        #expect(ran == 600)
    }

    @Test func theTickThatEndsItSaysSoOnce() {
        var clock = TalkClock(minutes: 1)
        var endings = 0
        for _ in 0..<80 where clock.tick() { endings += 1 }
        #expect(endings == 1)
        #expect(clock.secondsLeft == 0)
    }

    @Test func continuingStartsAFullSessionAgain() {
        var clock = TalkClock(minutes: 2)
        for _ in 0..<120 { _ = clock.tick() }
        #expect(clock.isOver)
        clock.restart()
        #expect(clock.secondsLeft == 120)
        #expect(!clock.isOver)
    }

    @Test func minutesAreClamped() {
        #expect(TalkClock(minutes: 0).minutes == 1)
        #expect(TalkClock(minutes: 500).minutes == TalkLimits.maxMinutes)
    }

    @Test func onlyATimeoutOrADropOffersContinue() {
        #expect(TalkEnding.timeUp.offersContinue)
        #expect(TalkEnding.dropped.offersContinue)
        #expect(!TalkEnding.reader.offersContinue)
        #expect(!TalkEnding.micDenied.offersContinue)
        #expect(!TalkEnding.fault(.connection).offersContinue)
        #expect(!TalkEnding.fault(.hub(.budgetExhausted)).offersContinue)
    }

    @Test func aFaultOffersARetry() {
        #expect(TalkEnding.fault(.connection).offersRetry)
        #expect(!TalkEnding.timeUp.offersRetry)
    }
}

@Suite("Mute gate")
struct MuteGateTests {
    private let frame = Data(repeating: 7, count: 4800)

    @Test func liveFramesPassThroughUntouched() {
        var gate = MuteGate()
        #expect(gate.outgoing(frame, capturedMuted: false) == frame)
    }

    @Test func muteSendsOneSecondOfSilenceThenNothing() {
        var gate = MuteGate()
        gate.setMuted(true)
        var silent = 0
        var dropped = 0
        for _ in 0..<(MuteGate.tailFrames + 5) {
            if let sent = gate.outgoing(frame, capturedMuted: true) {
                #expect(sent == Data(count: frame.count))
                silent += 1
            } else {
                dropped += 1
            }
        }
        #expect(silent == MuteGate.tailFrames)
        #expect(dropped == 5)
    }

    @Test func unmutingResumesAtOnce() {
        var gate = MuteGate()
        gate.setMuted(true)
        _ = gate.outgoing(frame, capturedMuted: true)
        gate.setMuted(false)
        #expect(!gate.isMuted)
        #expect(gate.outgoing(frame, capturedMuted: false) == frame)
    }

    @Test func aFrameRecordedWhileMutedNeverGoesOutAfterUnmuting() {
        var gate = MuteGate()
        gate.setMuted(true)
        gate.setMuted(false)
        // It sat in a stalled queue and is dequeued after the unmute.
        #expect(gate.outgoing(frame, capturedMuted: true) == nil)
    }

    @Test func mutingTwiceDoesNotOweTheTailTwice() {
        var gate = MuteGate()
        gate.setMuted(true)
        for _ in 0..<MuteGate.tailFrames { _ = gate.outgoing(frame, capturedMuted: true) }
        gate.setMuted(true)
        #expect(gate.outgoing(frame, capturedMuted: true) == nil)
    }
}
