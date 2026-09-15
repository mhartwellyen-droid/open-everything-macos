import ModelIO
import SceneKit
import SceneKit.ModelIO
import SwiftUI

struct Model3DView: View {
    static let supportedExtensions: Set<String> = [
        "3ds", "abc", "dae", "obj", "ply", "scn", "stl",
        "usd", "usda", "usdc", "usdz"
    ]

    let url: URL
    @State private var scene: SCNScene?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let scene {
                SceneView(
                    scene: scene,
                    options: [
                        .allowsCameraControl,
                        .autoenablesDefaultLighting
                    ],
                    preferredFramesPerSecond: 60,
                    antialiasingMode: .multisampling4X
                )
                .overlay(alignment: .bottomLeading) {
                    Label(
                        "Drag to rotate • Scroll to zoom • Two-finger drag to pan",
                        systemImage: "rotate.3d"
                    )
                    .font(.caption)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                }
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn’t load this 3D file",
                    systemImage: "cube.transparent",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Loading 3D model…")
            }
        }
        .task(id: url) {
            loadModel()
        }
    }

    @MainActor
    private func loadModel() {
        errorMessage = nil
        scene = nil

        let asset = MDLAsset(url: url)
        guard asset.count > 0 else {
            errorMessage = "The model is empty or its encoding is not supported by macOS."
            return
        }

        let loadedScene = SCNScene(mdlAsset: asset)
        guard !loadedScene.rootNode.childNodes.isEmpty else {
            errorMessage = "No displayable geometry was found."
            return
        }

        loadedScene.background.contents = NSColor.windowBackgroundColor
        scene = loadedScene
    }
}