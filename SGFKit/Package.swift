// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SGFKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SGFKit", targets: ["SGFKit"]),
        .library(name: "SGFRendering", targets: ["SGFRendering"]),
    ],
    targets: [
        .target(name: "SGFKit"),
        .target(name: "SGFRendering", dependencies: ["SGFKit"]),
        .testTarget(name: "SGFKitTests", dependencies: ["SGFKit"]),
        .testTarget(name: "SGFRenderingTests", dependencies: ["SGFRendering", "SGFKit"]),
    ]
)
