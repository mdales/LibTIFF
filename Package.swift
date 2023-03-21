// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "LibTIFF",
    products: [
        .library(name: "LibTIFF", targets: ["LibTIFF"])
    ],
    dependencies: [
        .package(url: "https://github.com/mrwerdo/Geometry", branch: "master")
        //.package(path: "../Geometry"),
    ],
    targets: [
        .target(name: "CLibTIFF", exclude: ["README", "VERSION", "ChangeLog", "COPYRIGHT", "mkg3states.c"]),
        .target(name: "LibTIFF", dependencies: ["CLibTIFF", "Geometry"]),
        .testTarget(name: "LibTIFFTests", dependencies: ["LibTIFF"])
    ]
)
