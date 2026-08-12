// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SolarFlowMonitor",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SolarFlowMonitor", targets: ["SolarFlowMonitor"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "SolarFlowMonitor",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/SolarFlowMonitor"
        ),
        .testTarget(
            name: "SolarFlowMonitorTests",
            dependencies: ["SolarFlowMonitor"],
            path: "Tests/SolarFlowMonitorTests"
        )
    ]
)
