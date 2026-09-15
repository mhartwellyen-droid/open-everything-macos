import AppKit
import SwiftUI

struct ExecutableLauncherView: View {
    let url: URL
    @State private var status: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Windows executable")
                .font(.title2.weight(.semibold))
            Text("macOS cannot run this file directly. Open Everything can hand it to an installed Windows compatibility app such as Whisky, CrossOver, or Wine.")
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
                process.arguments = [url.path]
                try process.run()
                return "Started with Wine."
            } catch {
                return "Wine could not start: \(error.localizedDescription)"
            }
        }
        return "No Windows compatibility app was found. Install Whisky, CrossOver, or Wine, then try again."
    }

    private func bundleID(for appName: String) -> String {
        switch appName {
        case "Whisky": return "com.isaacmarovitz.Whisky"
        case "CrossOver": return "com.codeweavers.CrossOver"
        default: return "org.winehq.wine"
        }
    }
}