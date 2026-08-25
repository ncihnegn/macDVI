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
        .target(
            name: "CPostScript",
            dependencies: [],
            path: "Sources/CPostScript"
        ),
        .executableTarget(
            name: "macDVI",
            dependencies: ["CPostScript"],
            linkerSettings: [
                .unsafeFlags([
                    "-L/Users/ningchen/Temp/postscript/target/release",
                    "-lpostscript"
                ])
            ]
        )
    ]
)
