import Foundation

/// A style the storyteller can imitate: a brief for the writer and a delivery note for the voice.
///
/// A style imitates the devices of an author's manner (rhythm, tone, kind of humour), never
/// the author's texts and never a real person's voice. The briefs are written in our own
/// words. The prompt is English; the story itself comes out in the language the person picks.
public struct StylePreset: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: LocalizedText
    /// Rhythm, devices and tone, addressed to the writer.
    public let brief: String
    /// One or two sentences for the voice: pace, mood, how to deliver the twists. At most
    /// `StyleCatalog.maxDeliveryNoteLength` characters (the hub's `instructions` limit).
    public let deliveryNote: String

    public init(id: String, name: LocalizedText, brief: String, deliveryNote: String) {
        self.id = id
        self.name = name
        self.brief = brief
        self.deliveryNote = deliveryNote
    }
}

/// What a request carries once the person's choice is resolved.
public struct ResolvedStyle: Sendable, Hashable {
    public let id: String
    public let name: String
    public let brief: String
    public let deliveryNote: String

    public init(id: String, name: String, brief: String, deliveryNote: String) {
        self.id = id
        self.name = name
        self.brief = brief
        self.deliveryNote = deliveryNote
    }
}

/// The person's pick: a preset, or a few words of their own ("like a noir detective").
public enum StyleChoice: Sendable, Hashable {
    case preset(String)
    case custom(String)

    public static let `default` = StyleChoice.preset(StyleCatalog.defaultID)

    /// The style to write in, or nil for an unknown preset or an empty custom text.
    public func resolve(languageCode: String? = nil) -> ResolvedStyle? {
        switch self {
        case .preset(let id):
            guard let preset = StyleCatalog.preset(id: id) else { return nil }
            return ResolvedStyle(
                id: preset.id, name: preset.name.resolved(languageCode: languageCode),
                brief: preset.brief, deliveryNote: preset.deliveryNote)
        case .custom(let text):
            let clean = StyleCatalog.cleanCustom(text)
            guard !clean.isEmpty else { return nil }
            return ResolvedStyle(
                id: "custom", name: clean,
                brief: "Write in this manner: \(clean). Work out which rhythm, vocabulary and kind of humour or "
                    + "gravity a listener would expect from it, and use those devices in original sentences.",
                deliveryNote: String("Deliver it in this manner: \(clean). Natural, engaging, never robotic."
                    .prefix(StyleCatalog.maxDeliveryNoteLength)))
        }
    }
}

public enum StyleCatalog {
    /// The hub's limit for the voice `instructions` field.
    public static let maxDeliveryNoteLength = 300
    /// A free-text style is a phrase, not a second prompt.
    public static let maxCustomLength = 120
    public static let defaultID = "zhvanetsky"

    public static func preset(id: String) -> StylePreset? { all.first { $0.id == id } }

