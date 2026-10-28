// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SonicRoute",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SonicRouteCore", targets: ["SonicRouteCore"]),
        .executable(name: "SonicRoute", targets: ["SonicRoute"])
    ],
    targets: [
        .target(
            name: "SonicRouteCore",
            path: "Sources/SonicRouteCore"
        ),
        .executableTarget(
            name: "SonicRoute",
            dependencies: ["SonicRouteCore"],
            path: "Sources/SonicRoute",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "SonicRouteCoreTests",
            dependencies: ["SonicRouteCore"],
            path: "Tests/SonicRouteCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
