// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Minutes",
    platforms: [.macOS("14.2")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.5"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "Minutes",
            dependencies: [
                "AudioGraphShim",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/Minutes",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AudioGraphShim",
            path: "Sources/AudioGraphShim",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("AVFAudio"), .linkedFramework("AudioToolbox")]
        ),
    ]
)
