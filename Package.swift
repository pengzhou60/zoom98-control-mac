// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Zoom98Mac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Zoom98Mac", targets: ["Zoom98Mac"]),
    ],
    targets: [
        .executableTarget(
            name: "Zoom98Mac",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreBluetooth"),
            ]
        ),
    ]
)
