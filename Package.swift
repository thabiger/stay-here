// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NamedSpaces",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NamedSpacesApp", targets: ["NamedSpacesApp"])
    ],
    targets: [
        .target(name: "Core", path: "NamedSpaces/Core"),
        .target(name: "Activation", dependencies: ["Core"], path: "NamedSpaces/Activation"),
        .target(name: "Shared", path: "NamedSpaces/Shared"),
        .executableTarget(
            name: "NamedSpacesApp",
            dependencies: ["Core", "Activation", "Shared"],
            path: "NamedSpaces/App"
        )
    ]
)
