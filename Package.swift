// swift-tools-version: 6.2
import PackageDescription

// `swift build` / `swift test` need a healthy Xcode 26 toolchain (CI has one).
// Scripts/build.sh assembles the signed .app bundle and also works on a bare Command Line Tools install.
let package = Package(
    name: "Pitwall",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Pitwall",
            path: "Sources/Pitwall",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PitwallTests",
            dependencies: ["Pitwall"],
            path: "Tests/PitwallTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
