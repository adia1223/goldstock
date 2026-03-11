// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GoldStock",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "GoldStock",
            path: "Sources"
        )
    ]
)
