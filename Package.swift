// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BackgroundComputerUse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BackgroundComputerUseKit", targets: ["BackgroundComputerUse"]),
        .library(name: "BackgroundComputerUseControlShared", targets: ["BackgroundComputerUseControlShared"]),
        .library(name: "BackgroundComputerUseControl", targets: ["BackgroundComputerUseControl"]),
        .library(name: "BackgroundComputerUseLockedShared", targets: ["BackgroundComputerUseLockedShared"]),
        .library(name: "BackgroundComputerUseLockedBroker", targets: ["BackgroundComputerUseLockedBroker"]),
        .library(name: "BCUAuthorizationPlugin", targets: ["BCUAuthorizationPlugin"]),
        .library(name: "BackgroundComputerUseLockedInstaller", targets: ["BackgroundComputerUseLockedInstaller"]),
        .library(name: "BCUAuthorizationPluginBundle", type: .dynamic, targets: ["BCUAuthorizationPlugin"]),
        .executable(name: "BackgroundComputerUseCoreXPCService", targets: ["BackgroundComputerUseCoreXPCService"]),
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
            dependencies: ["BackgroundComputerUseControlShared"],
            path: "Sources/BackgroundComputerUse"
        ),
        .target(
            name: "BackgroundComputerUseControlShared",
            path: "Sources/BackgroundComputerUseControlShared"
        ),
        .target(
            name: "BackgroundComputerUseControl",
            dependencies: ["BackgroundComputerUseControlShared", "BackgroundComputerUseLockedShared"],
            path: "Sources/BackgroundComputerUseControl"
        ),
        .target(
            name: "BackgroundComputerUseLockedShared",
            dependencies: ["BackgroundComputerUseControlShared"],
            path: "Sources/BackgroundComputerUseLockedShared"
        ),
        .target(
            name: "BackgroundComputerUseLockedBroker",
            dependencies: ["BackgroundComputerUseLockedShared", "BackgroundComputerUseControlShared"],
            path: "Sources/BackgroundComputerUseLockedBroker"
        ),
        .target(
            name: "BCUAuthorizationPlugin",
            dependencies: ["BackgroundComputerUseLockedShared", "CAuthorizationPlugin"],
            path: "Sources/BCUAuthorizationPlugin"
        ),
        .target(
            name: "CAuthorizationPlugin",
            path: "Sources/CAuthorizationPlugin",
            publicHeadersPath: "include"
        ),
        .target(
            name: "BackgroundComputerUseLockedInstaller",
            dependencies: ["BackgroundComputerUseLockedShared"],
            path: "Sources/BackgroundComputerUseLockedInstaller"
        ),
        .executableTarget(
            name: "BackgroundComputerUseServer",
            dependencies: ["BackgroundComputerUse", "BackgroundComputerUseControl"],
            path: "Sources/BackgroundComputerUseServer"
        ),
        .executableTarget(
            name: "BackgroundComputerUseLockedRecovery",
            dependencies: ["BackgroundComputerUseLockedInstaller"],
            path: "Sources/BackgroundComputerUseLockedRecovery"
        ),
        .executableTarget(
            name: "BackgroundComputerUseLockedBrokerService",
            dependencies: ["BackgroundComputerUseLockedBroker", "BackgroundComputerUseLockedShared", "BackgroundComputerUseControlShared"],
            path: "Sources/BackgroundComputerUseLockedBrokerService"
        ),
        .executableTarget(
            name: "BackgroundComputerUseCoreXPCService",
            dependencies: ["BackgroundComputerUseControlShared"],
            path: "Sources/BackgroundComputerUseCoreXPCService"
        ),
        .testTarget(
            name: "BackgroundComputerUseTests",
            dependencies: [
                "BackgroundComputerUse",
                "BackgroundComputerUseControlShared",
                "BackgroundComputerUseControl",
                "BackgroundComputerUseLockedShared",
                "BackgroundComputerUseLockedBroker",
                "BCUAuthorizationPlugin",
                "BackgroundComputerUseLockedInstaller",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/BackgroundComputerUseTests"
        ),
    ]
)
