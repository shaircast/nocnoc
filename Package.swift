// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "nocnoc",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "nocnoc", targets: ["Knock"]),
    ],
    targets: [
        .executableTarget(
            name: "Knock"
        ),
    ]
)
