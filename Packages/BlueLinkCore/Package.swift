// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlueLinkCore",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "BlueLinkCore", targets: ["BlueLinkCore"])
    ],
    targets: [
        .target(name: "BlueLinkCore"),
        .testTarget(name: "BlueLinkCoreTests", dependencies: ["BlueLinkCore"])
    ],
    swiftLanguageModes: [.v6]
)
