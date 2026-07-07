// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Model",
    platforms: [
        .iOS("26.0"),
        .macOS("14.0"), // lets `swift test` run on the Mac host
    ],
    products: [
        .library(name: "Model", targets: ["Model"]),
    ],
    targets: [
        .target(name: "Model"),
    ]
)
