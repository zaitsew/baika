import Foundation

/// Cleans model output for the ear: strips markdown, keeps the five audio tags the prompt
/// allows, drops every other bracketed tag.
public enum StorySanitizer {
    /// The ElevenLabs v3 tags the storyteller may use.
    public static let allowedTags: Set<String> = ["pause", "laughs", "sighs", "whispers", "sarcastic"]

    /// The longest bracket content treated as a tag. Anything longer is plain text in brackets.
    static let maxTagLength = 40

    /// The finished script: no markdown, only allowed tags, tidy whitespace.
    public static func sanitize(_ raw: String) -> String {
        tidy(stripTags(stripMarkdown(raw), keepAllowed: true))
    }

    /// The same for text that is still arriving: a trailing `[` that has not closed yet is held
    /// back so a half-written tag never flashes on screen.
    public static func sanitizeStreaming(_ raw: String) -> String {
        var text = raw
        if let open = text.lastIndex(of: "["), !text[open...].contains("]"),
           text.distance(from: open, to: text.endIndex) <= maxTagLength + 1 {
            text = String(text[..<open])
        }
        return sanitize(text)
    }

    /// The script as a person reads it: sanitized, with the allowed tags removed too.
    /// Used for the screen and for the backup voice, which would read a tag aloud.
    public static func spokenText(_ raw: String) -> String {
        tidy(stripTags(stripMarkdown(raw), keepAllowed: false))
    }

    // MARK: Markdown

    static func stripMarkdown(_ raw: String) -> String {
        var lines: [String] = []
        for var line in raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { continue }
            if isHorizontalRule(trimmed) { lines.append(""); continue }
            line = trimmed
            line = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^>+\s?"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^([-*+•]|\d{1,3}[.)])\s+"#, with: "", options: .regularExpression)
            // Images and links keep their text.
            line = line.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: #"\[([^\]]*)\]\((?:https?:|mailto:|/)[^)]*\)"#, with: "$1", options: .regularExpression)
            // Emphasis: bold first, then single markers that wrap a word or phrase.
            line = line.replacingOccurrences(of: #"(\*\*|__)(.+?)\1"#, with: "$2", options: .regularExpression)
            line = line.replacingOccurrences(of: #"(?<![\w*])\*(\S(?:[^*]*?\S)?)\*(?![\w*])"#, with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: #"(?<![\w_])_(\S(?:[^_]*?\S)?)_(?![\w_])"#, with: "$1", options: .regularExpression)
            // Whatever is left of the markers is noise to a narrator.
            line = line.replacingOccurrences(of: "*", with: "")
            line = line.replacingOccurrences(of: "`", with: "")
            line = line.replacingOccurrences(of: "~~", with: "")
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let marks = line.filter { !$0.isWhitespace }
        guard marks.count >= 3, let first = marks.first, "-*_=".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    // MARK: Tags

    /// Walks the text once. `[tag]` stays only when it is an allowed tag (and `keepAllowed`);
    /// any other short bracketed phrase is dropped.
    static func stripTags(_ text: String, keepAllowed: Bool) -> String {
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            guard ch == "[", let close = closingBracket(in: text, from: index) else {
                out.append(ch)
                index = text.index(after: index)
                continue
            }
            let inner = text[text.index(after: index)..<close].trimmingCharacters(in: .whitespaces).lowercased()
            if keepAllowed, allowedTags.contains(inner) { out += "[\(inner)]" }
            index = text.index(after: close)
        }
        return out
    }

    /// The `]` that closes the bracket at `open`, if it is close enough, on the same line and
    /// holds no other `[`.
    private static func closingBracket(in text: String, from open: String.Index) -> String.Index? {
        var cursor = text.index(after: open)
        var length = 0
        while cursor < text.endIndex, length <= maxTagLength {
            let ch = text[cursor]
            if ch == "]" { return cursor }
            if ch == "[" || ch == "\n" { return nil }
            cursor = text.index(after: cursor)
            length += 1
        }
        return nil
    }

    // MARK: Whitespace

    static func tidy(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n").map { line -> String in
            var line = line.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            // A removed tag can leave a space before punctuation.
            line = line.replacingOccurrences(of: #" +([,.!?;:…])"#, with: "$1", options: .regularExpression)
            return line.trimmingCharacters(in: .whitespaces)
        }
        // At most one blank line between paragraphs.
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(line)
        }
        lines = result
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

/// A script split into the title (its first line) and the story.
public struct StoryParts: Sendable, Equatable {
    /// The title so far. While the first line is still arriving this is the partial line.
    public var title: String
    /// True once the first line has ended, so the title will not change any more.
    public var titleIsComplete: Bool
    /// The story, with the allowed audio tags still in it.
    public var script: String

    /// The story as a person reads it on screen: no tags.
    public var readableScript: String { StorySanitizer.spokenText(script) }

    public init(title: String, titleIsComplete: Bool, script: String) {
        self.title = title
        self.titleIsComplete = titleIsComplete
        self.script = script
    }

    /// Splits the model output. The first non-empty line is the title.
    public static func parse(_ raw: String, streaming: Bool) -> StoryParts {
        let clean = streaming ? StorySanitizer.sanitizeStreaming(raw) : StorySanitizer.sanitize(raw)
        let text = clean.drop { $0.isNewline || $0.isWhitespace }
        guard !text.isEmpty else { return StoryParts(title: "", titleIsComplete: false, script: "") }
        guard let newline = text.firstIndex(of: "\n") else {
            return StoryParts(title: cleanTitle(String(text)), titleIsComplete: false, script: "")
        }
        let title = cleanTitle(String(text[..<newline]))
        let script = String(text[newline...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return StoryParts(title: title, titleIsComplete: true, script: script)
    }

    /// Drops a "Title:" label, quote marks and a closing full stop.
    static func cleanTitle(_ line: String) -> String {
        var title = line.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in ["title:", "название:", "título:", "titulo:"] where title.lowercased().hasPrefix(label) {
            title = String(title.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        }
        let quotes = CharacterSet(charactersIn: "\"'«»“”„‘’")
        if title.hasSuffix(".") { title.removeLast() }
        title = title.trimmingCharacters(in: quotes.union(.whitespaces))
        if title.hasSuffix(".") { title.removeLast() }
        return title.trimmingCharacters(in: quotes.union(.whitespaces))
    }
}

/// Collects the deltas of a streamed script and re-parses on each one.
public struct StoryStream: Sendable {
    public private(set) var raw = ""

    public init() {}

    public mutating func append(_ delta: String) { raw += delta }

    /// What to show now.
    public var live: StoryParts { StoryParts.parse(raw, streaming: true) }

    /// What to keep when the stream has ended.
    public var final: StoryParts { StoryParts.parse(raw, streaming: false) }
}
