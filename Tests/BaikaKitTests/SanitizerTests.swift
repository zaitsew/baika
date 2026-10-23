import Foundation
import Testing
@testable import BaikaKit

@Suite("Story sanitizer")
struct SanitizerTests {
    @Test func stripsHeadingsListsAndEmphasis() {
        let raw = """
        # The Islands

        **Bold** words and *italic* ones and __under__ and _soft_.

        - first thing
        * second thing
        1. numbered
        > quoted line
        """
        let clean = StorySanitizer.sanitize(raw)
        #expect(clean == """
        The Islands

        Bold words and italic ones and under and soft.

        first thing
        second thing
        numbered
        quoted line
        """)
    }

    @Test func linksKeepTheirTextAndCodeFencesGo() {
        let raw = "See [the map](https://example.com/map) now.\n```\ncode\n```\nDone."
        #expect(StorySanitizer.sanitize(raw) == "See the map now.\ncode\nDone.")
    }

    @Test func horizontalRulesBecomeParagraphBreaks() {
        #expect(StorySanitizer.sanitize("One.\n---\nTwo.") == "One.\n\nTwo.")
    }

    @Test func keepsTheFiveAllowedTags() {
        let raw = "Well. [pause] Then he [laughs] said it. [sighs] [whispers] Quiet. [sarcastic] Sure."
        #expect(StorySanitizer.sanitize(raw) == raw)
    }

    @Test func tagsAreLowercasedAndTrimmed() {
        #expect(StorySanitizer.sanitize("A [ Pause ] B [LAUGHS] C") == "A [pause] B [laughs] C")
    }

    @Test func dropsUnknownTagsAndSoundNotes() {
        let raw = "He ran. [applause] She stopped [long pause] and [excited] spoke [Scene: kitchen]."
        #expect(StorySanitizer.sanitize(raw) == "He ran. She stopped and spoke.")
    }

    @Test func removesAllTagsForTheScreenAndTheBackupVoice() {
        let raw = "Well. [pause] He [laughs] left [unknown]."
        #expect(StorySanitizer.spokenText(raw) == "Well. He left.")
    }

    @Test func aHalfWrittenTagIsHeldBackWhileStreaming() {
        #expect(StorySanitizer.sanitizeStreaming("Quiet now. [pau") == "Quiet now.")
        #expect(StorySanitizer.sanitizeStreaming("Quiet now. [pause") == "Quiet now.")
        #expect(StorySanitizer.sanitizeStreaming("Quiet now. [pause] Go") == "Quiet now. [pause] Go")
    }

    @Test func longBracketTextIsNotTreatedAsATag() {
        let long = "[this is a very long aside that is clearly not a delivery tag at all]"
        #expect(StorySanitizer.sanitize("Hi \(long) there").contains("very long aside"))
    }

    @Test func collapsesWhitespaceAndBlankLines() {
        #expect(StorySanitizer.sanitize("A   b\t\tc\n\n\n\nD  \n") == "A b c\n\nD")
    }

    @Test func noMarkdownSurvivesAFullModelAnswer() {
        let raw = """
        ## Title: The Harbour

        The **first** line [pause] is spoken.
        - not a list
        `code` and ~~strike~~ too.
        """
        let clean = StorySanitizer.sanitize(raw)
        for symbol in ["#", "*", "`", "~~", "- "] { #expect(!clean.contains(symbol)) }
    }
}

@Suite("Story parts and stream")
struct StoryPartsTests {
    @Test func firstLineIsTheTitle() {
        let parts = StoryParts.parse("The Salt Road\n\nOnce, a long time ago.\n\nThe end.", streaming: false)
        #expect(parts.title == "The Salt Road")
        #expect(parts.titleIsComplete)
        #expect(parts.script == "Once, a long time ago.\n\nThe end.")
    }

    @Test func titleLabelQuotesAndFullStopAreRemoved() {
        #expect(StoryParts.cleanTitle("Title: «Соляная дорога».") == "Соляная дорога")
        #expect(StoryParts.cleanTitle("\"The Road\"") == "The Road")
        #expect(StoryParts.cleanTitle("Название: Дорога") == "Дорога")
    }

    @Test func aTitleStillArrivingIsNotComplete() {
        let parts = StoryParts.parse("The Salt Ro", streaming: true)
        #expect(parts.title == "The Salt Ro")
        #expect(!parts.titleIsComplete)
        #expect(parts.script.isEmpty)
    }

    @Test func streamingBuildsUpThenFinalizes() {
        var stream = StoryStream()
        stream.append("The Salt Road\n\nOnce, ")
        #expect(stream.live.title == "The Salt Road")
        #expect(stream.live.script == "Once,")
        stream.append("a time. [pau")
        #expect(stream.live.script == "Once, a time.")
        stream.append("se] End.")
        #expect(stream.final.script == "Once, a time. [pause] End.")
        #expect(stream.final.readableScript == "Once, a time. End.")
    }

    @Test func leadingBlankLinesAreIgnored() {
        let parts = StoryParts.parse("\n\n  Title\n\nBody.", streaming: false)
        #expect(parts.title == "Title")
        #expect(parts.script == "Body.")
    }
}
