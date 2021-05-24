// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "BricBrac",
    products: [
        .library(name: "BricBrac", type: .dynamic, targets: ["BricBrac"]),
        .library(name: "Curio", type: .dynamic, targets: ["Curio"]),
        //.executable(name: "CurioTool", targets: ["CurioTool"]),
        ],
    targets: [
        .target(name: "BricBrac"),
        .testTarget(name: "BricBracTests", dependencies: ["BricBrac"]),
        .target(name: "Curio", dependencies: ["BricBrac"]),
        //.target(name: "CurioTool", dependencies: ["Curio"]),
        .testTarget(name: "CurioTests", dependencies: ["BricBrac", "Curio"]),
        ]
)
