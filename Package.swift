// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chiaro",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Chiaro",
            path: "Sources/Chiaro",
            // Resources are located by Support/Resources.swift, not declared
            // here: SwiftPM's Bundle.module accessor embeds the absolute build
            // path and falls back to it inside a signed .app.
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
