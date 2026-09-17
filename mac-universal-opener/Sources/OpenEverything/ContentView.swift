import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: FileViewerModel
    @State private var tab = InspectorTab.preview
    @State private var dropActive = false
    @State private var showCompatibilityCenter = false
    @State private var showBuiltInVM = false
    @State private var vmSourceURL: URL?
    @State private var showUpdates = false

    enum InspectorTab: String, CaseIterable, Identifiable {
        case preview = "Preview"
        case raw = "Raw"
        case info = "Info"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle(model.selectedURL?.lastPathComponent ?? "Open Everything")
        .fileImporter(
            isPresented: $model.showImporter,
            allowedContentTypes: [.data, .item, .content],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.open(url)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropActive) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url {
                    Task { @MainActor in model.open(url) }
                }
            }
            return true
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: { model.showImporter = true }) {
                    Label("Choose a File to Open", systemImage: "folder")
                }
                .help("Choose a file to inspect in Open Everything")
                Button(action: { showCompatibilityCenter = true }) {
                    Label("Check Compatibility and VM", systemImage: "checkmark.shield")
                }
                .help("Check Rosetta, Wine, and virtual-machine requirements")
                Button(action: { showUpdates = true }) {
                    Label("Get the Latest Version", systemImage: "arrow.down.circle")
                }
                .help("Open the newest Open Everything release")
                if model.selectedURL != nil {
                    Button(action: model.makeSelectedFileApp) {
                        Label("Create an App Copy of This File", systemImage: "app.badge")
                    }
                    .help("Copies this file into a locally signed app wrapper")
                    Button(action: model.openWithDefaultApp) {
                        Label(
                            isSelectedFileWindowsExecutable
                                ? "Run This Windows File with Wine"
                                : "Open with the Default Mac App",
                            systemImage: "arrow.up.forward.app"
                        )
                    }
                    .help(
                        isSelectedFileWindowsExecutable
                            ? "Runs through Wine instead of asking macOS to execute the file"
                            : "Opens this file in its associated macOS application"
                    )
                    Button(action: model.revealInFinder) {
                        Label("Reveal the Original in Finder", systemImage: "finder")
                    }
                    .help("Shows the original file without changing it")
                    Button {
                        if let url = model.selectedURL {
                            model.removeFromRecents(url)
                        }
                    } label: {
                        Label("Remove from Recents", systemImage: "trash")
                    }
                    .help("Removes only this Recent entry; the Finder file is not deleted")
                }
            }
        }
        .alert(
            "Open Everything",
            isPresented: Binding(
                get: { model.actionMessage != nil },
                set: { if !$0 { model.actionMessage = nil } }
            )
        ) {
            Button("OK") { model.actionMessage = nil }
        } message: {
            Text(model.actionMessage ?? "")
        }
        .sheet(isPresented: $showCompatibilityCenter) {
            CompatibilityCenterView()
                .frame(minWidth: 620, minHeight: 560)
        }
        .sheet(isPresented: $showBuiltInVM) {
            BuiltInVMView(initialSourceURL: vmSourceURL)
                .frame(minWidth: 900, minHeight: 650)
        }
        .sheet(isPresented: $showUpdates) {
            UpdateCenterView()
                .frame(minWidth: 520, minHeight: 360)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openBuiltInVM)) {
            notification in
            vmSourceURL = notification.object as? URL
            showBuiltInVM = true
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { model.showImporter = true }) {
                Label("Open any file", systemImage: "plus.rectangle.on.folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .padding()

            Divider()

            Text("RECENT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 14)

            if model.recentURLs.isEmpty {
                Text("Files you open appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding()
            } else {
                List(model.recentURLs, id: \.self, selection: Binding(
                    get: { model.selectedURL },
                    set: { if let url = $0 { model.open(url) } }
                )) { url in
                    HStack {
                        Label(url.lastPathComponent, systemImage: "doc")
                            .lineLimit(1)
                        Spacer()
                        Button {
                            model.removeFromRecents(url)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from Recents — the Finder file is not deleted")
                    }
                    .tag(url)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 250)
    }

    @ViewBuilder
    private var detail: some View {
        if let url = model.selectedURL {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .padding(12)
                Divider()
                switch tab {
                case .preview:
                    if url.pathExtension.lowercased() == "nes" {
                        NESPlayerView(romURL: url)
                            .id(url)
                    } else if ArchiveBrowserView.supportedExtensions.contains(
                        url.pathExtension.lowercased()
                    ) {
                        ArchiveBrowserView(url: url)
                            .id(url)
                    } else if ExecutableLauncherView.supportedExtensions.contains(
                        url.pathExtension.lowercased()
                    ) {
                        ExecutableLauncherView(
                            url: url,
                            runtime: model.windowsRuntime
                        )
                            .id(url)
                    } else if ["iso", "img"].contains(
                        url.pathExtension.lowercased()
                    ) {
                        WindowsDiskImageView(url: url)
                            .id(url)
                    } else if ["deb", "rpm", "sh"].contains(
                        url.pathExtension.lowercased()
                    ) {
                        LinuxFileView(url: url)
                            .id(url)
                    } else if url.pathExtension.lowercased() == "app" {
                        LegacyMacAppView(url: url)
                            .id(url)
                    } else if Model3DView.supportedExtensions.contains(
                        url.pathExtension.lowercased()
                    ) {
                        Model3DView(url: url)
                            .id(url)
                    } else {
                        QuickLookView(url: url)
                            .id(url)
                    }
                case .raw:
                    RawInspectorView(url: url)
                case .info:
                    FileInfoView(url: url)
                }
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop any file here")
                    .font(.title2.weight(.semibold))
                Text("Preview supported formats or inspect any unknown file as text, metadata, or hexadecimal bytes.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Button("Choose a File…") { model.showImporter = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dropActive ? Color.accentColor.opacity(0.12) : Color.clear)
        }
    }

    private var isSelectedFileWindowsExecutable: Bool {
        guard let selectedURL = model.selectedURL else { return false }
        return ExecutableLauncherView.supportedExtensions.contains(
            selectedURL.pathExtension.lowercased()
        )
    }
}

private struct FileInfoView: View {
    let url: URL

    var body: some View {
        let details = FileDetails(url: url)
        Form {
            LabeledContent("Name", value: details.name)
            LabeledContent("Format", value: details.type)
            LabeledContent("Size", value: details.size)
            LabeledContent("Modified", value: details.modified)
            LabeledContent("Permissions", value: details.permissions)
            LabeledContent("Path") {
                Text(details.path)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}