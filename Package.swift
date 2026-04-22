// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KapiBoard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DashboardCore", targets: ["DashboardCore"]),
        .executable(name: "DashboardApp", targets: ["DashboardApp"])
    ],
    targets: [
        .target(
            name: "DashboardCore",
            path: "DashboardCore/Sources/DashboardCore"
        ),
        .executableTarget(
            name: "DashboardApp",
            dependencies: ["DashboardCore"],
            path: "DashboardApp/Sources"
        )
    ]
)

