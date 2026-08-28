// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NarcissusEyes",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "NarcissusEyes",
            path: "Sources/NarcissusEyes",
            // Both are consumed by the Xcode target (the App Store build path),
            // not by SwiftPM — which would otherwise flag them as stray resources.
            exclude: ["Info.plist", "Assets.xcassets"]
        )
    ]
)
