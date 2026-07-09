// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SketchKit",
    platforms: [
        .iOS("26.0"),
        .macOS("14.0"), // lets `swift test` run on the Mac host
    ],
    products: [
        .library(name: "SketchKit", targets: ["SketchKit"]),
    ],
    targets: [
        .target(name: "SketchKit"),
        .testTarget(
            name: "SketchKitTests",
            dependencies: ["SketchKit"]
        ),
    ]
)