    /// Single line, trimmed, capped. Brackets and newlines are dropped so the text cannot
    /// pass for a second instruction block.
    public static func cleanCustom(_ text: String) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(flat.prefix(maxCustomLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static let all: [StylePreset] = [
        StylePreset(
            id: "zhvanetsky",
            name: LocalizedText(en: "Zhvanetsky", ru: "Жванецкий"),
            brief: "The manner of a satirical stage monologue from Odesa. Short, aphoristic lines. Paradox and "
                + "understatement. Humour from exact observation of ordinary people, queues, offices and habits. "
                + "A dry, rueful irony with warmth underneath. Set-up, a beat, then the twist, and the twist is "
                + "often one plain sentence. Rhetorical questions to the listener. Never explain the joke.",
            deliveryNote: "Dry, unhurried stage-monologue delivery with deadpan irony. A short pause before "
                + "each twist. Warm, a little weary, Odesa humour."),
        StylePreset(
            id: "dovlatov",
            name: LocalizedText(en: "Dovlatov", ru: "Довлатов"),
            brief: "A laconic, ironic first-person narrator. Short, clean sentences with no ornament. Deadpan "
                + "understatement and self-mockery. Stories told as anecdotes built on one telling detail. "
                + "The comic and the sad sit side by side. Paragraphs often close on a quiet punchline. "
                + "Plain words, exact nouns, almost no adjectives.",
            deliveryNote: "Quiet, even, conversational. Deadpan, as if telling a friend an anecdote over a "
                + "drink. Let the last line of each paragraph land softly."),
        StylePreset(
            id: "zoshchenko",
            name: LocalizedText(en: "Zoshchenko", ru: "Зощенко"),
            brief: "A comic skaz: the narrator is an earnest, half-educated everyman who retells events in "
                + "clumsy officialese mixed with street speech. Solemn tone about trivial matters. Comic "
                + "misuse of grand words. Absurd but airtight logic. A sudden moralising ending that misses "
                + "the point. Short paragraphs, plain syntax, the narrator never knows he is funny.",
            deliveryNote: "Earnest, slightly pompous everyman voice. Perfectly serious about silly things. "
                + "Brisk pace, a small beat before the moral."),
        StylePreset(
            id: "ilf-petrov",
            name: LocalizedText(en: "Ilf and Petrov", ru: "Ильф и Петров"),
            brief: "Sparkling picaresque satire. Vivid, unexpected similes. Ironic epithets. Exact absurd "
                + "detail. Quick comic sketches of characters in a line or two. A playful narrator who "
                + "comments on the action. Brisk adventure rhythm. Gentle parody of officialdom and slogans.",
            deliveryNote: "Bright, quick, mischievous. A raised eyebrow in the voice. Rapid in the sketches, "
                + "a brief pause before each comic simile."),
        StylePreset(
            id: "kharms",
            name: LocalizedText(en: "Kharms", ru: "Хармс"),
            brief: "An absurdist miniature. Impossible events told in a flat, matter-of-fact voice. Abrupt "
                + "non sequiturs. Scenes that break off with a deadpan \"and then\". Mathematical precision "
                + "applied to nonsense. Repeated structures. A sudden, unexplained ending. The absurdity lives "
                + "in the manner of telling and in invented side characters. Real facts in the story stay "
                + "true.",
            deliveryNote: "Flat, matter-of-fact, perfectly calm about impossible things. Abrupt stops. "
                + "A beat of silence before an odd ending."),
        StylePreset(
            id: "paustovsky",
            name: LocalizedText(en: "Paustovsky", ru: "Паустовский"),
            brief: "Lyrical, warm landscape prose. Light, colour, smell, weather and sound of a place. Long "
                + "flowing sentences that still breathe when read aloud, balanced by short ones. Tender "
                + "attention to craft, nature and ordinary people. Metaphors drawn from nature. Quiet, "
                + "reflective, unhurried, with a feeling of memory.",
            deliveryNote: "Soft, warm and unhurried. Lyrical phrasing, long breaths, gentle pauses between "
                + "images. Almost a murmur at the quiet moments."),
        StylePreset(
            id: "documentary",
            name: LocalizedText(en: "Documentary narrator", ru: "Диктор-документалист"),
            brief: "A calm, authoritative documentary narrator. Open with a vivid scene or a question, then "
                + "widen to the scale of the story. Clear, concrete facts in short sentences. Restrained "
                + "wonder. Pauses that let a fact sink in. Build toward one memorable closing image. Dramatic "
                + "but never breathless.",
            deliveryNote: "Calm, authoritative, resonant. Measured pace, deliberate pauses, quiet awe at "
                + "the big moments."),
        StylePreset(
            id: "bedtime",
            name: LocalizedText(en: "Bedtime story", ru: "Сказка на ночь"),
            brief: "A soothing bedtime story. Soft, simple words and gentle repetition. Warm, safe images. "
                + "A slow cadence like a lullaby. Nothing frightening. Occasional direct address to the "
                + "listener. Wind down toward the end: sentences get shorter and calmer, and the last line "
                + "is a quiet good night.",
            deliveryNote: "Slow, soft and soothing, almost a whisper. Long gentle pauses. Slow down even "
                + "more toward the end."),
    ]
}
