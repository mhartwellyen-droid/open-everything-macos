import AppKit
import Foundation
import SwiftUI

struct ArchiveBrowserView: View {
    static let supportedExtensions: Set<String> = [
        "7z", "bz2", "gz", "rar", "tar", "tbz", "tbz2", "tgz",
        "txz", "xz", "zip"
    ]

    let url: URL
    @StateObject private var model: ArchiveBrowserModel

    init(url: URL) {
        self.url = url
        _model = StateObject(
            wrappedValue: ArchiveBrowserModel(archiveURL: url)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Extract All to a Folder…") {
                    model.chooseDestinationAndExtract()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.loading || model.extracting)
                .help("Safely extracts every archive entry into a folder you choose")
            }
            .padding()

            Divider()

            if model.loading {
                Spacer()
                ProgressView("Reading archive contents…")
                Spacer()
            } else if let error = model.errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("Couldn’t Read Archive")
                        .font(.title3.weight(.semibold))
                    Text(error)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                Spacer()
            } else if model.entries.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("Archive Is Empty")
                        .font(.title3.weight(.semibold))
                    Text("No files or folders were found.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(model.entries, id: \.self) { entry in
                    Label {
                        Text(entry)
                            .textSelection(.enabled)
                    } icon: {
                        Image(
                            systemName: entry.hasSuffix("/")
                                ? "folder"
                                : "doc"
                        )
                    }
                }
            }

            if model.extracting || model.statusMessage != nil {
                Divider()
                HStack(spacing: 10) {
                    if model.extracting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(
                        model.statusMessage
                            ?? "Extracting archive contents…"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
            }
        }
        .task {
            await model.load()
        }
    }
}

@MainActor
final class ArchiveBrowserModel: ObservableObject {
    @Published var entries: [String] = []
    @Published var loading = true
    @Published var extracting = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    let archiveURL: URL

    init(archiveURL: URL) {
        self.archiveURL = archiveURL
    }

    var summary: String {
        if loading {
            return "Reading contents"
        }
        if entries.count == 1 {
            return "1 item"
        }
        return "\(entries.count) items"
    }

    func load() async {
        loading = true
        errorMessage = nil
        do {
            entries = try await ArchiveService.list(archiveURL)
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func chooseDestinationAndExtract() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder for Extracted Files"
        panel.prompt = "Extract Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        extracting = true
        statusMessage = "Extracting safely to \(destination.lastPathComponent)…"
        Task {
            do {
                try await ArchiveService.extract(
                    archiveURL,
                    to: destination
                )
                extracting = false
                statusMessage = "Extraction finished."
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                extracting = false
                statusMessage = "Extraction failed: \(error.localizedDescription)"
            }
        }
    }
}

enum ArchiveService {
    static func list(_ archiveURL: URL) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let fileExtension = archiveURL.pathExtension.lowercased()
            var result = run(
                executable: "/usr/bin/tar",
                arguments: ["-tf", archiveURL.path]
            )

            if result.status != 0 && fileExtension == "zip" {
                result = run(
                    executable: "/usr/bin/unzip",
                    arguments: ["-Z1", archiveURL.path]
                )
            }

            if result.status != 0,
               ["gz", "bz2", "xz"].contains(fileExtension) {
                let name = archiveURL.deletingPathExtension()
                    .lastPathComponent
                return [name]
            }

            guard result.status == 0 else {
                throw ArchiveError.commandFailed(
                    readableError(
                        result.error,
                        fallback:
                            "This archive may be encrypted, damaged, or use a method unavailable in this macOS version."
                    )
                )
            }

