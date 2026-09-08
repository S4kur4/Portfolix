// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Portfolix",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Portfolix", targets: ["Portfolix"]),
        .executable(name: "PortfolixPriceUpdater", targets: ["PortfolixPriceUpdater"]),
        .executable(name: "PortfolixMCP", targets: ["PortfolixMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite"
        ),
        .target(
            name: "PortfolixCore"
        ),
        .target(name: "PortfolixMCPKit", dependencies: ["CSQLite", "PortfolixCore"]),
        .executableTarget(name: "PortfolixMCP", dependencies: ["PortfolixMCPKit", "PortfolixCore"]),
        .executableTarget(
            name: "Portfolix",
            dependencies: [
                "CSQLite",
                "PortfolixCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "PortfolixPriceUpdater",
            dependencies: ["CSQLite", "PortfolixCore"]
        ),
        .testTarget(
            name: "PortfolixTests",
            dependencies: ["Portfolix", "PortfolixCore", "PortfolixMCPKit"]
        )
    ]
)
