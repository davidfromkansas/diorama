// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Diorama",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Diorama", targets: ["DioramaApp"]), .executable(name: "DioramaReporter", targets: ["DioramaReporter"])],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1")
    ],
    targets: [
        .target(name: "DioramaCore"),
        .executableTarget(name: "DioramaReporter", dependencies: ["DioramaCore"]),
        .executableTarget(name: "DioramaApp", dependencies: ["DioramaCore", .product(name: "MarkdownUI", package: "swift-markdown-ui")],
                          resources: [.copy("Resources/Library"), .copy("Resources/ConnectorBrand"), .copy("Resources/AgentStatus"), .copy("Resources/Capybara"), .copy("Resources/OfficeFurniture")],
                          swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "DioramaCoreTests", dependencies: ["DioramaCore"]),
        .testTarget(name: "DioramaRenderingTests", dependencies: ["DioramaApp"])
    ]
)
