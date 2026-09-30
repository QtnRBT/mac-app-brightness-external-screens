// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenBrightness",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ScreenBrightness",
            path: "Sources/ScreenBrightness",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]
        )
    ]
)
