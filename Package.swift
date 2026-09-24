// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "PicGen",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .executable(name: "PicGenApp", targets: ["PicGenApp"])
    ],
    targets: [
        .executableTarget(
            name: "PicGenApp",
            path: "Sources/PicGenApp"
        )
    ]
)
