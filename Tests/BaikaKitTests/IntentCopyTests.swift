import Foundation
import Testing

/// Apple refuses an upload whose App Intent copy names a device or an Apple product
/// (ITMS-90626, Baika 0.1.0 build 2: "cannot contain 'iphone'"). The intents live in the app
/// target, which the package tests cannot import, so this reads the source and checks every
/// string literal. Comment lines are skipped: only text that ships is checked.
@Suite("App Intent copy")
struct IntentCopyTests {
    static var forbidden: Regex<(Substring, Substring)> {
        #/\b(iphone|ipad|apple watch|siri|apple)\b/#.ignoresCase()
    }

    /// Every string literal on a non-comment line.
    static func literals(in source: String) -> [String] {
        let literal = #/"(?:[^"\\]|\\.)*"/#
        return source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .flatMap { line in line.matches(of: literal).map { String($0.output) } }
    }

    static func intentSources() throws -> [URL] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Intents")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
    }

    @Test func noIntentStringNamesADeviceOrAnAppleProduct() throws {
        let files = try Self.intentSources()
        #expect(!files.isEmpty, "App/Intents has no Swift files; the path moved")
        for file in files {
            let found = Self.literals(in: try String(contentsOf: file, encoding: .utf8))
            #expect(!found.isEmpty, "\(file.lastPathComponent): no string literals found")
            for text in found where text.firstMatch(of: Self.forbidden) != nil {
                Issue.record("\(file.lastPathComponent) has a string Apple refuses (ITMS-90626): \(text)")
            }
        }
    }

    @Test func theCheckCatchesTheWordsAsWholeWordsOnly() {
        for bad in ["on this iPhone", "Your IPAD", "an Apple Watch", "ask Siri", "Apple"] {
            #expect(bad.firstMatch(of: Self.forbidden) != nil, "\(bad)")
        }
        for good in ["\\(.applicationName)", "Play offline", "pineapple"] {
            #expect(good.firstMatch(of: Self.forbidden) == nil, "\(good)")
        }
        #expect(Self.literals(in: "// \"iPhone\"\nlet a = \"x\"") == ["\"x\""])
    }
}
