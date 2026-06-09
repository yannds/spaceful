// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Spaceful",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Spaceful", targets: ["Spaceful"])
    ],
    targets: [
        .executableTarget(
            name: "Spaceful",
            path: "Sources/Spaceful"
        )
    ]
)
