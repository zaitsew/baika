import Foundation

/// One line of the conversation: who, what, and whether it is still being said.
public struct TalkLine: Sendable, Hashable, Identifiable {
    public enum Speaker: String, Sendable, Hashable { case person, storyteller }

    public var id: Int
    public var speaker: Speaker
    public var text: String
    /// True while deltas are still arriving for it, or, for the person's line, while its
    /// transcription has not come yet (`text` is empty then).
    public var partial: Bool
    /// The conversation item this line is, when the server named one.
    public var itemId: String?

    public init(id: Int, speaker: Speaker, text: String, partial: Bool = false, itemId: String? = nil) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.partial = partial
        self.itemId = itemId
    }
}

/// The conversation, folded from server events. Pure, so the folding (the one thing about a
/// transcript that can be subtly wrong) is tested without a socket. It lives for the length of
/// the conversation and is never saved.
public struct TalkTranscript: Sendable, Hashable {
    /// Lines kept. A long conversation does not grow without bound.
    public static let maxLines = 60

    public private(set) var lines: [TalkLine] = []
    private var next = 1
    /// The answer was cut short by the person: its late words are not added until the next one.
    private var discardingAnswer = false
    /// The line the answer in progress is being written to. Nil until its first word, so a cut
    /// before that cannot touch the previous answer.
    private var answerLineID: Int?

    public init() {}

    public mutating func apply(_ event: RealtimeServerEvent) {
        switch event {
        case .committed(let itemId):
            // The question exists before its words do: the transcription runs beside the model
            // and can land after a short answer is over. A line is held for it at the moment
            // the question was asked, so the words read above the answer wherever they arrive.
            guard !lines.contains(where: { $0.speaker == .person && $0.itemId == itemId }) else { return }
            lines.append(TalkLine(id: take(), speaker: .person, text: "", partial: true, itemId: itemId))
        case .heard(let itemId, let text):
            if let itemId, let i = lines.firstIndex(where: { $0.speaker == .person && $0.itemId == itemId }) {
                if let clean = text.nonBlank {
                    lines[i].text = clean
                    lines[i].partial = false
                } else {
                    lines.remove(at: i)
                }
                return
            }
            // No held line: the words go before the storyteller line still being said, so the
            // question reads above its answer, and at the end otherwise.
            guard let clean = text.nonBlank else { return }
            let line = TalkLine(id: take(), speaker: .person, text: clean, itemId: itemId)
            if let i = lines.lastIndex(where: { $0.speaker == .storyteller && $0.partial }) {
                lines.insert(line, at: i)
            } else {
                lines.append(line)
            }
        case .transcriptionFailed(let itemId):
            if let itemId {
                lines.removeAll { $0.speaker == .person && $0.itemId == itemId && $0.text.nonBlank == nil }
            }
        case .answerItem:
            discardingAnswer = false
            answerLineID = nil
        case .sayingDelta(let delta):
            if discardingAnswer { break }
            if let i = lines.lastIndex(where: { $0.speaker == .storyteller && $0.partial }) {
                lines[i].text += delta
                answerLineID = lines[i].id
            } else if !delta.isEmpty {
                let id = take()
                lines.append(TalkLine(id: id, speaker: .storyteller, text: delta, partial: true))
                answerLineID = id
            }
        case .said(let whole):
            if discardingAnswer { break }
            if let i = lines.lastIndex(where: { $0.speaker == .storyteller && $0.partial }) {
                if let clean = whole.nonBlank { lines[i].text = clean }
                lines[i].partial = false
                answerLineID = lines[i].id
                if lines[i].text.nonBlank == nil { lines.remove(at: i) }
            } else if let clean = whole.nonBlank {
                let id = take()
                lines.append(TalkLine(id: id, speaker: .storyteller, text: clean))
                answerLineID = id
            }
        case .responseDone:
            // An answer cut short keeps the words that were said and stops being partial.
            if let i = lines.lastIndex(where: { $0.speaker == .storyteller && $0.partial }) {
                lines[i].partial = false
                if lines[i].text.nonBlank == nil { lines.remove(at: i) }
            }
        default:
            break
        }
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
    }

    /// The person talked over the answer and `fraction` (0...1) of its audio had been played. The
    /// storyteller's last line keeps that share of its words, cut on a word boundary, so what the
    /// transcript says is what was heard. Words that arrive late for that answer are dropped.
    public mutating func keepHeard(fraction: Double) {
        discardingAnswer = true
        guard let id = answerLineID, let i = lines.firstIndex(where: { $0.id == id }) else { return }
        let words = lines[i].text.split(separator: " ", omittingEmptySubsequences: true)
        let keep = Int((Double(words.count) * min(max(fraction, 0), 1)).rounded(.down))
        lines[i].text = words.prefix(keep).joined(separator: " ")
        lines[i].partial = false
        if lines[i].text.nonBlank == nil { lines.remove(at: i) }
    }

    private mutating func take() -> Int {
        defer { next += 1 }
        return next
    }

    /// Lines with words in them, in order.
    public var spoken: [TalkLine] { lines.filter { $0.text.nonBlank != nil } }

    /// The person has said something that was understood.
    public var hasPersonSpeech: Bool { lines.contains { $0.speaker == .person && $0.text.nonBlank != nil } }

    /// The last sentence the storyteller said or is saying, for the one line under the orb.
    public var caption: String { TalkCaption.lastSentence(of: lines.last { $0.speaker == .storyteller }?.text ?? "") }
}

/// The caption under the orb: the last sentence of the storyteller's last line, short enough for
/// three lines of large type.
public enum TalkCaption {
    public static let maxLength = 140

    public static func lastSentence(of text: String, maxLength: Int = TalkCaption.maxLength) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return "" }
        let enders: Set<Character> = [".", "!", "?", "\u{2026}"]
        // Drop the closing punctuation, then find the end of the sentence before it.
        var body = Substring(flat)
        while let last = body.last, enders.contains(last) || last == "\"" || last == "\u{BB}" { body = body.dropLast() }
        let start = body.lastIndex { enders.contains($0) }.map { body.index(after: $0) } ?? body.startIndex
        let sentence = flat[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        let result = sentence.isEmpty ? flat : sentence
        guard result.count > maxLength else { return result }
        // Too long: keep the end, cut on a word boundary.
        let tail = String(result.suffix(maxLength))
        if let space = tail.firstIndex(of: " ") { return "\u{2026}" + tail[tail.index(after: space)...] }
        return "\u{2026}" + tail
    }
}

/// The topic handed to Perform when the person taps "Perform this".
public enum TalkTopic {
    /// The person's own words, newest last, as many of the latest as fit `maxLength`
    /// (`StoryPrompt.maxTopicLength`). Fillers of one word ("yes", "ok") are left out. Nil when
    /// nothing substantial was said.
    public static func derive(from lines: [TalkLine], maxLength: Int = StoryPrompt.maxTopicLength) -> String? {
        let said = lines.compactMap { line -> String? in
            guard line.speaker == .person, let text = line.text.nonBlank else { return nil }
            return text.split(whereSeparator: \.isWhitespace).count >= 2 ? text : nil
        }
        var kept: [String] = []
        var length = 0
        for text in said.reversed() {
            let extra = text.count + (kept.isEmpty ? 0 : 1)
            if length + extra > maxLength {
                // Even the newest line may be over the limit: cut it rather than return nothing.
                if kept.isEmpty { kept.append(String(text.prefix(maxLength))) }
                break
            }
            kept.append(text)
            length += extra
        }
        guard !kept.isEmpty else { return nil }
        return kept.reversed().joined(separator: " ")
    }
}
