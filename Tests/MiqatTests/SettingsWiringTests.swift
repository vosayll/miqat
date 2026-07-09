import XCTest
import CoreLocation
@testable import Miqat

/// Стыковка окна настроек с движком: ключи UserDefaults, которые пишет
/// SettingsView, должны реально менять поведение читателей.
final class SettingsWiringTests: XCTestCase {

    private let defaults = UserDefaults.standard
    private let keys = ["calcMethod", "asrSchool", "methodAuto", "autoLocation",
                        "manualLat", "manualLon", "manualCity", "notifyEnabled",
                        "notifyLeadMinutes"]

    override func tearDown() {
        keys.forEach { defaults.removeObject(forKey: $0) }
        PrayerEngine.gpsCoordinate = nil
        PrayerEngine.gpsCityName = nil
        PrayerEngine.gpsCountryCode = nil
        PrayerEngine.gpsAdminArea = nil
        PrayerEngine.manualCountryCode = nil
        PrayerEngine.manualAdminArea = nil
        super.tearDown()
    }

    // MARK: - Метод и мазхаб для Aladhan

    /// Дефолт — авто: без региона фолбэк ДУМ России (14) + шафии (0).
    func testMethodDefaultsAuto() {
        XCTAssertEqual(PrayerStore.method, 14)
        XCTAssertEqual(PrayerStore.school, 0)
    }

    /// Авто по региону (GPS): Кавказ → 14/шафии, Казань → 14/ханафи, Стамбул → 13.
    func testMethodAutoByRegion() {
        PrayerEngine.gpsCountryCode = "RU"
        PrayerEngine.gpsAdminArea = "Chechnya"
        XCTAssertEqual(PrayerStore.method, 14)
        XCTAssertEqual(PrayerStore.school, 0)

        PrayerEngine.gpsAdminArea = "Republic of Tatarstan"
        XCTAssertEqual(PrayerStore.school, 1)   // ханафи

        PrayerEngine.gpsCountryCode = "TR"
        PrayerEngine.gpsAdminArea = nil
        XCTAssertEqual(PrayerStore.method, 13)
    }

    /// Явный выбор метода: методAuto=false → берутся calcMethod/asrSchool.
    func testMethodExplicitOverridesAuto() {
        PrayerEngine.gpsCountryCode = "RU"
        PrayerEngine.gpsAdminArea = "Chechnya"
        defaults.set(false, forKey: "methodAuto")
        defaults.set(3, forKey: "calcMethod")   // MWL
        defaults.set(1, forKey: "asrSchool")    // Ханафи
        XCTAssertEqual(PrayerStore.method, 3)
        XCTAssertEqual(PrayerStore.school, 1)
    }

    /// Смена региона меняет ключ кеша → старый файл не подойдёт, будет новая загрузка.
    func testRegionChangesCacheKey() {
        let name = { PrayerCache.fileName(latitude: 43.32, longitude: 45.69,
                                          method: PrayerStore.method, school: PrayerStore.school,
                                          year: 2026, month: 7) }
        PrayerEngine.gpsCountryCode = "RU"
        PrayerEngine.gpsAdminArea = "Chechnya"
        let grozny = name()
        XCTAssertEqual(grozny, "calendar_43.32_45.69_m14_s0_2026-07.json")
        PrayerEngine.gpsCountryCode = "TR"
        PrayerEngine.gpsAdminArea = nil
        XCTAssertNotEqual(grozny, name())       // метод сменился → другой файл
    }

    // MARK: - Ручная локация

    func testManualLocationOverridesGPS() {
        PrayerEngine.gpsCoordinate = CLLocationCoordinate2D(latitude: 43.32, longitude: 45.69)
        PrayerEngine.gpsCityName = "Грозный"

        defaults.set(false, forKey: "autoLocation")
        defaults.set(55.7558, forKey: "manualLat")
        defaults.set(37.6173, forKey: "manualLon")
        defaults.set("Москва", forKey: "manualCity")

        XCTAssertEqual(PrayerEngine.coordinate.latitude, 55.7558)
        XCTAssertEqual(PrayerEngine.coordinate.longitude, 37.6173)
        XCTAssertEqual(PrayerEngine.cityName, "Москва")

        // GPS-фикс пришёл позже — ручную локацию не перетирает.
        PrayerEngine.gpsCoordinate = CLLocationCoordinate2D(latitude: 41.0, longitude: 28.9)
        XCTAssertEqual(PrayerEngine.coordinate.latitude, 55.7558)

        // Вернули авто — снова GPS.
        defaults.set(true, forKey: "autoLocation")
        XCTAssertEqual(PrayerEngine.coordinate.latitude, 41.0)
    }

    /// Незаполненные ручные координаты (0; 0) — не Гвинейский залив, а «нет локации»:
    /// остаёмся на GPS/фоллбэке.
    func testManualLocationEmptyFieldsIgnored() {
        defaults.set(false, forKey: "autoLocation")
        XCTAssertEqual(PrayerEngine.coordinate.latitude, PrayerEngine.grozny.latitude)
        XCTAssertEqual(PrayerEngine.cityName, "Грозный")
    }

    /// Город не введён — показываем координаты, а не пустую строку.
    func testManualCityFallsBackToCoordinates() {
        defaults.set(false, forKey: "autoLocation")
        defaults.set(55.75, forKey: "manualLat")
        defaults.set(37.62, forKey: "manualLon")
        XCTAssertEqual(PrayerEngine.cityName, "55.75, 37.62")
    }

    // MARK: - Уведомления

    func testNotifySettings() {
        XCTAssertTrue(NotificationScheduler.enabled)        // дефолт — включены
        XCTAssertEqual(NotificationScheduler.leadMinutes, 0)

        defaults.set(false, forKey: "notifyEnabled")
        defaults.set(15, forKey: "notifyLeadMinutes")
        XCTAssertFalse(NotificationScheduler.enabled)
        XCTAssertEqual(NotificationScheduler.leadMinutes, 15)

        defaults.set(999, forKey: "notifyLeadMinutes")      // мусор клампится в 0–60
        XCTAssertEqual(NotificationScheduler.leadMinutes, 60)
        defaults.set(-5, forKey: "notifyLeadMinutes")
        XCTAssertEqual(NotificationScheduler.leadMinutes, 0)
    }

    func testNotificationBodyText() {
        let time = Date()
        XCTAssertEqual(NotificationScheduler.body(time: time, lead: 0),
                       "Время намаза · \(Format.clock(time))")
        XCTAssertEqual(NotificationScheduler.body(time: time, lead: 10),
                       "Через 10 мин · \(Format.clock(time))")
    }
}
