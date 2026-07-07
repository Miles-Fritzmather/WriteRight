// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CanvasCore",
    platforms: [
        .iOS("26.0"),
        .macOS("14.0"), // lets `swift test` run on the Mac host
    ],
    products: [
        .library(name: "CanvasCore", targets: ["CanvasCore"]),
    ],
    dependencies: [
        .package(path: "../Model"),
    ],
    targets: [
        .target(
            name: "CanvasCore",
            dependencies: [
                .product(name: "Model", package: "Model"),
            ]
        ),
        .testTarget(
            name: "CanvasCoreTests",
            dependencies: ["CanvasCore"]
        ),
    ]
)
