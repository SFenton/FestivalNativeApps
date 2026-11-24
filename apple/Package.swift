// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FestivalApple",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FestivalCore", targets: ["FestivalCore"]),
        .library(name: "FestivalDesign", targets: ["FestivalDesign"]),
        .library(name: "FestivalUI", targets: ["FestivalUI"]),
    ],
    dependencies: [
        // First-party foundation; keep the source revision immutable for builds.
        .package(
            url: "https://github.com/SFenton/FentonPlatform.git",
            revision: "b84bcc910b34bb9481b1358662d1f579b2abe9e2"
        ),
    ],
    targets: [
        .target(name: "FestivalCore"),
        .target(name: "FestivalDesign"),
        .target(name: "FestivalAppSupport", dependencies: ["FestivalCore"]),
        .target(
            name: "FestivalUI",
            dependencies: [
                "FestivalCore",
                "FestivalDesign",
                "FestivalAppSupport",
                .product(name: "FentonAppleCore", package: "FentonPlatform"),
                .product(name: "FentonUIKit", package: "FentonPlatform"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FestivalCoreTests",
            dependencies: ["FestivalCore"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(name: "FestivalDesignTests", dependencies: ["FestivalDesign"]),
        .testTarget(
            name: "FestivalUITests",
            dependencies: ["FestivalUI", "FestivalCore", "FestivalAppSupport"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
