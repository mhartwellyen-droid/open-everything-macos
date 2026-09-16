import AppKit
import SwiftUI

struct UpdateCenterView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Update Open Everything")
                .font(.title2.weight(.semibold))
            Text("Installed version: \(currentVersion)")
                .foregroundStyle(.secondary)
            Text("Download the newest DMG from the public project Releases page. You can also review the complete GPL-3.0 source code.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("Open the Latest Release Download Page") {
                NSWorkspace.shared.open(
                    URL(
                        string: "https://github.com/mhartwellyen-droid/open-everything-macos/releases/latest"
                    )!
                )
            }
            .buttonStyle(.borderedProminent)
            .help("Opens GitHub Releases to download the newest DMG")
            Link(
                "View Open-Source Code (GPL-3.0)",
                destination: URL(
                    string: "https://github.com/mhartwellyen-droid/open-everything-macos"
                )!
            )
            Button("Close") { dismiss() }
        }
        .padding(30)
    }

    private var currentVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
    }
}

struct GatekeeperHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let command =
        "sudo xattr -rd com.apple.quarantine \"/Applications/OpenEverything.app\""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Before opening Open Everything", systemImage: "lock.shield")
                .font(.title2.weight(.semibold))
            Text("This independently distributed build may be blocked by Gatekeeper with a “damaged” or “cannot be opened” message. The app is not deleting or modifying your files.")
                .foregroundStyle(.secondary)
            Text("After dragging OpenEverything.app into Applications:")
                .font(.headline)
            Text("1. Try right-clicking the app and choosing Open.\n2. If macOS still blocks it, open Terminal and run:")
            HStack(alignment: .top) {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Text("Terminal will request your Mac login password. It does not display characters while you type.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("I Understand") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
    }
}