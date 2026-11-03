// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "MacDynamicBar",
  platforms: [
    .macOS(.v14)
  ],
  targets: [
    .executableTarget(
      name: "MacDynamicBar",
      swiftSettings: [
        .enableUpcomingFeature("ApproachableConcurrency")
      ],
    ),
    .testTarget(
      name: "MacDynamicBarTests",
      dependencies: ["MacDynamicBar"],
      swiftSettings: [
        .enableUpcomingFeature("ApproachableConcurrency")
      ],
    ),
  ]
)
