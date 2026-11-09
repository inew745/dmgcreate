// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DMGCreator",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DMGCreator",
            path: "Sources/DMGCreator"
        )
    ]
)
