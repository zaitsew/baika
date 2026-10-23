import Foundation
import Testing
@testable import BaikaKit

@Suite("Narration chunker")
struct NarrationChunkerTests {
    /// A paragraph of `sentences` sentences, each about 60 characters.
    func paragraph(_ sentences: Int, seed: Int = 0) -> String {
        (0..<sentences).map { "Sentence number \($0 + seed) walks along the quiet harbour wall." }.joined(separator: " ")
    }

    @Test func aGraphemeWiderThanTheLimitStillMovesForward() {
        #expect(NarrationChunker().hardSplit("😀 ok").count >= 1)
        #expect(NarrationChunker(maxLength: 1, firstChunkLength: 1).hardSplit("😀😀") == ["😀", "😀"])
    }

    @Test func aShortScriptIsOneChunkWithNoContext() {
        let chunks = NarrationChunker().chunks(for: "Hello there. This is short.")
        #expect(chunks.count == 1)
        #expect(chunks[0].text == "Hello there. This is short.")
        #expect(chunks[0].previousText == nil)
        #expect(chunks[0].nextText == nil)
    }

    @Test func emptyScriptGivesNoChunks() {
        #expect(NarrationChunker().chunks(for: "").isEmpty)
        #expect(NarrationChunker().chunks(for: " \n \n").isEmpty)
    }

    @Test func noChunkIsLongerThanTheLimit() {
        let script = (0..<40).map { paragraph(6, seed: $0 * 6) }.joined(separator: "\n\n")
        let chunker = NarrationChunker()
        let chunks = chunker.chunks(for: script)
        #expect(chunks.count > 2)
        for chunk in chunks { #expect(chunk.text.utf16.count <= 2500) }
    }

    @Test func theFirstChunkIsShortSoPlaybackStartsFast() {
        let script = (0..<30).map { paragraph(5, seed: $0 * 5) }.joined(separator: "\n\n")
        let chunks = NarrationChunker().chunks(for: script)
        #expect(chunks[0].text.utf16.count <= 900)
        #expect(chunks[0].text.utf16.count > 300)
        #expect(chunks[1].text.utf16.count > 900)
    }

    @Test func aLongFirstParagraphIsCutIntoSentencesForTheFirstChunk() {
        let chunks = NarrationChunker().chunks(for: paragraph(30))
        #expect(chunks[0].text.utf16.count <= 900)
        #expect(chunks[0].text.hasSuffix("wall."))
    }

    @Test func chunksPreferParagraphBoundaries() {
        let paragraphs = (0..<12).map { paragraph(8, seed: $0 * 8) }
        let chunks = NarrationChunker().chunks(for: paragraphs.joined(separator: "\n\n"))
        let known = Set(paragraphs)
        // Every chunk after the first is built of whole paragraphs, since each fits the limit.
        for chunk in chunks.dropFirst() {
            for piece in chunk.text.components(separatedBy: "\n\n") { #expect(known.contains(piece)) }
        }
    }

    @Test func noTextIsLostOrReordered() {
        let script = (0..<25).map { paragraph(7, seed: $0 * 7) }.joined(separator: "\n\n")
        let chunks = NarrationChunker().chunks(for: script)
        let words = chunks.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace)
        #expect(words == script.split(whereSeparator: \.isWhitespace))
    }

    @Test func aSingleHugeSentenceIsCutAtSpaces() {
        let sentence = Array(repeating: "word", count: 2000).joined(separator: " ") + "."
        let chunks = NarrationChunker().chunks(for: sentence)
        #expect(chunks.count >= 4)
        for chunk in chunks {
            #expect(chunk.text.utf16.count <= 2500)
            #expect(!chunk.text.hasPrefix(" "))
            #expect(!chunk.text.hasSuffix(" "))
        }
        let words = chunks.flatMap { $0.text.split(separator: " ") }
        #expect(words.count == 2000)
    }

    @Test func aTextWithNoSpacesIsStillCut() {
        let blob = String(repeating: "я", count: 7000)
        let chunks = NarrationChunker().chunks(for: blob)
        #expect(chunks.count >= 3)
        for chunk in chunks { #expect(chunk.text.utf16.count <= 2500) }
        #expect(chunks.map(\.text).joined().count == 7000)
    }

    @Test func sentenceEndsHandleQuotesEllipsisAndMarks() {
        let chunker = NarrationChunker()
        let sentences = chunker.sentences(of: "Он сказал: «Идём!» Потом замолчал... Почему? Никто не знал.")
        #expect(sentences == ["Он сказал: «Идём!»", "Потом замолчал...", "Почему?", "Никто не знал."])
    }

    @Test func contextIsAtMostThreeHundredCharactersAtWordEdges() {
        let script = (0..<20).map { paragraph(6, seed: $0 * 6) }.joined(separator: "\n\n")
        let chunks = NarrationChunker().chunks(for: script)
        #expect(chunks.count > 2)
        #expect(chunks[1].previousText != nil)
        #expect(chunks[1].nextText != nil)
        for chunk in chunks {
            #expect((chunk.previousText?.utf16.count ?? 0) <= 300)
            #expect((chunk.nextText?.utf16.count ?? 0) <= 300)
        }
        // The context is the real neighbour text, cut at a word.
        let previous = chunks[1].previousText!
        #expect(chunks[0].text.hasSuffix(previous))
        let next = chunks[1].nextText!
        #expect(chunks[2].text.hasPrefix(next))
        #expect(chunks[0].previousText == nil)
        #expect(chunks.last?.nextText == nil)
    }

    @Test func limitsAreCountedInUTF16Units() {
        // Emoji take two units; 1300 of them are 2600 units though only 1300 characters.
        let text = String(repeating: "😀", count: 1300)
        let chunks = NarrationChunker().chunks(for: text)
        for chunk in chunks { #expect(chunk.text.utf16.count <= 2500) }
    }

    @Test func audioTagsStayInTheChunkText() {
        let chunks = NarrationChunker().chunks(for: "Quiet now. [pause] Listen. [whispers] Closer.")
        #expect(chunks[0].text.contains("[pause]"))
        #expect(chunks[0].text.contains("[whispers]"))
    }
}
