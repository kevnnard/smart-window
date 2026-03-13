// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SmartWindow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SmartWindow",
            targets: ["SmartWindow"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "SmartWindow",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources",
            resources: [
                .process("../Resources")
            ]
        )
    ]
)
