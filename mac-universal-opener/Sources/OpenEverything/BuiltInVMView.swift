import AppKit
import SwiftUI
import Virtualization

enum GuestOperatingSystem: String, CaseIterable, Identifiable {
    case linux = "Linux"
    case windows = "Windows"
    var id: String { rawValue }
}

@MainActor
final class BuiltInVMController: ObservableObject {
    @Published var guest = GuestOperatingSystem.linux
    @Published var isoURL: URL?
    @Published var status = "Choose an installation ISO, then create or start the VM."
    @Published var virtualMachine: VZVirtualMachine?
    @Published var running = false

    private var accessedISO: URL?

    func chooseISO() {
        let panel = NSOpenPanel()
        panel.title = "Choose \(guest.rawValue) Installation Image"
        panel.allowedFileTypes = ["iso", "img"]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setISO(url)
    }

    func setISO(_ url: URL) {
        if accessedISO != url {
            accessedISO?.stopAccessingSecurityScopedResource()
            if url.startAccessingSecurityScopedResource() {
                accessedISO = url
            }
        }
        isoURL = url
        status = "Ready to boot \(url.lastPathComponent)."
    }

    func start() {
        do {
            let configuration = try makeConfiguration()
            try configuration.validate()
            let vm = VZVirtualMachine(configuration: configuration)
            virtualMachine = vm
            status = "Starting \(guest.rawValue) VM…"
            vm.start { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.running = true
                        self?.status = "VM is running."
                    case .failure(let error):
                        self?.status = "VM failed to start: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            status = "Couldn’t configure the VM: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard let virtualMachine, virtualMachine.canRequestStop else { return }
        do {
            try virtualMachine.requestStop()
            running = false
            status = "Stop requested."
        } catch {
            status = "Couldn’t stop the VM: \(error.localizedDescription)"
        }
    }

    private func makeConfiguration() throws -> VZVirtualMachineConfiguration {
        let directory = try vmDirectory()
        let configuration = VZVirtualMachineConfiguration()
        configuration.cpuCount = max(2, min(4, VZVirtualMachineConfiguration.maximumAllowedCPUCount))
        configuration.memorySize = min(
            4 * 1_024 * 1_024 * 1_024,
            VZVirtualMachineConfiguration.maximumAllowedMemorySize
        )

        let platform = VZGenericPlatformConfiguration()
        configuration.platform = platform

        let bootLoader = VZEFIBootLoader()
        let variablesURL = directory.appendingPathComponent("efi-variables")
        if FileManager.default.fileExists(atPath: variablesURL.path) {
            bootLoader.variableStore = VZEFIVariableStore(url: variablesURL)
        } else {
            bootLoader.variableStore = try VZEFIVariableStore(
                creatingVariableStoreAt: variablesURL
            )
        }
        configuration.bootLoader = bootLoader

        let diskURL = directory.appendingPathComponent("disk.img")
        if !FileManager.default.fileExists(atPath: diskURL.path) {
            FileManager.default.createFile(atPath: diskURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: diskURL)
            try handle.truncate(atOffset: 64 * 1_024 * 1_024 * 1_024)
            try handle.close()
        }
        let diskAttachment = try VZDiskImageStorageDeviceAttachment(
            url: diskURL,
            readOnly: false
        )
        var storage: [VZStorageDeviceConfiguration] = [
            VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)
        ]
        if let isoURL {
            let imageAttachment = try VZDiskImageStorageDeviceAttachment(
                url: isoURL,
                readOnly: true
            )
            storage.append(
                VZUSBMassStorageDeviceConfiguration(
                    attachment: imageAttachment
                )
            )
        }
        configuration.storageDevices = storage

        let graphics = VZVirtioGraphicsDeviceConfiguration()
        graphics.scanouts = [
            VZVirtioGraphicsScanoutConfiguration(
                widthInPixels: 1280,
                heightInPixels: 800
            )
        ]
        configuration.graphicsDevices = [graphics]
        configuration.keyboards = [VZUSBKeyboardConfiguration()]
        configuration.pointingDevices = [
            VZUSBScreenCoordinatePointingDeviceConfiguration()
        ]
        configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        configuration.memoryBalloonDevices = [
            VZVirtioTraditionalMemoryBalloonDeviceConfiguration()
        ]
        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        configuration.networkDevices = [network]
        return configuration
    }

    private func vmDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support
            .appendingPathComponent("Open Everything", isDirectory: true)
            .appendingPathComponent("Virtual Machines", isDirectory: true)
            .appendingPathComponent(guest.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

struct BuiltInVMView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = BuiltInVMController()
    let initialSourceURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Guest", selection: $controller.guest) {
                    ForEach(GuestOperatingSystem.allCases) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                Button("Choose ISO…") { controller.chooseISO() }
                Button(controller.running ? "Stop" : "Start") {
                    controller.running ? controller.stop() : controller.start()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            Divider()
            if let vm = controller.virtualMachine {
                VirtualMachineDisplay(virtualMachine: vm)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 52, weight: .light))
                    Text("Built-in \(controller.guest.rawValue) Virtual Machine")
                        .font(.title2.weight(.semibold))
                    Text(controller.isoURL?.lastPathComponent ?? "No installation image selected")
                        .foregroundStyle(.secondary)
                    if let initialSourceURL {
                        Text("Source file: \(initialSourceURL.lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("A sparse 64 GB virtual disk is created in Application Support. It consumes space only as the guest writes data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 540)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This VM unlocks:")
                            .font(.headline)
                        Label(
                            "A complete \(controller.guest.rawValue) desktop",
                            systemImage: "desktopcomputer"
                        )
                        Label(
                            controller.guest == .windows
                                ? "Windows apps, installers, and system tools"
                                : "DEB, RPM, AppImage, and native Linux programs",
                            systemImage: "app.badge.checkmark"
                        )
                        Label(
                            "Persistent storage, internet access, keyboard, and mouse",
                            systemImage: "externaldrive.connected.to.line.below"
                        )
                        Label(
                            "Isolation from your main macOS environment",
                            systemImage: "lock.shield"
                        )
                    }
                    .font(.callout)
                    .padding()
                    .background(
                        .quaternary,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            Text(controller.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .onAppear {
            if let initialSourceURL,
               ["iso", "img"].contains(initialSourceURL.pathExtension.lowercased()) {
                controller.setISO(initialSourceURL)
            }
        }
    }
}

private struct VirtualMachineDisplay: NSViewRepresentable {
    let virtualMachine: VZVirtualMachine

    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.virtualMachine = virtualMachine
        view.capturesSystemKeys = true
        return view
    }

    func updateNSView(_ view: VZVirtualMachineView, context: Context) {
        view.virtualMachine = virtualMachine
    }
}