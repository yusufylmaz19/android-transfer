// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AndroidTransfer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AndroidTransfer", targets: ["AndroidTransfer"])],
    targets: [.executableTarget(name: "AndroidTransfer")]
)
