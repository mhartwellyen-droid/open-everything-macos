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
            Text("Open Everything can open its built-in Windows virtual machine. Install Windows once from your own ISO, then run Windows files inside that VM.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            RosettaRequirementView()
            Button("Open Built-in Windows VM") {
                NotificationCenter.default.post(
                    name: .openBuiltInVM,
                    object: url
                )
                status = "Opening the built-in VM. The file’s folder will remain available in Finder for transfer into Windows."
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