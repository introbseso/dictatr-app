// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dictatr",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DictatrCore"),
        .executableTarget(name: "Dictatr", dependencies: ["DictatrCore"]),
        .executableTarget(name: "DictatrTests", dependencies: ["DictatrCore"]),
    ]
)
