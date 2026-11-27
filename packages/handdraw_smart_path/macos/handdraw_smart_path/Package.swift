// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "handdraw_smart_path",
  platforms: [.macOS("10.15")],
  products: [
    .library(name: "handdraw-smart-path", targets: ["handdraw_smart_path"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "handdraw_smart_path",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ]
    )
  ]
)

