import XCTest
import CoreLocation
@testable import Miqat

/// Каталог городов GeoNames: загрузка из бандла, ближайший к координате, поиск.
final class CityCatalogTests: XCTestCase {

    private let catalog = CityCatalog.shared

    func testCatalogLoads() {
        XCTAssertGreaterThan(catalog.count, 60_000, "каталог должен загрузиться из бандла")
    }

    /// Ближайший к точке Грозного — сам Грозный (geonameId 558418).
    func testNearestGrozny() throws {
        let c = try XCTUnwrap(catalog.nearest(to: .init(latitude: 43.3178, longitude: 45.6949)))
        XCTAssertEqual(c.id, 558418)
        XCTAssertEqual(c.timezone, "Europe/Moscow")
        XCTAssertEqual(c.country, "RU")
    }

    /// Точка в центре Москвы → Москва (524901), а не подмосковный посёлок.
    func testNearestMoscow() throws {
        let c = try XCTUnwrap(catalog.nearest(to: .init(latitude: 55.7558, longitude: 37.6173)))
        XCTAssertEqual(c.id, 524901)
    }

    /// Поиск по английскому названию: Грозный находится и координаты верные.
    func testSearchGrozny() {
        let hits = catalog.search("grozny")
        let g = hits.first { $0.id == 558418 }
        XCTAssertNotNil(g, "Грозный должен найтись по 'grozny'")
        XCTAssertEqual(g?.latitude ?? 0, 43.31195, accuracy: 0.001)
    }

    /// Одноимённые города ранжируются по населению: столица Москва — первой.
    func testSearchRanksByPopulation() throws {
        let hits = catalog.search("moscow")
        let first = try XCTUnwrap(hits.first)
        XCTAssertEqual(first.id, 524901, "самая крупная Москва должна быть первой")
    }

    /// Слишком короткий запрос не сканирует весь мир.
    func testShortQueryEmpty() {
        XCTAssertTrue(catalog.search("g").isEmpty)
    }
}
