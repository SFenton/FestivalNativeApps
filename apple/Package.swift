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
        // Private internal foundation; keep the source revision immutable for builds.
        .package(
            url: "https://github.com/SFenton/FentonPlatform.git",
            revision: "0b9592686a90a89181e442cdc0f5058bca9af001"
        ),
    ],
    targets: [
        .target(name: "FestivalCore"),
        .target(name: "FestivalDesign"),
        .target(
            name: "FestivalUI",
            dependencies: [
                "FestivalCore",
                "FestivalDesign",
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
            dependencies: [
                "FestivalUI", "FestivalCore",
                .product(name: "FentonUIKit", package: "FentonPlatform"),
            ],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
