// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chiaro",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Chiaro",
            path: "Sources/Chiaro",
            resources: [.copy("Resources/Fonts"), .copy("Resources/AgentIcons")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
