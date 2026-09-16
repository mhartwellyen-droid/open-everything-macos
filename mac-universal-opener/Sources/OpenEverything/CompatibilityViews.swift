import AppKit
import SwiftUI

struct WindowsDiskImageView: View {
    let url: URL
    @State private var status: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "opticaldiscdrive")
                .font(.system(size: 48, weight: .light))
            Text("Windows disk image")
                .font(.title2.weight(.semibold))
            Text("Open Everything can mount this image. After it opens in Finder, select its setup.exe or installer.msi file to run it through the built-in Windows runtime.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            Button("Mount and Open Image") {
                status = mountImage()
            }
            .buttonStyle(.borderedProminent)
            Button("Use with Virtual Machine") {
                NotificationCenter.default.post(name: .openBuiltInVM, object: url)
                status = "Opening the built-in VM."
            }
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

    private func mountImage() -> String {
        do {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["attach", "-plist", "-nobrowse", url.path]
            process.standardOutput = pipe
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return "macOS could not mount this disk image."
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard
                let plist = try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as? [String: Any],
                let entities = plist["system-entities"] as? [[String: Any]],
                let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first
            else {
                return "The image mounted, but its Finder location could not be determined."
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: mountPath))
            return "Mounted successfully. Open setup.exe or an .msi installer from the Finder window."
        } catch {
            return "Couldn’t mount the image: \(error.localizedDescription)"
        }
    }
}

struct LinuxFileView: View {
    let url: URL
    @State private var confirmRun = false
    @State private var status: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48, weight: .light))
            Text(title)
                .font(.title2.weight(.semibold))
            Text(explanation)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580)
            if url.pathExtension.lowercased() == "sh" {
                Button("Run with macOS Shell") {
                    confirmRun = true
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Open Linux Virtual Machine") {
                NotificationCenter.default.post(name: .openBuiltInVM, object: url)
                status = "Opening the built-in VM."
            }
            if let status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .alert("Run this shell script?", isPresented: $confirmRun) {
            Button("Cancel", role: .cancel) {}
            Button("Run Script") { runScript() }
        } message: {
            Text("Shell scripts can change or delete files. Only run scripts you trust. Linux-specific commands and libraries will not work on macOS.")
        }
    }

    private var title: String {
        url.pathExtension.lowercased() == "sh"
            ? "Linux or Unix shell script"
            : "Linux software package"
    }

    private var explanation: String {
        if url.pathExtension.lowercased() == "sh" {
            return "This script can run only if it uses commands available on macOS. Scripts that depend on Linux system libraries, package managers, or kernel features require a Linux virtual machine."
        }
        return "\(url.pathExtension.uppercased()) packages contain Linux software and cannot be installed into macOS. They require a compatible Linux system or virtual machine."
    }

    private func runScript() {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [url.path]
            process.currentDirectoryURL = url.deletingLastPathComponent()
            try process.run()
            status = "The script started. Linux-only commands may still fail."
        } catch {
            status = "The script could not start: \(error.localizedDescription)"
        }
    }
}

struct LegacyMacAppView: View {
    let url: URL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48, weight: .light))
            Text("Legacy Mac application")
                .font(.title2.weight(.semibold))
            Text("macOS Catalina and newer cannot run 32-bit Mac applications. Rosetta 2 translates Intel 64-bit apps only; it does not restore 32-bit Mac support.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580)
            Text("To run a genuinely 32-bit Mac app, use macOS Mojave 10.14 or earlier on compatible Apple hardware or in a properly licensed virtual machine.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580)
            Button("Show App in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}