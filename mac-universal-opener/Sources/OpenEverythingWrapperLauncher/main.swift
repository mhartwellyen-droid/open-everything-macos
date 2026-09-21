import AppKit
import Foundation
import LauncherDiagnostics

@MainActor
final class WrapperLauncher: NSObject, NSApplicationDelegate {
    private let rosettaCommand =
        "softwareupdate --install-rosetta --agree-to-license"
    private let runtimeDownloadURL = URL(
        string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.17/wine-staging-11.17-osx64.tar.xz"
    )!
    private var window: NSWindow?
    private var statusLabel: NSTextField?
    private var progressIndicator: NSProgressIndicator?
    private var wineProcess: Process?
    private let diagnostics = LauncherDiagnostics(component: "Generated Windows App")

    func applicationDidFinishLaunching(_ notification: Notification) {
        diagnostics.record("Launcher startup")
        diagnostics.recordSystemStatus()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showProgress("Preparing Windows app…")
        Task { await start() }
    }

    private func start() async {
        guard let payloadURL else {
            diagnostics.record("Payload discovery failed")
            showFatalError("This app does not contain its Windows file.")
            return
        }
        diagnostics.record("Payload type: \(payloadURL.pathExtension.lowercased())")
        guard ensureRosetta() else { return }

        diagnostics.record("Wine path: \(wineExecutable.path)")
        if !FileManager.default.isExecutableFile(atPath: wineExecutable.path) {
            diagnostics.record("Wine runtime: not installed")
            let alert = NSAlert()
            alert.messageText = "Windows support is required"
            alert.informativeText =
                "This app needs to download Wine once (about 193 MB). A Windows ISO is not required."
            alert.addButton(withTitle: "Download and Run")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                diagnostics.record("Wine download cancelled by user")
                NSApp.terminate(nil)
                return
            }

            showProgress("Downloading Windows support…")
            do {
                try await installRuntime()
            } catch {
                diagnostics.record("Wine installation failed: \(error.localizedDescription)")
                showFatalError(
                    "Windows support could not be installed: \(error.localizedDescription)"
                )
                return
            }
        }

