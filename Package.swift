// swift-tools-version:6.2
import PackageDescription

let defaultSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "machinist",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Machinist", targets: ["Machinist"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "Machinist",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: defaultSwiftSettings
        ),
        .testTarget(
            name: "MachinistTests",
            dependencies: ["Machinist"],
            swiftSettings: defaultSwiftSettings
        ),
    ]
)
