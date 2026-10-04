// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Diorama",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Diorama", targets: ["DioramaApp"]), .executable(name: "DioramaReporter", targets: ["DioramaReporter"])],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "DioramaCore"),
        .executableTarget(name: "DioramaReporter", dependencies: ["DioramaCore"]),
        .executableTarget(name: "DioramaApp", dependencies: ["DioramaCore", .product(name: "MarkdownUI", package: "swift-markdown-ui"), .product(name: "Sparkle", package: "Sparkle")],
                          resources: [.copy("Resources/Library"), .copy("Resources/ConnectorBrand"), .copy("Resources/AgentStatus"), .copy("Resources/Capybara"), .copy("Resources/OfficeFurniture")],
                          swiftSettings: [.defaultIsolation(MainActor.self)],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "DioramaCoreTests", dependencies: ["DioramaCore"]),
        .testTarget(name: "DioramaRenderingTests", dependencies: ["DioramaApp"])
    ]
)
