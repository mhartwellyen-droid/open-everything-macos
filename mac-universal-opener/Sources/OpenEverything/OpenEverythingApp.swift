import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openHandler: ((URL) -> Void)? {
        didSet { flushPendingFiles() }
    }
    private var pendingFiles: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingFiles.append(contentsOf: urls)
        flushPendingFiles()
    }

    private func flushPendingFiles() {
        guard let openHandler else { return }
        pendingFiles.forEach(openHandler)
        pendingFiles.removeAll()
    }
}

@main
struct OpenEverythingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = FileViewerModel()
    @AppStorage("didShowGatekeeperHelp") private var didShowGatekeeperHelp = false
    @State private var showGatekeeperHelp = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 620)
                .onAppear {
                    appDelegate.openHandler = { url in
                        Task { @MainActor in model.open(url) }
                    }
                    if !didShowGatekeeperHelp {
                        showGatekeeperHelp = true
                    }
                }
                .sheet(isPresented: $showGatekeeperHelp, onDismiss: {
                    didShowGatekeeperHelp = true
                }) {
                    GatekeeperHelpView()
                        .frame(minWidth: 560, minHeight: 390)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open File…") {
                    model.showImporter = true
                }
                .keyboardShortcut("o")
            }
        }
    }

}