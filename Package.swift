// swift-tools-version: 5.9

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let postscriptLibraryDirectory = packageRoot
    .deletingLastPathComponent()
    .appendingPathComponent("postscript/target/release")
let postscriptStaticLibrary = postscriptLibraryDirectory.appendingPathComponent("libpostscript.a")

let package = Package(
    name: "macDVI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "macDVI", targets: ["macDVI"])
    ],
    targets: [
        .systemLibrary(
            name: "CPostScript",
            path: "Sources/CPostScript"
        ),
        .executableTarget(
            name: "macDVI",
            dependencies: ["CPostScript"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker",
                    "-force_load",
                    "-Xlinker",
                    postscriptStaticLibrary.path
                ])
            ]
        )
    ]
)
