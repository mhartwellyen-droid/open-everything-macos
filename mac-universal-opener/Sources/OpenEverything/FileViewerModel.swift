import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class FileViewerModel: ObservableObject {
    @Published var selectedURL: URL?
    @Published var showImporter = false
    @Published var loadError: String?
    @Published private(set) var recentURLs: [URL] = []

    func open(_ url: URL) {
        loadError = nil
        selectedURL = url
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        recentURLs = Array(recentURLs.prefix(12))
    }

    func revealInFinder() {
        guard let selectedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedURL])
    }

    func openWithDefaultApp() {
        guard let selectedURL else { return }
        NSWorkspace.shared.open(selectedURL)
    }
}

struct FileDetails {
    let name: String
    let path: String
    let size: String
    let modified: String
    let type: String
    let permissions: String

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .contentTypeKey
        ])
        name = url.lastPathComponent
        path = url.path
        size = ByteCountFormatter.string(
            fromByteCount: Int64(values?.fileSize ?? 0),
            countStyle: .file
        )
        if let date = values?.contentModificationDate {
            modified = date.formatted(date: .abbreviated, time: .shortened)
        } else {
            modified = "Unknown"
        }
        type = values?.contentType?.localizedDescription
            ?? values?.contentType?.identifier
            ?? "Unknown format"
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mode = attributes?[.posixPermissions] as? NSNumber
        permissions = mode.map { String(format: "%03o", $0.intValue) } ?? "Unknown"
    }
}