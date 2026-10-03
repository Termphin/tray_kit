// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "tray_kit",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "tray-kit", targets: ["tray_kit"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "tray_kit",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
