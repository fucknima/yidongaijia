import Foundation
import UIKit

struct MediaItem: Identifiable {
    enum Kind {
        case image
        case video
    }

    let url: URL
    let kind: Kind

    var id: URL { url }
    var fileName: String { url.lastPathComponent }

    var date: Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    var fileSizeText: String {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

/// Manages screenshots and recordings stored in the app sandbox Documents
/// directory so they stay visible in Files.app (UIFileSharingEnabled).
final class MediaLibrary: ObservableObject {
    static let shared = MediaLibrary()

    @Published private(set) var items: [MediaItem] = []

    private static let capturesSubdirectory = "AijiaMedia/Captures"
    private static let recordingsSubdirectory = "AijiaMedia/Recordings"

    static var capturesDirectory: URL {
        documentsDirectory.appendingPathComponent(capturesSubdirectory, isDirectory: true)
    }

    static var recordingsDirectory: URL {
        documentsDirectory.appendingPathComponent(recordingsSubdirectory, isDirectory: true)
    }

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private init() {
        ensureDirectories()
        reload()
    }

    func reload() {
        let captures = files(in: Self.capturesDirectory, extensions: ["png"])
        let recordings = files(in: Self.recordingsDirectory, extensions: ["mp4", "ts"])
        items = (captures + recordings).sorted { $0.date > $1.date }
    }

    func delete(_ item: MediaItem) {
        try? FileManager.default.removeItem(at: item.url)
        reload()
    }

    static func uniqueFileURL(in directory: URL, baseName: String, ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        var candidate = directory.appendingPathComponent("\(baseName)-\(stamp).\(ext)")
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(stamp)-\(index).\(ext)")
            index += 1
        }
        return candidate
    }

    private func ensureDirectories() {
        for directory in [Self.capturesDirectory, Self.recordingsDirectory] {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    private func files(in directory: URL, extensions: [String]) -> [MediaItem] {
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ) else {
            return []
        }

        return names.compactMap { name -> MediaItem? in
            let ext = (name as NSString).pathExtension.lowercased()
            guard extensions.contains(ext) else { return nil }
            let url = directory.appendingPathComponent(name)
            let kind: MediaItem.Kind = (ext == "mp4" || ext == "ts") ? .video : .image
            return MediaItem(url: url, kind: kind)
        }
    }
}
