// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PerfTicker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PerfTicker",
            path: "Sources/PerfTicker"
        )
    ]
)
