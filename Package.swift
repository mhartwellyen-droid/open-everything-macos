// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenEverything",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OpenEverything", targets: ["OpenEverything"])
    ],
    targets: [
        .executableTarget(
            name: "OpenEverything",
            path: "Sources/OpenEverything"
        )
    ]
)