import AVFoundation
import Foundation

/// Reading and joining the mp3 chunks of a story.
enum AudioTools {
    /// Total length of the files, in seconds. A file that cannot be read counts as zero.
    static func totalDuration(of urls: [URL]) async -> TimeInterval {
        var total = 0.0
        for url in urls {
            if let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite {
                total += seconds
            }
        }
        return total
    }

    enum MergeError: Error { case noAudio, exportFailed }

    /// Joins the chunks into one .m4a in the temporary folder, for the share sheet.
    static func mergeToM4A(_ urls: [URL], name: String) async throws -> URL {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MergeError.exportFailed }
        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            let length = try await asset.load(.duration)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: cursor)
            cursor = CMTimeAdd(cursor, length)
        }
        guard cursor > .zero else { throw MergeError.noAudio }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
        else { throw MergeError.exportFailed }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeFileName(name)).m4a")
        try? FileManager.default.removeItem(at: output)
        try await export.export(to: output, as: .m4a)
        return output
    }

    static func safeFileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|\n")).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Baika story" : String(cleaned.prefix(60))
    }
}
