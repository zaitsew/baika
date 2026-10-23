import Foundation

/// The mp3 chunks of each story, one folder per story in Application Support.
public struct AudioCache: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `Application Support/Baika/Stories`.
    public static func standard() -> AudioCache {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return AudioCache(root: base.appendingPathComponent("Baika", isDirectory: true)
            .appendingPathComponent("Stories", isDirectory: true))
    }

    /// `chunk-000.mp3`, the name kept in the library record.
    public static func fileName(forChunk index: Int) -> String {
        String(format: "chunk-%03d.mp3", index)
    }

    public static func fileNames(count: Int) -> [String] {
        (0..<max(count, 0)).map(fileName(forChunk:))
    }

    public func directory(for storyID: UUID) -> URL {
        root.appendingPathComponent(storyID.uuidString, isDirectory: true)
    }

    public func url(for storyID: UUID, fileName: String) -> URL {
        directory(for: storyID).appendingPathComponent(fileName)
    }

    /// Writes a chunk and returns its file name.
    @discardableResult
    public func write(_ data: Data, storyID: UUID, chunkIndex: Int) throws -> String {
        let directory = directory(for: storyID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = Self.fileName(forChunk: chunkIndex)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    public func exists(storyID: UUID, fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: storyID, fileName: fileName).path)
    }

    /// Positions in `fileNames` whose file is not on disk.
    public func missingChunks(storyID: UUID, fileNames: [String]) -> [Int] {
        fileNames.indices.filter { !exists(storyID: storyID, fileName: fileNames[$0]) }
    }

    public func removeStory(_ storyID: UUID) throws {
        let directory = directory(for: storyID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    public func removeAll() throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }
}
