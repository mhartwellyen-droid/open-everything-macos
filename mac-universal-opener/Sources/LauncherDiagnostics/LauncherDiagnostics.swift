import AppKit
import Foundation

public final class LauncherDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private let component: String
    private let logURL: URL
    private let maximumBytes = 512 * 1024

    public init(component: String) {
        self.component = component
        let base = (try? FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
        let directory = base.appendingPathComponent(
            "Logs/Open Everything",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        logURL = directory.appendingPathComponent("Windows Launcher.log")
    }

    public func recordSystemStatus() {
        #if arch(arm64)
        record("CPU architecture: arm64")
        #else
        record("CPU architecture: x86_64")
        #endif
    }

    public func recordWineVersion(at executable: URL) {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            record("Wine version: unavailable")
            return
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", executable.path, "--version"]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let version = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            record(
                "Wine version: \(version?.isEmpty == false ? version! : "unknown")"
            )
        } catch {
            record("Wine version check failed: \(error.localizedDescription)")
        }
    }

    public func record(_ message: String) {
        let safe = message
            .replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path,
                with: "~"
            )
            .replacingOccurrences(of: "\n", with: " ")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) [\(component)] \(safe)\n"
        lock.lock()
        defer { lock.unlock() }
        var existing = (try? Data(contentsOf: logURL)) ?? Data()
        existing.append(Data(line.utf8))
        if existing.count > maximumBytes {
            existing = existing.suffix(maximumBytes)
            if let newline = existing.firstIndex(of: 0x0A) {
                existing = existing.suffix(
                    from: existing.index(after: newline)
                )
            }
        }
        try? existing.write(to: logURL, options: .atomic)
    }

    public func report() -> String {
        lock.lock()
        defer { lock.unlock() }
        return (try? String(contentsOf: logURL, encoding: .utf8))
            ?? "No diagnostic entries are available."
    }

    @MainActor
    public func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report(), forType: .string)
    }

    @MainActor
    public func presentSavePanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Open Everything Diagnostic Report.txt"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? report().write(
            to: destination,
            atomically: true,
            encoding: .utf8
        )
    }
}