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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "CXSwitch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "CXSwitch",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
