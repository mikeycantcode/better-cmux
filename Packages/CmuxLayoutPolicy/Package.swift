// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmuxLayoutPolicy",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CmuxLayoutPolicy", targets: ["CmuxLayoutPolicy"])],
    targets: [
        .target(
            name: "CmuxLayoutPolicy",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(name: "CmuxLayoutPolicyTests", dependencies: ["CmuxLayoutPolicy"]),
    ]
)
