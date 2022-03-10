// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "LibTIFF",
    products: [
        .library(name: "LibTIFF", targets: ["LibTIFF"])
    ],
    dependencies: [
        // .package(url: "https://github.com/mrwerdo/Geometry", from: "1.0.0")
        .package(path: "../Geometry"),
    ],
    targets: [
        .target(name: "CLibTIFF", exclude: ["README", "VERSION", "ChangeLog", "COPYRIGHT", "mkg3states.c"]),
        .target(name: "LibTIFF", dependencies: ["CLibTIFF", "Geometry"]),
        .testTarget(name: "LibTIFFTests", dependencies: ["LibTIFF"])
    ]
)
