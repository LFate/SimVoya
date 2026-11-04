// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SimVoya", platforms: [.macOS(.v14)], products: [.executable(name: "SimVoya", targets: ["SimVoya"])], targets: [.executableTarget(name: "SimVoya"), .testTarget(name: "SimVoyaTests", dependencies: ["SimVoya"])])
