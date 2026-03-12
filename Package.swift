// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VoxelEd",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "VoxelEd",
            targets: ["VoxelEd"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VoxelEd",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
