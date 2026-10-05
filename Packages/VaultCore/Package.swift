// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VaultCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ChiikawaCrypto", targets: ["ChiikawaCrypto"]),
        .library(name: "VaultwardenAPI", targets: ["VaultwardenAPI"]),
    ],
    targets: [
        .target(name: "ChiikawaCrypto"),
        .target(name: "VaultwardenAPI", dependencies: ["ChiikawaCrypto"]),
        .testTarget(name: "ChiikawaCryptoTests", dependencies: ["ChiikawaCrypto"]),
        .testTarget(name: "VaultwardenAPITests", dependencies: ["VaultwardenAPI"]),
    ]
)
