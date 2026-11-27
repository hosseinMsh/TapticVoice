// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TapticVoice",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TapticCore", targets: ["TapticCore"]),
        .executable(name: "TapticVoice", targets: ["TapticVoice"])
    ],
    targets: [
        .target(
            name: "CSherpaOnnx",
            path: "Sources/CSherpaOnnx",
            publicHeadersPath: "."
        ),
        .target(
            name: "TapticCore",
            dependencies: ["CSherpaOnnx"],
            path: "Sources/TapticCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("NaturalLanguage")
            ]
        ),
        .executableTarget(
            name: "TapticVoice",
            dependencies: ["TapticCore"],
            path: "Sources/TapticVoice",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "TapticCoreVerify",
            dependencies: ["TapticCore"],
            path: "Tests/TapticCoreVerify"
        ),
        .testTarget(
            name: "TapticVoiceTests",
            dependencies: ["TapticCore"],
            path: "Tests/TapticVoiceTests"
        )
    ]
)
