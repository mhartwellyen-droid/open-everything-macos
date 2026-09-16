// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenEverything",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OpenEverything", targets: ["OpenEverything"]),
        .executable(
            name: "OpenEverythingWrapperLauncher",
            targets: ["OpenEverythingWrapperLauncher"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OpenEverything",
            path: "Sources/OpenEverything",
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "OpenEverythingWrapperLauncher",
            path: "Sources/OpenEverythingWrapperLauncher"
        )
    ]
)