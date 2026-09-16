import AppKit
import SwiftUI

struct ExecutableLauncherView: View {
    static let supportedExtensions: Set<String> = [
        "bat", "cmd", "com", "exe", "lnk", "msi"
    ]

    let url: URL
    @State private var status: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Windows file")
                .font(.title2.weight(.semibold))
            Text("Open Everything runs this file through its built-in Windows compatibility environment.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button("Run with compatibility app") {
                status = launch()
            }
            .buttonStyle(.borderedProminent)
            if let status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func launch() -> String {
        if let embeddedWine = Bundle.main.resourceURL?
            .appendingPathComponent("WineRuntime/bin/wine"),
           FileManager.default.isExecutableFile(atPath: embeddedWine.path) {
            do {
                let support = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let prefix = support
                    .appendingPathComponent("Open Everything", isDirectory: true)
                    .appendingPathComponent("WinePrefix", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: prefix,
                    withIntermediateDirectories: true
                )

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
                process.arguments = ["-x86_64", embeddedWine.path] + wineArguments
                process.currentDirectoryURL = url.deletingLastPathComponent()
                var environment = ProcessInfo.processInfo.environment
                environment["WINEPREFIX"] = prefix.path
                environment["WINEDEBUG"] = "-all"
                environment["PATH"] = embeddedWine.deletingLastPathComponent().path
                    + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
                process.environment = environment
                try process.run()
                return "Started with the built-in Wine runtime. The first launch may take a minute while Windows support is initialized."
            } catch {
                return "The built-in Windows runtime could not start: \(error.localizedDescription). On Apple Silicon, install Rosetta 2 and try again."
            }
        }

        let workspace = NSWorkspace.shared
        let appNames = ["Whisky", "CrossOver", "Wine Stable"]
        for name in appNames {
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID(for: name))
                ?? workspace.fullPath(forApplication: name).map(URL.init(fileURLWithPath:)) {
                let configuration = NSWorkspace.OpenConfiguration()
                workspace.open([url], withApplicationAt: appURL, configuration: configuration)
                return "Opened with \(name)."
            }
        }

        let winePaths = [
            "/opt/homebrew/bin/wine64",
            "/opt/homebrew/bin/wine",
            "/usr/local/bin/wine64",
            "/usr/local/bin/wine"
        ]
        if let wine = winePaths.first(where: FileManager.default.isExecutableFile(atPath:)) {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: wine)
                process.arguments = wineArguments
                try process.run()
                return "Started with Wine."
            } catch {
                return "Wine could not start: \(error.localizedDescription)"
            }
        }
        return "The built-in Windows runtime is missing. Reinstall Open Everything, or install Whisky, CrossOver, or Wine."
    }

    private var wineArguments: [String] {
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

    private func bundleID(for appName: String) -> String {
        switch appName {
        case "Whisky": return "com.isaacmarovitz.Whisky"
        case "CrossOver": return "com.codeweavers.CrossOver"
        default: return "org.winehq.wine"
        }
    }
}