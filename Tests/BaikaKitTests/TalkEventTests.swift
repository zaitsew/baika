import Foundation
import Testing
@testable import BaikaKit

private func object(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

private func frame(_ json: String) -> RealtimeServerEvent? { RealtimeServerEvent.parse(text: json) }

@Suite("Realtime client events")
struct RealtimeClientEventTests {
    @Test func appendCarriesBase64AudioAndRoundTrips() {
        let pcm = Data((0..<64).map { UInt8($0) })
        let sent = object(RealtimeClientEvent.appendAudio(pcm).json)
        #expect(sent["type"] as? String == "input_audio_buffer.append")
        #expect(Data(base64Encoded: sent["audio"] as? String ?? "") == pcm)
    }

    @Test func truncateNamesTheItemAndNeverGoesNegative() {
        let sent = object(RealtimeClientEvent.truncate(itemId: "item_9", audioEndMs: 1234).json)
        #expect(sent["type"] as? String == "conversation.item.truncate")
        #expect(sent["item_id"] as? String == "item_9")
        #expect(sent["content_index"] as? Int == 0)
        #expect(sent["audio_end_ms"] as? Int == 1234)
        #expect(object(RealtimeClientEvent.truncate(itemId: "x", audioEndMs: -5).json)["audio_end_ms"] as? Int == 0)
    }

    @Test func cancelAndClearHaveOnlyAType() {
        #expect(object(RealtimeClientEvent.cancelResponse.json) as NSDictionary == ["type": "response.cancel"])
        #expect(object(RealtimeClientEvent.clearInput.json) as NSDictionary == ["type": "input_audio_buffer.clear"])
    }

    @Test func theTextFrameIsTheJson() {
        let event = RealtimeClientEvent.cancelResponse
        #expect(Data(event.text.utf8) == event.json)
    }
}

@Suite("Realtime server events")
struct RealtimeServerEventTests {
    @Test func theSimpleEventsParse() {
        #expect(frame(#"{"type":"session.created"}"#) == .sessionCreated)
        #expect(frame(#"{"type":"input_audio_buffer.speech_started"}"#) == .speechStarted)
        #expect(frame(#"{"type":"input_audio_buffer.speech_stopped"}"#) == .speechStopped)
        #expect(frame(#"{"type":"response.output_audio.done"}"#) == .audioDone)
    }

    @Test func committedAndHeardCarryTheItem() {
        #expect(frame(#"{"type":"input_audio_buffer.committed","item_id":"i1"}"#) == .committed(itemId: "i1"))
        #expect(frame(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"i1","transcript":"привет"}"#)
            == .heard(itemId: "i1", text: "привет"))
        #expect(frame(#"{"type":"conversation.item.input_audio_transcription.failed","item_id":"i1"}"#)
            == .transcriptionFailed(itemId: "i1"))
    }

    @Test func theAnswerItemIsOnlyAMessage() {
        #expect(frame(#"{"type":"response.output_item.added","item":{"type":"message","id":"m1"}}"#) == .answerItem("m1"))
        #expect(frame(#"{"type":"response.output_item.added","item":{"type":"function_call","id":"f1"}}"#)
            == .other("response.output_item.added"))
    }

    @Test func transcriptDeltasUseBothSpellings() {
        #expect(frame(#"{"type":"response.output_audio_transcript.delta","delta":"Привет"}"#) == .sayingDelta("Привет"))
        #expect(frame(#"{"type":"response.audio_transcript.delta","delta":"Hi"}"#) == .sayingDelta("Hi"))
        #expect(frame(#"{"type":"response.output_audio_transcript.done","transcript":"Привет."}"#) == .said("Привет."))
    }

    @Test func audioDecodesBase64() {
        let pcm = Data([1, 2, 3, 4])
        let json = #"{"type":"response.output_audio.delta","delta":"\#(pcm.base64EncodedString())"}"#
        #expect(frame(json) == .audio(pcm))
        #expect(frame(#"{"type":"response.output_audio.delta","delta":"!!!"}"#) == .audio(Data()))
    }

    @Test func responseDoneAndErrorsAndUnknownTypes() {
        #expect(frame(#"{"type":"response.done","response":{"status":"cancelled"}}"#) == .responseDone(status: "cancelled"))
        #expect(frame(#"{"type":"error","error":{"code":"x","message":"boom"}}"#) == .error(code: "x", message: "boom"))
        #expect(frame(#"{"type":"rate_limits.updated"}"#) == .other("rate_limits.updated"))
    }

    @Test func aFrameThatIsNotAnEventIsNil() {
        #expect(frame("not json") == nil)
        #expect(frame(#"{"no":"type"}"#) == nil)
    }
}

