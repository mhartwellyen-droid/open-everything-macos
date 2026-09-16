import AppKit
import SwiftUI

@MainActor
final class WindowsRuntimeManager: ObservableObject {
    @Published var installing = false
    @Published var status: String?

    private let runtimeURL = URL(
        string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.17/wine-staging-11.17-osx64.tar.xz"
    )!

    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: wineExecutable.path)
    }

    var isRosettaInstalled: Bool {
        #if arch(arm64)
        return FileManager.default.fileExists(
            atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        )
        #else
        return true
        #endif
    }

    func installAndRun(_ fileURL: URL) {
        guard !installing else { return }
        guard isRosettaInstalled else {
            status = "Rosetta 2 is required before Windows support can run. Install it with the command shown above, then try again."
            return
        }
        installing = true
        status = "Downloading Windows support (about 193 MB)…"
        Task {
            do {
                try await install()
                installing = false
                try run(fileURL)
            } catch {
                installing = false
                status = "Windows support could not be installed: \(error.localizedDescription)"
            }
        }
    }

    func run(_ fileURL: URL) throws {
        guard isRosettaInstalled else {
            throw RuntimeError.rosettaRequired
        }
        guard isInstalled else {
            installAndRun(fileURL)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", wineExecutable.path]
            + wineArguments(for: fileURL)
        process.currentDirectoryURL = fileURL.deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = winePrefix.path
        environment["WINEDEBUG"] = "-all"
        environment["PATH"] = wineExecutable.deletingLastPathComponent().path
            + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        try FileManager.default.createDirectory(
            at: winePrefix,
            withIntermediateDirectories: true
        )
        try process.run()
        status = "Started \(fileURL.lastPathComponent). The first launch may take a minute while Windows support initializes."
    }

    private func install() async throws {
        let (downloadedURL, response) = try await URLSession.shared.download(
            from: runtimeURL
        )
        guard
            let http = response as? HTTPURLResponse,
            http.statusCode == 200
        else {
            throw RuntimeError.downloadFailed
        }

        let root = runtimeRoot
        try await Task.detached {
            let fileManager = FileManager.default
            let work = root.deletingLastPathComponent()
                .appendingPathComponent("WindowsRuntimeInstall", isDirectory: true)
            let archive = work.appendingPathComponent("wine.tar.xz")
            let extracted = work.appendingPathComponent("extracted", isDirectory: true)
            try? fileManager.removeItem(at: work)
            try fileManager.createDirectory(
                at: extracted,
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: downloadedURL, to: archive)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", archive.path, "-C", extracted.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw RuntimeError.extractionFailed
            }

            let source = extracted
                .appendingPathComponent("Wine Staging.app/Contents/Resources/wine")
            try? fileManager.removeItem(at: root)
            try fileManager.createDirectory(
                at: root.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: root)
            try? fileManager.removeItem(at: work)
        }.value
        status = "Windows support is installed."
    }

    private func wineArguments(for url: URL) -> [String] {
        switch url.pathExtension.lowercased() {
        case "msi":
            return ["msiexec", "/i", url.path]
        case "bat", "cmd":
            return ["cmd", "/c", url.path]
        case "lnk":
            return ["start", "/unix", url.path]
        default:
            return [url.path]
        }
    }

    private var applicationSupport: URL {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Open Everything", isDirectory: true)
    }

    private var runtimeRoot: URL {
        applicationSupport.appendingPathComponent(
            "WindowsRuntime",
            isDirectory: true
        )
    }

    private var wineExecutable: URL {
        runtimeRoot.appendingPathComponent("bin/wine")
    }

    private var winePrefix: URL {
        applicationSupport.appendingPathComponent(
            "WinePrefix",
            isDirectory: true
        )
    }

    enum RuntimeError: LocalizedError {
        case downloadFailed
        case extractionFailed
        case rosettaRequired

        var errorDescription: String? {
            switch self {
            case .downloadFailed:
                return "The runtime download failed."
            case .extractionFailed:
                return "The downloaded runtime could not be extracted."
            case .rosettaRequired:
                return "Rosetta 2 must be installed before Windows files can run."
            }
        }
    }
}

struct ExecutableLauncherView: View {
    static let supportedExtensions: Set<String> = [
        "bat", "cmd", "com", "exe", "lnk", "msi"
    ]

    let url: URL
    @ObservedObject var runtime: WindowsRuntimeManager

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Windows file")
                .font(.title2.weight(.semibold))
            Text("Run this file directly through downloadable Windows compatibility support. A Windows ISO is not required.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            RosettaRequirementView()
            Button(
                runtime.isInstalled
                    ? "Run This Windows File with Wine"
                    : "Download Wine Support, Then Run This File"
            ) {
                if runtime.isInstalled {
                    do {
                        try runtime.run(url)
                    } catch {
                        runtime.status = "Could not start: \(error.localizedDescription)"
                    }
                } else {
                    runtime.installAndRun(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(runtime.installing)
            .help("Runs this file through Wine; a Windows ISO is not required")
            if runtime.installing {
                ProgressView()
                    .controlSize(.small)
            }
            if let status = runtime.status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Open the Full Windows VM Instead") {
                NotificationCenter.default.post(name: .openBuiltInVM, object: url)
            }
            .buttonStyle(.link)
            .help("Starts a complete Windows guest installed from an ISO")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

}

private struct RosettaRequirementView: View {
    private let command = "softwareupdate --install-rosetta --agree-to-license"

    var body: some View {
        #if arch(arm64)
        VStack(alignment: .leading, spacing: 8) {
            Label(
                rosettaInstalled ? "Rosetta 2 is installed" : "Rosetta 2 is required",
                systemImage: rosettaInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(rosettaInstalled ? Color.green : Color.orange)
            if !rosettaInstalled {
                Text("Open Terminal, paste this command, and press Return:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        #endif
    }

    private var rosettaInstalled: Bool {
        FileManager.default.fileExists(
            atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        )
    }
}