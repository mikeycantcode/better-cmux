// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmuxEditPreview",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CmuxEditPreview", targets: ["CmuxEditPreview"])],
    targets: [
        .target(
            name: "CmuxEditPreview",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(name: "CmuxEditPreviewTests", dependencies: ["CmuxEditPreview"]),
    ]
)
