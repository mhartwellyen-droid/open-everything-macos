import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class FileViewerModel: ObservableObject {
    @Published var selectedURL: URL?
    @Published var showImporter = false
    @Published var loadError: String?
    @Published var actionMessage: String?
    @Published private(set) var recentURLs: [URL] = []
    private var securityScopedURLs: Set<URL> = []
    let windowsRuntime = WindowsRuntimeManager()

    func open(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            securityScopedURLs.insert(url)
        }
        loadError = nil
        selectedURL = url
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        recentURLs = Array(recentURLs.prefix(12))
    }

    func revealInFinder() {
        guard let selectedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedURL])
    }

    func removeFromRecents(_ url: URL) {
        recentURLs.removeAll { $0 == url }
    }

    func openWithDefaultApp() {
        guard let selectedURL else { return }
        if ExecutableLauncherView.supportedExtensions.contains(
            selectedURL.pathExtension.lowercased()
        ) {
            guard windowsRuntime.isRosettaInstalled else {
                actionMessage = """
                Rosetta 2 is required to run Windows files through Wine on Apple Silicon.

                Open Terminal and run:
                softwareupdate --install-rosetta --agree-to-license

                Then return to Open Everything and try again.
                """
                return
            }
            if windowsRuntime.isInstalled {
                do {
                    try windowsRuntime.run(selectedURL)
                    actionMessage = windowsRuntime.status
                } catch {
                    actionMessage = "Couldn’t run the Windows file: \(error.localizedDescription)"
                }
            } else {
                windowsRuntime.installAndRun(selectedURL)
                actionMessage = "Downloading Wine support. Progress and status are shown in the Windows file panel."
            }
            return
        }
        NSWorkspace.shared.open(selectedURL)
    }

    func makeSelectedFileApp() {
        guard let selectedURL else { return }

        let panel = NSSavePanel()
        panel.title = "Make File into an App"
        panel.prompt = "Create App"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.nameFieldStringValue =
            selectedURL.deletingPathExtension().lastPathComponent + ".app"
        guard panel.runModal() == .OK, let appURL = panel.url else { return }

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: appURL.path) {
                try fileManager.removeItem(at: appURL)
            }

            let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
            let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
            let resources = contents.appendingPathComponent("Resources", isDirectory: true)
            try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

            let payloadName = "payload." + selectedURL.pathExtension
            let payload = resources.appendingPathComponent(payloadName)
            try fileManager.copyItem(at: selectedURL, to: payload)

            guard let sourceExecutable = Bundle.main.executableURL else {
                throw NSError(
                    domain: "OpenEverything.AppWrapper",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The Open Everything executable could not be located."
                    ]
                )
            }
            let wrapperExecutable = macOS.appendingPathComponent("OpenEverything")
            try fileManager.copyItem(
                at: sourceExecutable,
                to: wrapperExecutable
            )

            for resourceName in [
                "AppIcon.icns",
                "jsnes.min.js",
                "JSNES-LICENSE.txt"
            ] {
                guard
                    let sourceResource = Bundle.main.resourceURL?
                        .appendingPathComponent(resourceName),
                    fileManager.fileExists(atPath: sourceResource.path)
                else {
                    continue
                }
                try fileManager.copyItem(
                    at: sourceResource,
                    to: resources.appendingPathComponent(resourceName)
                )
            }

            let plist: [String: Any] = [
                "CFBundleDevelopmentRegion": "en",
                "CFBundleDisplayName": appURL.deletingPathExtension().lastPathComponent,
                "CFBundleExecutable": "OpenEverything",
                "CFBundleIconFile": "AppIcon",
                "CFBundleIdentifier": "app.openeverything.wrapper.\(UUID().uuidString.lowercased())",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": appURL.deletingPathExtension().lastPathComponent,
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1"
            ]
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try plistData.write(to: contents.appendingPathComponent("Info.plist"))

            let signer = Process()
            signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            signer.arguments = ["--force", "--deep", "--sign", "-", appURL.path]
            try signer.run()
            signer.waitUntilExit()
            guard signer.terminationStatus == 0 else {
                throw NSError(
                    domain: "OpenEverything.AppWrapper",
                    code: Int(signer.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "macOS could not sign the generated app wrapper."
                    ]
                )
            }

            actionMessage = "Created and locally signed \(appURL.lastPathComponent). It contains its own Open Everything executable and a copy of the selected file, so it can open the Windows launcher directly."
        } catch {
            actionMessage = "Couldn’t create the app: \(error.localizedDescription)"
        }
    }

}

struct FileDetails {
    let name: String
    let path: String
    let size: String
    let modified: String
    let type: String
    let permissions: String

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .contentTypeKey
        ])
        name = url.lastPathComponent
        path = url.path
        size = ByteCountFormatter.string(
            fromByteCount: Int64(values?.fileSize ?? 0),
            countStyle: .file
        )
        if let date = values?.contentModificationDate {
            modified = date.formatted(date: .abbreviated, time: .shortened)
        } else {
            modified = "Unknown"
        }
        type = values?.contentType?.localizedDescription
            ?? values?.contentType?.identifier
            ?? "Unknown format"
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mode = attributes?[.posixPermissions] as? NSNumber
        permissions = mode.map { String(format: "%03o", $0.intValue) } ?? "Unknown"
    }
}