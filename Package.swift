// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CXSwitch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CXSwitch",
            targets: ["CXSwitch"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CXSwitch",
            path: "CXSwitch",
            exclude: ["Resources"]
        )
    ]
)
