// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MT3KMacTools",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mt3k-mac-tools", targets: ["MT3KMacTools"]),
        .executable(name: "mt3k-battery-helper", targets: ["MT3KBatteryHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/srimanachanta/SMCKit.git", revision: "8286f3b11ad9801405e0be062a07e557fb654019"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "BatteryGuardCore",
            path: "Sources/BatteryGuardCore"
        ),
        .executableTarget(
            name: "MT3KMacTools",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/MT3KMacTools"
        ),
        .executableTarget(
            name: "MT3KBatteryHelper",
            dependencies: [
                "BatteryGuardCore",
                .product(name: "SMCKit", package: "SMCKit"),
            ],
            path: "Sources/MT3KBatteryHelper",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "MT3KMacToolsTests",
            dependencies: ["MT3KMacTools", "BatteryGuardCore"],
            path: "Tests/MT3KMacToolsTests"
        ),
    ]
)
