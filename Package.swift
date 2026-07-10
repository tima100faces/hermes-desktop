// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HermesDesktop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "HermesDesktop",
            targets: ["HermesDesktop"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "HermesDesktop",
            path: "HermesDesktop",
            resources: []
        )
    ]
)
