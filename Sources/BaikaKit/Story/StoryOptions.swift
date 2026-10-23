import Foundation

/// A short text in the two interface languages. The story language is a separate choice
/// (`StoryLanguage`); this is only for names and descriptions shown in the app.
public struct LocalizedText: Sendable, Hashable {
    public let en: String
    public let ru: String

    public init(en: String, ru: String) {
        self.en = en
        self.ru = ru
    }

    /// Russian for a Russian device, English for everything else.
    public func resolved(languageCode: String?) -> String {
        languageCode == "ru" ? ru : en
    }
}

/// The language the story is written and narrated in.
public enum StoryLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case ru, en, es

    public static let `default` = StoryLanguage.ru

    public var id: String { rawValue }

    /// How the language names itself: the label on the picker.
    public var nativeName: String {
        switch self {
        case .ru: "Русский"
        case .en: "English"
        case .es: "Español"
        }
    }

    /// The name used inside the prompt, which is written in English.
    public var promptName: String {
        switch self {
        case .ru: "Russian"
        case .en: "English"
        case .es: "Spanish"
        }
    }

    /// ISO 639-1, the `language_code` the narration endpoint takes.
    public var code: String { rawValue }
}

/// How long the story runs when read aloud: 2, 4 or 7 minutes at about 150 spoken words a minute.
public enum StoryLength: Int, CaseIterable, Codable, Sendable, Identifiable {
    case short = 2
    case medium = 4
    case long = 7

    public static let `default` = StoryLength.medium

    /// A calm narrator reads about this many words a minute.
    public static let wordsPerMinute = 150

    public var id: Int { rawValue }
    public var minutes: Int { rawValue }
    public var wordTarget: Int { rawValue * Self.wordsPerMinute }
}
