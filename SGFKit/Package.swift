// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SGFKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SGFKit", targets: ["SGFKit"]),
    ],
    targets: [
        .target(name: "SGFKit"),
        .testTarget(name: "SGFKitTests", dependencies: ["SGFKit"]),
    ]
)
