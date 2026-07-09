// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Narcissus",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "Narcissus",
            path: "Sources/Narcissus",
            exclude: ["Info.plist"]
        )
    ]
)
