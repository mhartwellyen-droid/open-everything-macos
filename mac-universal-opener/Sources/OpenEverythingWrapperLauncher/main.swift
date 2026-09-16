import AppKit
import Foundation

@main
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { await start() }
    }

    private func start() async {
        guard let payloadURL else {
            showFatalError("This app does not contain its Windows file.")
            return
        }
        guard ensureRosetta() else { return }

        if !FileManager.default.isExecutableFile(atPath: wineExecutable.path) {
            let alert = NSAlert()
            alert.messageText = "Windows support is required"
            alert.informativeText =
                "This app needs to download Wine once (about 193 MB). A Windows ISO is not required."
            alert.addButton(withTitle: "Download and Run")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                NSApp.terminate(nil)
                return
            }

            showProgress("Downloading Windows support…")
            do {
                try await installRuntime()
            } catch {
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
            showFatalError("The Windows app could not start: \(error.localizedDescription)")
        }
    }

    private func ensureRosetta() -> Bool {
        #if arch(arm64)
        guard FileManager.default.fileExists(
            atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        ) else {
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
        #endif
        return true
    }

    private func installRuntime() async throws {
        let (downloadedURL, response) = try await URLSession.shared.download(
            from: runtimeDownloadURL
        )
        guard
            let http = response as? HTTPURLResponse,
            http.statusCode == 200
        else {
            throw LauncherError.downloadFailed
        }

        let root = runtimeRoot
        try await Task.detached {
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
        }.value
    }

    private func launchWine(_ payloadURL: URL) throws {
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
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
        try process.run()
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
            label.frame = NSRect(x: 24, y: 85, width: 392, height: 28)
            let progress = NSProgressIndicator(
                frame: NSRect(x: 70, y: 50, width: 300, height: 16)
            )
            progress.style = .bar
            progress.isIndeterminate = true
            progress.startAnimation(nil)
            content.addSubview(label)
            content.addSubview(progress)
            let created = NSWindow(
                contentRect: content.bounds,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            created.title = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleDisplayName"
            ) as? String ?? "Windows App"
            created.contentView = content
            created.center()
            window = created
            statusLabel = label
            progressIndicator = progress
        }
        statusLabel?.stringValue = message
        window?.makeKeyAndOrderFront(nil)
    }

    private func showFatalError(_ message: String) {
        window?.orderOut(nil)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Couldn’t open this Windows app"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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