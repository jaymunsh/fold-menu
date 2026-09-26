// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FoldMenu",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "FoldMenu")],
    swiftLanguageModes: [.v5]
)
