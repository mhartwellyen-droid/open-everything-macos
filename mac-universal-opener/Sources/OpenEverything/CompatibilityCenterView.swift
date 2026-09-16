import AppKit
import SwiftUI

extension Notification.Name {
    static let openBuiltInVM = Notification.Name("OpenEverything.openBuiltInVM")
}

struct CompatibilityCenterView: View {
    @Environment(\.dismiss) private var dismiss
    private let rosettaCommand =
        "softwareupdate --install-rosetta --agree-to-license"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("System Status")
                        .font(.title2.weight(.semibold))
                    statusRow("Mac architecture", architectureName, true)
                    statusRow(
                        "Built-in VM engine",
                        "Apple Virtualization framework is available",
                        true
                    )
                    #if arch(arm64)
                    statusRow(
                        "Rosetta 2",
                        rosettaInstalled ? "Installed" : "Optional for Intel Mac apps",
                        rosettaInstalled
                    )
                    #endif

                    Divider()
                    Text("Built-in Linux and Windows VMs")
                        .font(.headline)
                    Text("Create and run virtual machines without downloading UTM, VMware, Parallels, or VirtualBox. Supply your own compatible Linux or Windows installation ISO.")
                        .foregroundStyle(.secondary)
                    Button("Open Built-in VM") {
                        dismiss()
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .openBuiltInVM,
                                object: nil
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    #if arch(arm64)
                    Divider()
                    Text("Rosetta 2 command")
                        .font(.headline)
                    HStack {
                        Text(rosettaCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                rosettaCommand,
                                forType: .string
                            )
                        }
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    #endif

                    Divider()
                    Text("Image requirements")
                        .font(.headline)
                    Text("Apple Silicon Macs require ARM64 Windows or Linux images. Intel Macs require x86-64 images. The built-in VM does not emulate a different processor architecture and does not include an operating-system license.")
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("Compatibility Center")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func statusRow(
        _ title: String,
        _ detail: String,
        _ ready: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(ready ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var rosettaInstalled: Bool {
        FileManager.default.fileExists(
            atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        )
    }

    private var architectureName: String {
        #if arch(arm64)
        return "Apple Silicon — ARM64 guests"
        #else
        return "Intel — x86-64 guests"
        #endif
    }
}