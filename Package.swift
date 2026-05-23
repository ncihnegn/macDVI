// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "macDVI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "macDVI", targets: ["macDVI"])
    ],
    targets: [
        .executableTarget(name: "macDVI")
    ]
)
