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
    targets: [
        .target(name: "FestivalCore"),
        .target(name: "FestivalDesign"),
        .target(
            name: "FestivalUI",
            dependencies: ["FestivalCore", "FestivalDesign"],
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
            dependencies: ["FestivalUI", "FestivalCore"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