        showProgress("Starting \(payloadURL.lastPathComponent)…")
        do {
            try launchWine(payloadURL)
        } catch {
            diagnostics.record("Wine launch failed: \(error.localizedDescription)")
            showFatalError("The Windows app could not start: \(error.localizedDescription)")
        }
    }

    private func ensureRosetta() -> Bool {
        #if arch(arm64)
        guard FileManager.default.fileExists(
            atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        ) else {
            diagnostics.record("Rosetta status: not installed")
            let alert = NSAlert()
            alert.messageText = "Rosetta 2 is required"
            alert.informativeText =
                "Install Rosetta 2 before running this Windows app:\n\n\(rosettaCommand)"
            alert.addButton(withTitle: "Copy Command")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    rosettaCommand,
                    forType: .string
                )
            }
            NSApp.terminate(nil)
            return false
        }
        diagnostics.record("Rosetta status: installed")
        #else
        diagnostics.record("Rosetta status: not required on Intel")
        #endif
        return true
    }

    private func installRuntime() async throws {
        diagnostics.record("Wine download started")
        let (downloadedURL, response) = try await URLSession.shared.download(
            from: runtimeDownloadURL
        )
        guard
            let http = response as? HTTPURLResponse,
            http.statusCode == 200
        else {
            diagnostics.record("Wine download failed: unexpected HTTP response")
            throw LauncherError.downloadFailed
        }
        diagnostics.record("Wine download completed: HTTP \(http.statusCode)")

        let root = runtimeRoot
        let extractionStatus = try await Task.detached {
            let fileManager = FileManager.default
            let work = root.deletingLastPathComponent()
                .appendingPathComponent(
                    "WindowsRuntimeInstall",
                    isDirectory: true
                )
            let archive = work.appendingPathComponent("wine.tar.xz")
            let extracted = work.appendingPathComponent(
                "extracted",
                isDirectory: true
            )
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
                throw LauncherError.extractionFailed
            }

            let source = extracted
                .appendingPathComponent(
                    "Wine Staging.app/Contents/Resources/wine"
                )
            try? fileManager.removeItem(at: root)
            try fileManager.createDirectory(
                at: root.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: root)
            try? fileManager.removeItem(at: work)
            return process.terminationStatus
        }.value
        diagnostics.record("Wine extraction completed: exit \(extractionStatus)")
        diagnostics.recordWineVersion(at: wineExecutable)
    }

    private func launchWine(_ payloadURL: URL) throws {
        diagnostics.recordWineVersion(at: wineExecutable)
        diagnostics.record("Wine launch requested")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", wineExecutable.path]
            + wineArguments(for: payloadURL)
        process.currentDirectoryURL = payloadURL.deletingLastPathComponent()
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
        process.terminationHandler = { [diagnostics] completed in
            diagnostics.record(
                "Wine exited: status \(completed.terminationStatus), reason \(completed.terminationReason.rawValue)"
            )
            DispatchQueue.main.async {
                if completed.terminationStatus == 0 {
                    NSApp.terminate(nil)
                } else {
                    self.showFatalError(
                        "Wine stopped with exit status \(completed.terminationStatus)."
                    )
                }
            }
        }
        try process.run()
        diagnostics.record("Wine process started: pid \(process.processIdentifier)")
        wineProcess = process
        window?.orderOut(nil)
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

    private func showProgress(_ message: String) {
        if window == nil {
            let content = NSView(
                frame: NSRect(x: 0, y: 0, width: 440, height: 150)
            )
            let label = NSTextField(labelWithString: message)
            label.alignment = .center
            label.font = .systemFont(ofSize: 16, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            let progress = NSProgressIndicator()
            progress.style = .bar
            progress.isIndeterminate = true
            progress.translatesAutoresizingMaskIntoConstraints = false
            progress.startAnimation(nil)
            content.addSubview(label)
            content.addSubview(progress)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                label.centerYAnchor.constraint(
                    equalTo: content.centerYAnchor,
                    constant: 16
                ),
                label.leadingAnchor.constraint(
                    greaterThanOrEqualTo: content.leadingAnchor,
                    constant: 24
                ),
                label.trailingAnchor.constraint(
                    lessThanOrEqualTo: content.trailingAnchor,
                    constant: -24
                ),
                progress.centerXAnchor.constraint(
                    equalTo: content.centerXAnchor
                ),
                progress.topAnchor.constraint(
                    equalTo: label.bottomAnchor,
                    constant: 12
                ),
                progress.widthAnchor.constraint(equalToConstant: 300)
            ])
            let created = NSWindow(
                contentRect: content.bounds,
                styleMask: [
                    .titled,
                    .closable,
                    .miniaturizable,
                    .resizable
                ],
                backing: .buffered,
                defer: false
            )
            created.title = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleDisplayName"
            ) as? String ?? "Windows App"
            created.contentView = content
            created.collectionBehavior.insert(.fullScreenPrimary)
            created.minSize = NSSize(width: 440, height: 150)
            created.center()
            window = created
            statusLabel = label
            progressIndicator = progress
        }
        statusLabel?.stringValue = message
        window?.makeKeyAndOrderFront(nil)
    }

    private func showFatalError(_ message: String) {
        diagnostics.record("Fatal error summary: \(message)")
        window?.orderOut(nil)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Couldn’t open this Windows app"
        alert.informativeText = message
        alert.addButton(withTitle: "Copy Diagnostics")
        alert.addButton(withTitle: "Save Diagnostic Report")
        alert.addButton(withTitle: "Quit")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            diagnostics.copyToPasteboard()
            showFatalError(message)
            return
        case .alertSecondButtonReturn:
            diagnostics.presentSavePanel()
            showFatalError(message)
            return
        default:
            break
        }
        NSApp.terminate(nil)
    }

    private var payloadURL: URL? {
        guard
            let resources = Bundle.main.resourceURL,
            let contents = try? FileManager.default.contentsOfDirectory(
                at: resources,
                includingPropertiesForKeys: nil
            )
        else {
            return nil
        }
        return contents.first {
            $0.lastPathComponent.hasPrefix("payload.")
        }
    }

    private var applicationSupport: URL {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent(
            "Open Everything",
            isDirectory: true
        )
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

    enum LauncherError: LocalizedError {
        case downloadFailed
        case extractionFailed

        var errorDescription: String? {
            switch self {
            case .downloadFailed:
                return "The Wine download failed."
            case .extractionFailed:
                return "The Wine download could not be extracted."
            }
        }
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let launcher = WrapperLauncher()
    application.delegate = launcher
    application.setActivationPolicy(.regular)
    application.run()
}