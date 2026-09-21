import AppKit
import Darwin
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
    static let diagnosticCaptureLimit = 256 * 1024
    private static let commandTimeout: TimeInterval = 30
    typealias CommandRunner = (
        _ executable: String,
        _ arguments: [String],
        _ timeout: TimeInterval,
        _ standardOutput: URL?
    ) -> CommandResult

    static func list(
        _ archiveURL: URL,
        runner: @escaping CommandRunner = run
    ) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let fileExtension = archiveURL.pathExtension.lowercased()
            if ["gz", "bz2", "xz"].contains(fileExtension) {
                return [
                    archiveURL.deletingPathExtension().lastPathComponent
                ]
            }

            var result = invoke(
                executable: "/usr/bin/tar",
                arguments: ["-tf", archiveURL.path],
                runner: runner
            )

            if result.status != 0 && fileExtension == "zip" {
                result = invoke(
                    executable: "/usr/bin/unzip",
                    arguments: ["-Z1", archiveURL.path],
                    runner: runner
                )
            }

            guard result.status == 0 else {
                throw ArchiveError.commandFailed(
                    archiveFailureMessage(
                        action: "read",
                        detail: result.error
                    )
                )
            }

            let entries = result.output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.isEmpty }
            try validate(entries)
            try validateLinks(in: archiveURL, entries: entries, runner: runner)
            return entries
        }.value
    }

    static func extract(
        _ archiveURL: URL,
        to destination: URL,
        runner: @escaping CommandRunner = run
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let entries = try listSynchronously(archiveURL, runner: runner)
            try validate(entries)

            let fileExtension = archiveURL.pathExtension.lowercased()
            if ["gz", "bz2", "xz"].contains(fileExtension) {
                try decompressSingleFile(
                    archiveURL,
                    to: destination,
                    runner: runner
                )
                return
            }

            try validateLinks(in: archiveURL, entries: entries, runner: runner)

            var result = invoke(
                executable: "/usr/bin/tar",
                arguments: [
                    "-xf", archiveURL.path,
                    "-C", destination.path
                ],
                runner: runner
            )

            if result.status != 0 && fileExtension == "zip" {
                result = invoke(
                    executable: "/usr/bin/ditto",
                    arguments: [
                        "-x", "-k", archiveURL.path, destination.path
                    ],
                    runner: runner
                )
            }

            guard result.status == 0 else {
                throw ArchiveError.commandFailed(
                    archiveFailureMessage(
                        action: "extract",
                        detail: result.error
                    )
                )
            }
        }.value
    }

    private static func listSynchronously(
        _ archiveURL: URL,
        runner: CommandRunner
    ) throws -> [String] {
        let fileExtension = archiveURL.pathExtension.lowercased()
        if ["gz", "bz2", "xz"].contains(fileExtension) {
            return [
                archiveURL.deletingPathExtension().lastPathComponent
            ]
        }

        var result = invoke(
            executable: "/usr/bin/tar",
            arguments: ["-tf", archiveURL.path],
            runner: runner
        )
        if result.status != 0 && fileExtension == "zip" {
            result = invoke(
                executable: "/usr/bin/unzip",
                arguments: ["-Z1", archiveURL.path],
                runner: runner
            )
        }
        guard result.status == 0 else {
            throw ArchiveError.commandFailed(
                archiveFailureMessage(
                    action: "read",
                    detail: result.error
                )
            )
        }
        return result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func validate(_ entries: [String]) throws {
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

    private static func validateLinks(
        in archiveURL: URL,
        entries: [String],
        runner: CommandRunner
    ) throws {
        let result = invoke(
            executable: "/usr/bin/tar",
            arguments: ["-tvf", archiveURL.path],
            runner: runner
        )
        guard result.status == 0 else {
            throw ArchiveError.commandFailed(
                archiveFailureMessage(
                    action: "inspect",
                    detail: result.error
                )
            )
        }

        let descriptions = result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard descriptions.count == entries.count else {
            throw ArchiveError.commandFailed(
                "macOS could not inspect this archive safely because its metadata was inconsistent."
            )
        }

        for (name, description) in zip(entries, descriptions) {
            guard let link = linkTarget(from: description) else {
                continue
            }
            try validateLink(
                name: name,
                target: link.target,
                isHardLink: link.isHardLink
            )
        }
    }

    private static func linkTarget(
        from description: String
    ) -> (target: String, isHardLink: Bool)? {
        guard let type = description.first, type == "l" || type == "h" else {
            return nil
        }

        let separator = type == "l" ? " -> " : " link to "
        guard let separatorRange = description.range(
            of: separator,
            options: .backwards
        ) else {
            return nil
        }

        let target = String(description[separatorRange.upperBound...])
        return (target, type == "h")
    }

    private static func validateLink(
        name: String,
        target: String,
        isHardLink: Bool
    ) throws {
        let normalizedName = name.replacingOccurrences(of: "\\", with: "/")
        let normalizedTarget = target.replacingOccurrences(of: "\\", with: "/")
        if normalizedTarget.hasPrefix("/") {
            throw ArchiveError.unsafePath("\(name) -> \(target)")
        }

        var components = isHardLink
            ? []
            : normalizedName.split(separator: "/").dropLast().map(String.init)
        for component in normalizedTarget.split(
            separator: "/",
            omittingEmptySubsequences: false
        ) {
            switch component {
            case "", ".":
                continue
            case "..":
                guard !components.isEmpty else {
                    throw ArchiveError.unsafePath("\(name) -> \(target)")
                }
                components.removeLast()
            default:
                components.append(String(component))
            }
        }
    }

    private static func decompressSingleFile(
        _ archiveURL: URL,
        to destination: URL,
        runner: CommandRunner
    ) throws {
        let outputURL = destination.appendingPathComponent(
            archiveURL.deletingPathExtension().lastPathComponent
        )
        let temporaryURL = destination.appendingPathComponent(
            ".\(outputURL.lastPathComponent).\(UUID().uuidString).partial"
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        let result = invoke(
            executable: "/usr/bin/tar",
            arguments: ["-xOf", archiveURL.path],
            standardOutput: temporaryURL,
            runner: runner
        )
        if result.timedOut {
            throw ArchiveError.commandFailed(timeoutMessage(action: "expand"))
        }
        guard result.status == 0 else {
            throw ArchiveError.commandFailed(
                readableError(
                    result.error,
                    fallback: "The compressed file could not be expanded."
                )
            )
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(
                outputURL,
                withItemAt: temporaryURL
            )
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        }
    }

    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 30,
        standardOutput: URL? = nil
    ) -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        var outputHandle: FileHandle?
        if let standardOutput {
            FileManager.default.createFile(
                atPath: standardOutput.path,
                contents: nil
            )
            do {
                let handle = try FileHandle(forWritingTo: standardOutput)
                outputHandle = handle
                process.standardOutput = handle
            } catch {
                return CommandResult(
                    status: -1,
                    output: "",
                    error: error.localizedDescription,
                    timedOut: false
                )
            }
        } else {
            process.standardOutput = outputPipe
        }
        process.standardError = errorPipe
        let termination = terminationSemaphore(for: process)
        do {
            try process.run()
            let reads = DispatchGroup()
            let output = CommandOutput()
            let error = CommandOutput()
            if standardOutput == nil {
                reads.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    output.capture(from: outputPipe.fileHandleForReading)
                    reads.leave()
                }
            }
            reads.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                error.capture(from: errorPipe.fileHandleForReading)
                reads.leave()
            }
            let timedOut = waitForExit(
                process,
                termination: termination,
                timeout: timeout
            )
            reads.wait()
            try? outputHandle?.close()
            return CommandResult(
                status: process.terminationStatus,
                output: String(decoding: output.data, as: UTF8.self),
                error: timedOut
                    ? timeoutMessage(action: "finish")
                    : String(decoding: error.data, as: UTF8.self),
                timedOut: timedOut
            )
        } catch {
            try? outputHandle?.close()
            return CommandResult(
                status: -1,
                output: "",
                error: error.localizedDescription,
                timedOut: false
            )
        }
    }

    private static func invoke(
        executable: String,
        arguments: [String],
        standardOutput: URL? = nil,
        runner: CommandRunner
    ) -> CommandResult {
        runner(executable, arguments, commandTimeout, standardOutput)
    }

    private static func terminationSemaphore(
        for process: Process
    ) -> DispatchSemaphore {
        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            termination.signal()
        }
        return termination
    }

    @discardableResult
    private static func waitForExit(
        _ process: Process,
        termination: DispatchSemaphore,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = DispatchTime.now() + max(0, timeout)
        guard termination.wait(timeout: deadline) == .timedOut else {
            process.waitUntilExit()
            return false
        }

        process.terminate()
        if termination.wait(timeout: .now() + 1) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            termination.wait()
        }
        process.waitUntilExit()
        return true
    }

    private static func timeoutMessage(action: String) -> String {
        "The archive tool took too long to \(action) and was stopped. Try a smaller archive or check whether the file is damaged."
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

    private static func archiveFailureMessage(
        action: String,
        detail: String
    ) -> String {
        let explanation =
            "macOS could not \(action) this archive. It may be encrypted, damaged, or use an unsupported archive method."
        return readableError(detail, fallback: explanation) == explanation
            ? explanation
            : "\(explanation) \(readableError(detail, fallback: ""))"
    }

    private final class CommandOutput: @unchecked Sendable {
        var data = Data()

        func capture(from handle: FileHandle) {
            while true {
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }

                if chunk.count >= diagnosticCaptureLimit {
                    data = chunk.suffix(diagnosticCaptureLimit)
                    continue
                }

                let overflow =
                    data.count + chunk.count - diagnosticCaptureLimit
                if overflow > 0 {
                    data.removeFirst(overflow)
                }
                data.append(chunk)
            }
        }
    }

    struct CommandResult {
        let status: Int32
        let output: String
        let error: String
        let timedOut: Bool
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