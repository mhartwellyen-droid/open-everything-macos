import AppKit
import SwiftUI

enum VirtualMachineSupport {
    struct VMApplication: Identifiable {
        let name: String
        let bundleIdentifier: String
        var id: String { bundleIdentifier }

        var applicationURL: URL? {
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            )
        }
    }

    static let applications = [
        VMApplication(name: "UTM", bundleIdentifier: "com.utmapp.UTM"),
        VMApplication(name: "VMware Fusion", bundleIdentifier: "com.vmware.fusion"),
        VMApplication(
            name: "Parallels Desktop",
            bundleIdentifier: "com.parallels.desktop.console"
        ),
        VMApplication(
            name: "VirtualBox",
            bundleIdentifier: "org.virtualbox.app.VirtualBox"
        )
    ]

    static var installedApplications: [VMApplication] {
        applications.filter { $0.applicationURL != nil }
    }

    static func openForVirtualMachine(fileURL: URL) -> String {
        guard
            let application = installedApplications.first,
            let applicationURL = application.applicationURL
        else {
            NSWorkspace.shared.open(URL(string: "https://mac.getutm.app/")!)
            return "No supported virtual machine app was found. The UTM download page was opened."
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        return "Opened \(application.name) and selected \(fileURL.lastPathComponent) in Finder. Attach or copy the file into your virtual machine."
    }
}

struct CompatibilityCenterView: View {
    @Environment(\.dismiss) private var dismiss
    private let rosettaCommand =
        "softwareupdate --install-rosetta --agree-to-license"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusSection
                    windowsSection
                    virtualMachineSection
                    limitationsSection
                }
                .padding(24)
            }
            .navigationTitle("Compatibility Center")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Status")
                .font(.title2.weight(.semibold))
            statusRow(
                title: "Mac architecture",
                detail: architectureName,
                ready: true
            )
            statusRow(
                title: "Built-in Windows runtime",
                detail: wineInstalled ? "Wine runtime is ready" : "Wine runtime is missing",
                ready: wineInstalled
            )
            #if arch(arm64)
            statusRow(
                title: "Rosetta 2",
                detail: rosettaInstalled ? "Installed" : "Required for Windows files",
                ready: rosettaInstalled
            )
            #endif
            statusRow(
                title: "Virtual machine support",
                detail: vmStatus,
                ready: !VirtualMachineSupport.installedApplications.isEmpty
            )
        }
    }

    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Windows Compatibility")
                .font(.headline)
            Text("The bundled Wine runtime handles EXE, MSI, BAT, CMD, COM, and LNK files. Compatibility depends on the Windows program.")
                .foregroundStyle(.secondary)
            #if arch(arm64)
            if !rosettaInstalled {
                Text("Install Rosetta 2")
                    .font(.subheadline.weight(.semibold))
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
            }
            #endif
        }
    }

    private var virtualMachineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Virtual Machines")
                .font(.headline)
            Text("Use a VM for bootable Windows images, Linux packages and executables, or legacy 32-bit Mac applications.")
                .foregroundStyle(.secondary)
            ForEach(VirtualMachineSupport.applications) { application in
                HStack {
                    Image(
                        systemName: application.applicationURL == nil
                            ? "circle"
                            : "checkmark.circle.fill"
                    )
                    .foregroundStyle(
                        application.applicationURL == nil
                            ? Color.secondary
                            : Color.green
                    )
                    Text(application.name)
                    Spacer()
                    if let url = application.applicationURL {
                        Button("Open") {
                            NSWorkspace.shared.openApplication(
                                at: url,
                                configuration: .init()
                            )
                        }
                    } else if application.name == "UTM" {
                        Link(
                            "Download",
                            destination: URL(string: "https://mac.getutm.app/")!
                        )
                    }
                }
            }
        }
    }

    private var limitationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Important Limitations")
                .font(.headline)
            Text("Open Everything does not include Windows, Linux, or an older copy of macOS. Operating-system installers and licenses must be supplied by the user. Apple permits macOS virtualization only under its applicable license terms.")
                .foregroundStyle(.secondary)
        }
    }

    private func statusRow(
        title: String,
        detail: String,
        ready: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ready ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var wineInstalled: Bool {
        Bundle.main.resourceURL.map {
            FileManager.default.isExecutableFile(
                atPath: $0
                    .appendingPathComponent("WineRuntime/bin/wine")
                    .path
            )
        } ?? false
    }

    private var rosettaInstalled: Bool {
        FileManager.default.fileExists(
            atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        )
    }

    private var architectureName: String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }

    private var vmStatus: String {
        let names = VirtualMachineSupport.installedApplications.map(\.name)
        return names.isEmpty ? "No supported VM app detected" : names.joined(separator: ", ")
    }
}