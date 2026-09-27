// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "greendot",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "StatusCore"),
        .target(
            name: "TestSupport",
            dependencies: ["StatusCore"],
            path: "Tests/TestSupport"
        ),
        .executableTarget(
            name: "greendot",
            dependencies: ["StatusCore"]
        ),
        .testTarget(
            name: "StatusCoreTests",
            dependencies: ["StatusCore", "TestSupport"]
        ),
        .testTarget(
            name: "greendotTests",
            dependencies: ["greendot", "StatusCore", "TestSupport"]
        )
    ]
)
