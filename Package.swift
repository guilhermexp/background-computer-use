// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BackgroundComputerUse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BackgroundComputerUseKit", targets: ["BackgroundComputerUse"]),
        .executable(name: "BackgroundComputerUse", targets: ["BackgroundComputerUseServer"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            revision: "swift-6.2.3-RELEASE"
        ),
    ],
    targets: [
        .target(
            name: "BackgroundComputerUse",
            path: "Sources/BackgroundComputerUse"
        ),
        .executableTarget(
            name: "BackgroundComputerUseServer",
            dependencies: ["BackgroundComputerUse"],
            path: "Sources/BackgroundComputerUseServer"
        ),
        .testTarget(
            name: "BackgroundComputerUseTests",
            dependencies: [
                "BackgroundComputerUse",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/BackgroundComputerUseTests"
        ),
    ]
)
