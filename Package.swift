// swift-tools-version: 5.7
import PackageDescription
import Foundation

// Две сборки из одной кодовой базы:
//
//  • ОБЫЧНАЯ (по умолчанию) — для ПРЯМОЙ раздачи .app/.dmg с сайта. Подключает
//    приватные API (CGS Spaces + SkyLight): островок виден на всех рабочих
//    столах и на заблокированном экране. Apple в App Store такую НЕ примет.
//
//  • ДЛЯ APP STORE (переменная окружения MIQAT_APPSTORE=1) — только публичные
//    API. Пакет SkyLightWindow и приватные обёртки (CGSSpace.swift,
//    SkyLightLock.swift) НЕ подключаются вовсе — чтобы приватных символов не
//    было даже в бинаре (Apple ловит их статическим анализом). Задаётся флаг
//    компиляции APPSTORE — по нему код выбирает публичные аналоги (см. #if
//    APPSTORE в SpacePlacement.swift).
//
// Сборка варианта для App Store — скриптом packaging/build_appstore.sh.
let appStore = ProcessInfo.processInfo.environment["MIQAT_APPSTORE"] == "1"

var packageDependencies: [Package.Dependency] = [
    // Расчёт времён намаза на устройстве (проверенная open-source библиотека).
    .package(url: "https://github.com/batoulapps/adhan-swift.git", from: "1.5.0"),
]
var targetDependencies: [Target.Dependency] = [
    .product(name: "Adhan", package: "adhan-swift"),
]
var swiftSettings: [SwiftSetting] = []

if appStore {
    swiftSettings.append(.define("APPSTORE"))
} else {
    // Показ окна на заблокированном экране (обёртка над приватным SkyLight API).
    // В App Store-сборке не подключается.
    packageDependencies.append(.package(url: "https://github.com/Lakr233/SkyLightWindow", from: "1.0.0"))
    targetDependencies.append(.product(name: "SkyLightWindow", package: "SkyLightWindow"))
}

let package = Package(
    name: "Miqat",
    platforms: [.macOS(.v13)],
    dependencies: packageDependencies,
    targets: [
        .executableTarget(
            name: "Miqat",
            dependencies: targetDependencies,
            // Встроенный каталог городов (срез GeoNames) — читается через Bundle.module.
            resources: [.copy("Resources/cities.tsv")],
            swiftSettings: swiftSettings
        ),
        // Тесты разбора ответов API времён намаза (фикстуры — реальные ответы).
        .testTarget(
            name: "MiqatTests",
            dependencies: ["Miqat"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
