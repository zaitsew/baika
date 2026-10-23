import Foundation

/// The person's yes to sending their topic to the AI providers (App Store guideline 5.1.2(i)).
///
/// The topic goes to Anthropic (the text) and to ElevenLabs or OpenAI (the voice), through the
/// Fabrique accounts hub. The version moves when the wording or the provider list changes, so
/// an old yes does not carry over.
public enum AIConsent {
    public static let currentVersion = 1
    static let key = "baika.aiConsentVersion"

    public static func isGiven(in defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: key) >= currentVersion
    }

    public static func set(_ given: Bool, in defaults: UserDefaults = .standard) {
        if given {
            defaults.set(currentVersion, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
