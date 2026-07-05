// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "Miqat",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Расчёт времён намаза на устройстве (проверенная open-source библиотека).
        .package(url: "https://github.com/batoulapps/adhan-swift.git", from: "1.5.0"),
        // Показ окна на заблокированном экране (обёртка над приватным SkyLight API).
        .package(url: "https://github.com/Lakr233/SkyLightWindow", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Miqat",
            dependencies: [
                .product(name: "Adhan", package: "adhan-swift"),
                .product(name: "SkyLightWindow", package: "SkyLightWindow"),
            ]
        ),
    ]
)
