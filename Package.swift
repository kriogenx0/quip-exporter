// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuipExporter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "QuipExporter",
            path: "Sources/QuipExporter",
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .testTarget(
            name: "QuipExporterTests",
            dependencies: ["QuipExporter"],
            path: "Tests/QuipExporterTests"
        )
    ]
)
