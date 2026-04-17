// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BSPRenderer",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "BSPRenderer", path: "Sources/BSPRenderer")
    ]
)