@Suite("PCM16")
struct PCM16Tests {
    @Test func samplesRoundTripThroughBytes() {
        let samples: [Int16] = [0, 1, -1, 32767, -32768, 1234]
        #expect(PCM16.samples(PCM16.data(samples)) == samples)
    }

    @Test func aTrailingHalfSampleIsDropped() {
        #expect(PCM16.samples(Data([1, 0, 9])) == [1])
    }

    @Test func frameSizeAndDuration() {
        #expect(PCM16.bytes(milliseconds: 100, sampleRate: 24_000) == 4800)
        #expect(PCM16.seconds(Data(count: 48_000), sampleRate: 24_000) == 1)
        #expect(PCM16.seconds(Data(count: 10), sampleRate: 0) == 0)
    }

    @Test func levelIsZeroForSilenceAndCappedAtOne() {
        #expect(PCM16.level([Int16](repeating: 0, count: 100)) == 0)
        #expect(PCM16.level([Int16](repeating: 30_000, count: 100)) == 1)
        #expect(PCM16.level([]) == 0)
        #expect(PCM16.level(of: Data()) == 0)
        #expect(PCM16.level(of: PCM16.data([Int16](repeating: 30_000, count: 100))) == 1)
        #expect(PCM16.level(of: Data(count: 200)) == 0)
    }

    @Test func floatsStayInRange() {
        let floats = PCM16.floats([32767, -32768, 0])
        #expect(floats.allSatisfy { $0 >= -1 && $0 <= 1 })
    }
}

@Suite("Talk transcript")
struct TalkTranscriptTests {
    private func fold(_ events: [RealtimeServerEvent]) -> TalkTranscript {
        var transcript = TalkTranscript()
        for event in events { transcript.apply(event) }
        return transcript
    }

    @Test func aQuestionReadsAboveItsAnswerEvenWhenTheWordsComeLate() {
        let transcript = fold([
            .committed(itemId: "q1"),
            .sayingDelta("Канары — "),
            .sayingDelta("это вулканы."),
            .heard(itemId: "q1", text: "Расскажи про Канары"),
            .responseDone(status: "completed"),
        ])
        #expect(transcript.lines.map(\.speaker) == [.person, .storyteller])
        #expect(transcript.lines[0].text == "Расскажи про Канары")
        #expect(transcript.lines[1].text == "Канары — это вулканы.")
        #expect(transcript.lines.allSatisfy { !$0.partial })
    }

    @Test func wordsWithoutAHeldLineGoBeforeThePartialAnswer() {
        let transcript = fold([.sayingDelta("Ответ"), .heard(itemId: nil, text: "Вопрос")])
        #expect(transcript.lines.map(\.text) == ["Вопрос", "Ответ"])
    }

    @Test func aFailedTranscriptionDropsTheHeldLine() {
        let transcript = fold([.committed(itemId: "q1"), .transcriptionFailed(itemId: "q1")])
        #expect(transcript.lines.isEmpty)
    }

    @Test func aBlankHeardDropsTheHeldLine() {
        let transcript = fold([.committed(itemId: "q1"), .heard(itemId: "q1", text: "  ")])
        #expect(transcript.lines.isEmpty)
    }

    @Test func aCutOffAnswerKeepsWhatWasSaid() {
        let transcript = fold([.sayingDelta("Half an answ"), .responseDone(status: "cancelled")])
        #expect(transcript.lines.count == 1)
        #expect(transcript.lines[0].text == "Half an answ")
        #expect(!transcript.lines[0].partial)
    }

    @Test func saidReplacesTheDeltasWithTheWholeText() {
        let transcript = fold([.sayingDelta("Hel"), .said("Hello there.")])
        #expect(transcript.lines.map(\.text) == ["Hello there."])
    }

