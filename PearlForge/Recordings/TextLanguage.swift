import Foundation
import NaturalLanguage

/// Which language a piece of text is in, worked out on the phone (no AI, no
/// cost), so the library can label pearls in other languages and show their
/// English versions.
enum TextLanguage {
    /// The language you read: library titles and English versions use it.
    static let yours = "en"

    private static let cache = NSCache<NSString, NSString>()

    /// The text's language code ("fr", "ko", "zh"), or nil when it's too
    /// short or mixed to tell.
    static func code(of text: String) -> String? {
        let sample = String(text.prefix(400))
        guard !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let known = cache.object(forKey: sample as NSString) {
            return known.length == 0 ? nil : known as String
        }
        // "zh-Hans" and "zh-Hant" are both Chinese here.
        let code = NLLanguageRecognizer.dominantLanguage(for: sample)
            .map { String($0.rawValue.prefix { $0 != "-" }) }
        cache.setObject((code ?? "") as NSString, forKey: sample as NSString)
        return code
    }

    /// The text's language when it isn't yours: "Korean", "French".
    static func other(in text: String) -> String? {
        guard let code = code(of: text), code != yours else { return nil }
        return name(of: code)
    }

    static func isOther(_ text: String) -> Bool {
        other(in: text) != nil
    }

    /// "Korean" for "ko".
    static func name(of code: String) -> String {
        SpeechLanguages.named(code)?.name
            ?? Locale(identifier: yours).localizedString(forLanguageCode: code)
            ?? code
    }
}
