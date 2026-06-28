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
    targets: [
        .systemLibrary(
            name: "CSQLite"
        ),
        .executableTarget(
            name: "Portfolix",
            dependencies: ["CSQLite"]
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
