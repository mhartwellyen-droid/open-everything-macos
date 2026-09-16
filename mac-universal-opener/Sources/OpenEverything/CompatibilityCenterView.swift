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
                        rosettaInstalled
                            ? "Installed"
                            : "Required for Wine and Intel Mac apps",
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

                    Text("What the VM unlocks")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "A complete Windows or Linux desktop",
                            systemImage: "desktopcomputer"
                        )
                        Label(
                            "Windows software that does not work through Wine",
                            systemImage: "app.badge.checkmark"
                        )
                        Label(
                            "Linux DEB, RPM, AppImage, and native ELF software",
                            systemImage: "shippingbox"
                        )
                        Label(
                            "Bootable ISO and IMG installation media",
                            systemImage: "opticaldisc"
                        )
                        Label(
                            "Persistent virtual storage and NAT internet access",
                            systemImage: "externaldrive.connected.to.line.below"
                        )
                        Label(
                            "An isolated environment for testing untrusted software",
                            systemImage: "lock.shield"
                        )
                    }
                    .font(.callout)

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

                    Divider()
                    Text("How to get an ISO")
                        .font(.headline)
                    Text("You do not need an ISO to run ordinary EXE or MSI files. Use an ISO only when you want a complete Windows or Linux virtual machine.")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Choose the download that matches your Mac: ARM64 for Apple Silicon or x86-64 for Intel.")
                        Text("2. Download the ISO directly from Microsoft or your Linux distribution.")
                        Text("3. Open Built-in VM, choose Windows or Linux, select the ISO, and press Start.")
                        Text("4. Complete the operating-system installer inside the VM.")
                    }
                    .font(.callout)
                    HStack {
                        Link(
                            "Download Windows 11",
                            destination: URL(
                                string: "https://www.microsoft.com/software-download/windows11"
                            )!
                        )
                        Link(
                            "Download Ubuntu",
                            destination: URL(
                                string: "https://ubuntu.com/download/desktop"
                            )!
                        )
                    }
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