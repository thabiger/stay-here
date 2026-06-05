// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "StayHere",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "StayHereApp", targets: ["StayHereApp"])
    ],
    targets: [
        .target(name: "Core", path: "StayHere/Core"),
        .target(name: "Activation", dependencies: ["Core"], path: "StayHere/Activation", exclude: ["README.md"]),
        .target(name: "Shared", path: "StayHere/Shared", exclude: ["README.md"]),
        .executableTarget(
            name: "StayHereApp",
            dependencies: ["Core", "Activation", "Shared"],
            path: "StayHere/App"
        ),
        .testTarget(
            name: "ActivationTests",
            dependencies: ["Activation", "Core"],
            path: "Tests/ActivationTests"
        )
    ]
)
