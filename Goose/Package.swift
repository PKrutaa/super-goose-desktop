// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Goose",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Goose", targets: ["Goose"])
    ],
    targets: [
        .executableTarget(
            name: "Goose",
            path: "Sources/Goose"
        )
    ]
)
