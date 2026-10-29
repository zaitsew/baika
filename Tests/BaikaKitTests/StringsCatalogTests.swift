import Foundation
import Testing

/// scripts/make-strings.py is the source of the Russian copy. It once fell 19 keys behind the
/// committed catalogs because later PRs edited them by hand, and running it would have wiped
/// the Talk strings. This runs the generator into a temp directory and compares each catalog
/// byte for byte with the committed one.
@Suite("Strings catalogs")
struct StringsCatalogTests {
    static let catalogs = ["Localizable.xcstrings", "InfoPlist.xcstrings", "AppShortcuts.xcstrings"]

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func theGeneratorReproducesTheCommittedCatalogs() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("baika-strings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: out) }

        let run = Process()
        run.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        run.arguments = ["python3", Self.repoRoot.appendingPathComponent("scripts/make-strings.py").path, out.path]
        run.standardOutput = Pipe()
        let errors = Pipe()
        run.standardError = errors
        try run.run()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        run.waitUntilExit()
        #expect(run.terminationStatus == 0, "make-strings.py failed: \(String(decoding: stderr, as: UTF8.self))")

        for name in Self.catalogs {
            let committed = try Data(contentsOf: Self.repoRoot.appendingPathComponent("App/\(name)"))
            let generated = try Data(contentsOf: out.appendingPathComponent(name))
            #expect(generated == committed,
                    "App/\(name) differs from what scripts/make-strings.py generates; run scripts/make-strings.py")
        }
    }
}
