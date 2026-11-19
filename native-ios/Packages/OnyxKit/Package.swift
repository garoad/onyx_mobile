// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OnyxKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "OnyxKit", targets: ["OnyxKit"])],
    targets: [
        .target(name: "OnyxKit"),
        .testTarget(name: "OnyxKitTests", dependencies: ["OnyxKit"], resources: [.copy("Fixtures")]),
    ]
)
