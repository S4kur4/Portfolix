// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Portfolix",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Portfolix", targets: ["Portfolix"]),
        .executable(name: "PortfolixPriceUpdater", targets: ["PortfolixPriceUpdater"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite"
        ),
        .executableTarget(
            name: "Portfolix",
            dependencies: [
                "CSQLite",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "PortfolixPriceUpdater",
            dependencies: ["CSQLite"]
        ),
        .testTarget(
            name: "PortfolixTests",
            dependencies: ["Portfolix"]
        )
    ]
)
