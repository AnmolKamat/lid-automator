// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lid-automator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "lid-automator",
            targets: ["lid-automator"]
        )
    ],
    targets: [
        .executableTarget(
            name: "lid-automator",
            path: "Sources/lid-automator"
        )
    ]
)
