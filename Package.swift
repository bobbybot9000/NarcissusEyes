// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LookNice",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "LookNice",
            path: "Sources/LookNice",
            // Both are consumed by the Xcode target (the App Store build path),
            // not by SwiftPM — which would otherwise flag them as stray resources.
            exclude: ["Info.plist", "Assets.xcassets"]
        )
    ]
)
