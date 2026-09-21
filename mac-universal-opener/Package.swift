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
            dependencies: ["LauncherDiagnostics"],
            path: "Sources/OpenEverything",
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "OpenEverythingWrapperLauncher",
            dependencies: ["LauncherDiagnostics"],
            path: "Sources/OpenEverythingWrapperLauncher"
        ),
        .target(
            name: "LauncherDiagnostics",
            path: "Sources/LauncherDiagnostics"
        ),
        .testTarget(
            name: "OpenEverythingTests",
            dependencies: ["OpenEverything"],
            path: "Tests/OpenEverythingTests"
        )
    ]
)
