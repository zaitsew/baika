import Foundation

/// One request to the narration endpoint.
public struct NarrationChunk: Sendable, Hashable, Identifiable {
    public let index: Int
    /// The text to speak, audio tags included.
    public let text: String
    /// The end of the chunk before, for continuity of voice. At most `contextLength` characters.
    public let previousText: String?
    /// The start of the chunk after.
    public let nextText: String?

    public var id: Int { index }

    public init(index: Int, text: String, previousText: String?, nextText: String?) {
        self.index = index
        self.text = text
        self.previousText = previousText
        self.nextText = nextText
    }
}

/// Splits a script into chunks the narration endpoint takes (at most 2500 characters each).
///
/// Boundaries are chosen in this order: between paragraphs, then between sentences, then at a
/// space. The first chunk is deliberately short (about 900 characters, roughly a minute of
/// audio) so playback starts fast; the rest fill up to the limit. Lengths are UTF-16 units,
/// which is how the hub counts `input`.
public struct NarrationChunker: Sendable {
    public static let defaultMaxLength = 2500
    public static let defaultFirstChunkLength = 900
    public static let defaultContextLength = 300

    public let maxLength: Int
    public let firstChunkLength: Int
    public let contextLength: Int

    public init(
        maxLength: Int = defaultMaxLength,
        firstChunkLength: Int = defaultFirstChunkLength,
        contextLength: Int = defaultContextLength
    ) {
        precondition(maxLength > 0 && firstChunkLength > 0 && contextLength >= 0)
        self.maxLength = maxLength
        self.firstChunkLength = min(firstChunkLength, maxLength)
        self.contextLength = contextLength
    }

    public func chunks(for script: String) -> [NarrationChunk] {
        let texts = split(script)
        return texts.indices.map { index in
            NarrationChunk(
                index: index,
                text: texts[index],
                previousText: index > 0 ? Self.tail(of: texts[index - 1], limit: contextLength) : nil,
                nextText: index + 1 < texts.count ? Self.head(of: texts[index + 1], limit: contextLength) : nil)
        }
    }

    // MARK: Splitting

    func split(_ script: String) -> [String] {
        let paragraphs = script
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""
        func limit() -> Int { chunks.isEmpty ? firstChunkLength : maxLength }
        func flush() {
            if !current.isEmpty { chunks.append(current) }
            current = ""
        }
        func fits(_ text: String, joiner: String) -> Bool {
            current.isEmpty || Self.length(current) + Self.length(joiner) + Self.length(text) <= limit()
        }
        func add(_ text: String, joiner: String) {
            current = current.isEmpty ? text : current + joiner + text
        }

        for paragraph in paragraphs {
            // A paragraph that opens an empty chunk must fit that chunk's limit too, so a long
            // first paragraph is cut into sentences and the first chunk stays short.
            let fitsHere = current.isEmpty
                ? Self.length(paragraph) <= limit()
                : Self.length(current) + 2 + Self.length(paragraph) <= limit()
            if fitsHere {
                add(paragraph, joiner: "\n\n")
                continue
            }
            // Prefer to move the whole paragraph to the next chunk, if it fits there.
            if !current.isEmpty, Self.length(paragraph) <= maxLength {
                flush()
                add(paragraph, joiner: "\n\n")
                continue
            }
            // Otherwise pack it sentence by sentence.
            var first = true
            for sentence in sentences(of: paragraph) {
                let joiner = first ? "\n\n" : " "
                if !fits(sentence, joiner: joiner) { flush() }
                add(sentence, joiner: joiner)
                first = false
            }
        }
        flush()
        return chunks
    }

    /// Sentences of one paragraph, each at most `maxLength`: a longer one is cut at a space.
    func sentences(of paragraph: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(paragraph)
        var i = 0
        while i < characters.count {
            current.append(characters[i])
            if Self.isTerminator(characters[i]) {
                // Swallow a run of terminators and closing quotes: "?!", "...", "»".
                while i + 1 < characters.count, Self.isTerminator(characters[i + 1]) || Self.isCloser(characters[i + 1]) {
                    i += 1
                    current.append(characters[i])
                }
                if i + 1 >= characters.count || characters[i + 1].isWhitespace {
                    result.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            }
            i += 1
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result.flatMap { Self.length($0) <= maxLength ? [$0] : hardSplit($0) }
    }

    /// A sentence longer than `maxLength`: cut at the last space inside the limit.
    func hardSplit(_ text: String) -> [String] {
        var pieces: [String] = []
        var rest = Substring(text)
        while Self.length(String(rest)) > maxLength {
            var used = 0
            var cut = rest.startIndex
            var lastSpace: String.Index?
            var index = rest.startIndex
            while index < rest.endIndex {
                let width = rest[index].utf16.count
                if used + width > maxLength { break }
                used += width
                if rest[index] == " " { lastSpace = index }
                index = rest.index(after: index)
                cut = index
            }
            // A single grapheme wider than the limit still has to move forward.
            var end = lastSpace ?? cut
            if end == rest.startIndex { end = rest.index(after: rest.startIndex) }
            pieces.append(String(rest[..<end]).trimmingCharacters(in: .whitespaces))
            rest = rest[end...].drop { $0 == " " }
        }
        let tail = String(rest).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces
    }

    // MARK: Context

    /// The end of `text`, at most `limit` units, starting at a word.
    static func tail(of text: String, limit: Int) -> String? {
        guard limit > 0, !text.isEmpty else { return nil }
        guard length(text) > limit else { return text }
        var used = 0
        var start = text.endIndex
        while start > text.startIndex {
            let previous = text.index(before: start)
            let width = text[previous].utf16.count
            if used + width > limit { break }
            used += width
            start = previous
        }
        var piece = text[start...]
        // Cut mid-word: start at the next space.
        if start > text.startIndex, !text[text.index(before: start)].isWhitespace, let space = piece.firstIndex(of: " ") {
            piece = piece[piece.index(after: space)...]
        }
        let result = String(piece).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// The start of `text`, at most `limit` units, ending at a word.
    static func head(of text: String, limit: Int) -> String? {
        guard limit > 0, !text.isEmpty else { return nil }
        guard length(text) > limit else { return text }
        var used = 0
        var end = text.startIndex
        while end < text.endIndex {
            let width = text[end].utf16.count
            if used + width > limit { break }
            used += width
            end = text.index(after: end)
        }
        var piece = text[..<end]
        if end < text.endIndex, !text[end].isWhitespace, let space = piece.lastIndex(of: " ") {
            piece = piece[..<space]
        }
        let result = String(piece).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    // MARK: Helpers

    static func length(_ text: String) -> Int { text.utf16.count }
    static func isTerminator(_ c: Character) -> Bool { c == "." || c == "!" || c == "?" || c == "…" }
    static func isCloser(_ c: Character) -> Bool { "\"'»”’)]".contains(c) }
}
