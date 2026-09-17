// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Softfall",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Softfall", path: "Sources/Softfall")
    ]
)
