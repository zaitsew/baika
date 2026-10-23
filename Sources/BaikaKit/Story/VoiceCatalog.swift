import Foundation

/// A narrator voice from the ElevenLabs library.
///
/// Every voice here is an original library voice, never a clone of a real person: ElevenLabs
/// forbids cloning without consent, and Baika imitates an author's text style, not a voice.
public struct Voice: Identifiable, Sendable, Hashable {
    /// Our own slug, stable across catalogue changes. Saved stories keep the name, not this.
    public let id: String
    public let name: String
    /// The ElevenLabs `voice_id` sent to the hub.
    public let voiceID: String
    public let summary: LocalizedText
    /// True when the id was read back from ElevenLabs' public voice list (see `VoiceCatalog`).
    public let confirmed: Bool

    public init(id: String, name: String, voiceID: String, summary: LocalizedText, confirmed: Bool) {
        self.id = id
        self.name = name
        self.voiceID = voiceID
        self.summary = summary
        self.confirmed = confirmed
    }
}

/// The narrators offered on the Perform screen.
///
/// Confirmed: on 2026-10-23 `GET https://api.elevenlabs.io/v1/voices` (public, no key) listed
/// each id below with category `premade` and the name beside it. They are English-native
/// voices; on `eleven_v3` they speak Russian and Spanish with an accent, which the
/// descriptions say. A voice whose id could not be confirmed would carry `confirmed: false`;
/// the catalogue test fails the build for an unconfirmed voice that ships by accident.
public enum VoiceCatalog {
    public static let defaultID = "george"

    public static func voice(id: String) -> Voice? { all.first { $0.id == id } }

    public static var `default`: Voice { voice(id: defaultID) ?? all[0] }

    public static let all: [Voice] = [
        Voice(
            id: "george", name: "George", voiceID: "JBFqnCBsd6RMkjVDRZzb",
            summary: LocalizedText(
                en: "Warm, captivating storyteller. British, middle-aged.",
                ru: "Тёплый рассказчик, который держит внимание. Британец, средних лет."),
            confirmed: true),
        Voice(
            id: "brian", name: "Brian", voiceID: "nPczCjzI2devNBz1zQrb",
            summary: LocalizedText(
                en: "Deep, resonant and comforting. American, middle-aged.",
                ru: "Глубокий, объёмный, успокаивающий. Американец, средних лет."),
            confirmed: true),
        Voice(
            id: "bill", name: "Bill", voiceID: "pqHfZKP75CvOlQylNhV4",
            summary: LocalizedText(
                en: "Wise, mature, balanced. American, older.",
                ru: "Мудрый, зрелый, уравновешенный. Американец, постарше."),
            confirmed: true),
        Voice(
            id: "daniel", name: "Daniel", voiceID: "onwK4e9ZLuTAKqWW03F9",
            summary: LocalizedText(
                en: "Steady broadcaster. British, formal.",
                ru: "Ровный диктор. Британец, строгий тон."),
            confirmed: true),
        Voice(
            id: "lily", name: "Lily", voiceID: "pFZP5JQG7iQjIQuC4Bku",
            summary: LocalizedText(
                en: "Velvety actress. British, confident.",
                ru: "Бархатный голос актрисы. Британка, уверенная."),
            confirmed: true),
        Voice(
            id: "alice", name: "Alice", voiceID: "Xb7hH8MSUJpSbSDYk0k2",
            summary: LocalizedText(
                en: "Clear, engaging educator. British.",
                ru: "Ясная, увлекающая рассказчица. Британка."),
            confirmed: true),
    ]
}
