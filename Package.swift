// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "greendot",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "StatusCore"),
        .executableTarget(
            name: "greendot",
            dependencies: ["StatusCore"]
        ),
        .testTarget(
            name: "StatusCoreTests",
            dependencies: ["StatusCore"]
        ),
        .testTarget(
            name: "greendotTests",
            dependencies: ["greendot", "StatusCore"]
        )
    ]
)