    @Test func theTranscriptIsCapped() {
        var transcript = TalkTranscript()
        for i in 0..<(TalkTranscript.maxLines + 20) {
            transcript.apply(.said("line \(i)"))
        }
        #expect(transcript.lines.count == TalkTranscript.maxLines)
        #expect(transcript.lines.last?.text == "line \(TalkTranscript.maxLines + 19)")
    }

    @Test func aTalkedOverAnswerKeepsOnlyWhatWasPlayed() {
        var transcript = fold([.answerItem("a1"), .sayingDelta("one two three four five six seven eight")])
        transcript.keepHeard(fraction: 0.5)
        #expect(transcript.lines.map(\.text) == ["one two three four"])
        #expect(!transcript.lines[0].partial)
        // Words that arrive late for the cut answer are dropped; the next answer is kept.
        transcript.apply(.sayingDelta(" nine ten"))
        transcript.apply(.said("one two three four five six seven eight nine ten"))
        #expect(transcript.lines.map(\.text) == ["one two three four"])
        transcript.apply(.answerItem("a2"))
        transcript.apply(.said("Next answer."))
        #expect(transcript.lines.map(\.text) == ["one two three four", "Next answer."])
    }

    @Test func nothingPlayedLeavesNoLine() {
        var transcript = fold([.answerItem("a1"), .said("Never heard at all.")])
        transcript.keepHeard(fraction: 0)
        #expect(transcript.lines.isEmpty)
    }

    @Test func theCaptionIsTheLastStorytellerSentence() {
        let transcript = fold([.said("Первое. Второе предложение!"), .heard(itemId: nil, text: "Дальше")])
        #expect(transcript.caption == "Второе предложение!")
        #expect(transcript.hasPersonSpeech)
    }
}

@Suite("Talk caption and topic")
struct TalkCaptionTests {
    @Test func theLastSentenceOfSeveral() {
        #expect(TalkCaption.lastSentence(of: "One. Two! Three?") == "Three?")
        #expect(TalkCaption.lastSentence(of: "Один.\nДва.") == "Два.")
    }

    @Test func aSentenceStillBeingSaidShowsAsItGrows() {
        #expect(TalkCaption.lastSentence(of: "Done. And then the") == "And then the")
    }

    @Test func nothingSaidIsEmpty() {
        #expect(TalkCaption.lastSentence(of: "  \n ") == "")
        #expect(TalkCaption.lastSentence(of: "") == "")
    }

    @Test func aLongSentenceKeepsItsEndOnAWordBoundary() {
        let long = (0..<60).map { "word\($0)" }.joined(separator: " ") + "."
        let caption = TalkCaption.lastSentence(of: long, maxLength: 40)
        #expect(caption.hasPrefix("\u{2026}"))
        #expect(caption.count <= 41)
        #expect(caption.hasSuffix("word59."))
    }

    private func said(_ texts: [String]) -> [TalkLine] {
        texts.enumerated().map { TalkLine(id: $0.offset, speaker: .person, text: $0.element) }
    }

    @Test func theTopicIsThePersonsOwnWordsInOrder() {
        let lines = said(["Расскажи про Канары", "ага", "а про Тенерифе подробнее"])
        #expect(TalkTopic.derive(from: lines) == "Расскажи про Канары а про Тенерифе подробнее")
    }

    @Test func theTopicSkipsTheStorytellerAndNothingMeansNil() {
        let lines = [TalkLine(id: 1, speaker: .storyteller, text: "I am talking a lot here"),
                     TalkLine(id: 2, speaker: .person, text: "ok")]
        #expect(TalkTopic.derive(from: lines) == nil)
        #expect(TalkTopic.derive(from: []) == nil)
    }

    @Test func theNewestLinesWinWhenTheTopicIsTooLong() {
        let lines = said(["first request here", "second request here", "third request here"])
        let topic = TalkTopic.derive(from: lines, maxLength: 40)
        #expect(topic == "second request here third request here")
        #expect((topic ?? "").count <= 40)
    }

    @Test func aSingleOverlongLineIsCutNotDropped() {
        let line = TalkLine(id: 1, speaker: .person, text: String(repeating: "word ", count: 200))
        let topic = TalkTopic.derive(from: [line], maxLength: 50)
        #expect(topic?.count == 50)
    }
}