            let entries = result.output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.isEmpty }
            try validate(entries)
            return entries
        }.value
    }

    static func extract(
        _ archiveURL: URL,
        to destination: URL
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let entries = try listSynchronously(archiveURL)
            try validate(entries)

            let fileExtension = archiveURL.pathExtension.lowercased()
            var result = run(
                executable: "/usr/bin/tar",
                arguments: [
                    "-xf", archiveURL.path,
                    "-C", destination.path
                ]
            )

            if result.status != 0 && fileExtension == "zip" {
                result = run(
                    executable: "/usr/bin/ditto",
                    arguments: [
                        "-x", "-k", archiveURL.path, destination.path
                    ]
                )
            }

            if result.status != 0,
               ["gz", "bz2", "xz"].contains(fileExtension) {
                try decompressSingleFile(
                    archiveURL,
                    to: destination,
                    fileExtension: fileExtension
                )
                return
            }

            guard result.status == 0 else {
                throw ArchiveError.commandFailed(
                    readableError(
                        result.error,
                        fallback:
                            "macOS could not extract this archive. It may be encrypted, damaged, or use an unsupported compression method."
                    )
                )
            }
        }.value
    }

    private static func listSynchronously(
        _ archiveURL: URL
    ) throws -> [String] {
        let fileExtension = archiveURL.pathExtension.lowercased()
        var result = run(
            executable: "/usr/bin/tar",
            arguments: ["-tf", archiveURL.path]
        )
        if result.status != 0 && fileExtension == "zip" {
            result = run(
                executable: "/usr/bin/unzip",
                arguments: ["-Z1", archiveURL.path]
            )
        }
        if result.status != 0,
           ["gz", "bz2", "xz"].contains(fileExtension) {
            return [
                archiveURL.deletingPathExtension().lastPathComponent
            ]
        }
        guard result.status == 0 else {
            throw ArchiveError.commandFailed(
                readableError(
                    result.error,
                    fallback: "The archive contents could not be read."
                )
            )
        }
        return result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func validate(_ entries: [String]) throws {
        for entry in entries {
            let normalized = entry.replacingOccurrences(
                of: "\\",
                with: "/"
            )
            let components = normalized.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            if normalized.hasPrefix("/")
                || components.contains(where: { $0 == ".." }) {
                throw ArchiveError.unsafePath(entry)
            }
        }
    }

    private static func decompressSingleFile(
        _ archiveURL: URL,
        to destination: URL,
        fileExtension: String
    ) throws {
        let tool: String
        switch fileExtension {
        case "gz":
            tool = "/usr/bin/gzip"
        case "bz2":
            tool = "/usr/bin/bzip2"
        default:
            tool = "/usr/bin/xz"
        }
        guard FileManager.default.isExecutableFile(atPath: tool) else {
            throw ArchiveError.commandFailed(
                "This macOS installation does not include the \(fileExtension.uppercased()) decompression tool."
            )
        }

        let outputURL = destination.appendingPathComponent(
            archiveURL.deletingPathExtension().lastPathComponent
        )
        FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil
        )
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["-dc", archiveURL.path]
        process.standardOutput = outputHandle
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            let errorData =
                errorPipe.fileHandleForReading.readDataToEndOfFile()
            throw ArchiveError.commandFailed(
                readableError(
                    String(decoding: errorData, as: UTF8.self),
                    fallback: "The compressed file could not be expanded."
                )
            )
        }
    }

    private static func run(
        executable: String,
        arguments: [String]
    ) -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            let output =
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let error =
                errorPipe.fileHandleForReading.readDataToEndOfFile()
            return CommandResult(
                status: process.terminationStatus,
                output: String(decoding: output, as: UTF8.self),
                error: String(decoding: error, as: UTF8.self)
            )
        } catch {
            return CommandResult(
                status: -1,
                output: "",
                error: error.localizedDescription
            )
        }
    }

    private static func readableError(
        _ message: String,
        fallback: String
    ) -> String {
        let trimmed = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? fallback : trimmed
    }

    private struct CommandResult {
        let status: Int32
        let output: String
        let error: String
    }

    enum ArchiveError: LocalizedError {
        case commandFailed(String)
        case unsafePath(String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let message):
                return message
            case .unsafePath(let path):
                return "Extraction was blocked because the archive contains an unsafe path: \(path)"
            }
        }
    }
}