// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Softfall",
    platforms: [.macOS(.v14)],
    dependencies: [
        // In-app updates. Sparkle is the framework nearly every independently
        // distributed Mac app uses for this; it downloads the release, checks
        // its signature, swaps the bundle out from under a running app, clears
        // quarantine and relaunches — every one of which is a thing that goes
        // wrong when done by hand.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Softfall",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Softfall",
            linkerSettings: [
                // Sparkle is a dynamic framework. The bundle carries it in
                // Contents/Frameworks (see Scripts/build-app.sh), so the
                // binary has to know to look there.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
