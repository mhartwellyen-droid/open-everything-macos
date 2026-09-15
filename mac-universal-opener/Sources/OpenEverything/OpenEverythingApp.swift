import SwiftUI

@main
struct OpenEverythingApp: App {
    @StateObject private var model = FileViewerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 620)
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