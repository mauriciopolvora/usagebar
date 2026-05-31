// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "UsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "UsageBar",
            path: "Sources/UsageBar"
        )
    ]
)
