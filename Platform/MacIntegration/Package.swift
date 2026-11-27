// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacIntegration",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "MacIntegration", targets: ["MacIntegration"])
    ],
    dependencies: [
        .package(path: "../../Packages/BlueLinkCore")
    ],
    targets: [
        .target(
            name: "MacIntegration",
            dependencies: [
                .product(name: "BlueLinkCore", package: "BlueLinkCore")
            ]
        ),
        .testTarget(
            name: "MacIntegrationTests",
            dependencies: ["MacIntegration"]
        )
    ],
    swiftLanguageModes: [.v6]
)
