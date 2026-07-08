import XCTest
@testable import Miqat

/// Разбор ответов siylaha-qoran.ru на реальных фикстурах (сырые ответы API,
/// сохранены 2026-07-08) + конвертация "HH:mm" → Date с переходом через полночь.
final class PrayerAPITests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    // MARK: /calculate — двойная обёртка data.data, ключи С Заглавной

    func testDecodeCalculateMoscow() throws {
        let day = try JSONDecoder()
            .decode(APIEnvelope<CalculateDay>.self, from: fixture("calculate-moscow"))
            .data.data
        XCTAssertEqual(day.timings.fajr, "00:34")
        XCTAssertEqual(day.timings.maghrib, "21:12")
        XCTAssertEqual(day.timings.isha, "00:35")       // «выпала за полночь»
        XCTAssertEqual(day.timings.midnight, "22:53")
        XCTAssertEqual(day.timezone, "Europe/Moscow")
        XCTAssertEqual(day.method, 3)
    }

    func testDecodeCalculateGrozny() throws {
        let day = try JSONDecoder()
            .decode(APIEnvelope<CalculateDay>.self, from: fixture("calculate-grozny"))
            .data.data
        XCTAssertEqual(day.timings.fajr, "02:09")
        XCTAssertEqual(day.timings.isha, "21:44")
        XCTAssertEqual(day.qibla ?? 0, 194.45, accuracy: 0.01)
    }

    // MARK: /calendar — двойная обёртка, ключи в нижнем регистре, 31 день

    func testDecodeCalendarGrozny() throws {
        let days = try JSONDecoder()
            .decode(APIEnvelope<[CalendarDay]>.self, from: fixture("calendar-grozny-2026-07"))
            .data.data
        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(days[0].date, "2026-07-01")
        XCTAssertEqual(days[0].fajr, "02:02")
        XCTAssertEqual(days[7].date, "2026-07-08")
        XCTAssertEqual(days[7].isha, "21:44")           // совпадает с /calculate на тот же день
    }

    // MARK: "HH:mm" → Date

    /// Обычный день: все шесть времён на своей дате, по возрастанию.
    func testDatesPlainDay() throws {
        let day = CalendarDay(date: "2026-07-08", fajr: "02:09", sunrise: "04:25",
                              dhuhr: "12:03", asr: "16:07", maghrib: "19:39", isha: "21:44")
        let dates = try XCTUnwrap(PrayerStore.dates(for: day, timezone: "Europe/Moscow"))
        XCTAssertEqual(dates.count, 6)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(PrayerStore.dayKey(dates[0], timezone: "Europe/Moscow"), "2026-07-08")
        XCTAssertEqual(PrayerStore.dayKey(dates[5], timezone: "Europe/Moscow"), "2026-07-08")
    }

    /// Высокие широты: Isha "00:35" < Maghrib "21:12" → Isha уходит на следующий
    /// календарный день, отсчёт до неё не ломается.
    func testDatesIshaAfterMidnight() throws {
        let day = CalendarDay(date: "2026-07-08", fajr: "00:34", sunrise: "03:57",
                              dhuhr: "12:36", asr: "18:18", maghrib: "21:12", isha: "00:35")
        let dates = try XCTUnwrap(PrayerStore.dates(for: day, timezone: "Europe/Moscow"))
        XCTAssertEqual(dates, dates.sorted())
        // Fajr 00:34 — раннее утро того же дня.
        XCTAssertEqual(PrayerStore.dayKey(dates[0], timezone: "Europe/Moscow"), "2026-07-08")
        // Isha 00:35 — уже 9 июля, позже Maghrib.
        XCTAssertEqual(PrayerStore.dayKey(dates[5], timezone: "Europe/Moscow"), "2026-07-09")
        XCTAssertGreaterThan(dates[5], dates[4])
        XCTAssertEqual(dates[5].timeIntervalSince(dates[4]), 3 * 3600 + 23 * 60)  // 21:12 → 00:35
    }

    // MARK: - Кеш

    /// Ключ кеша: координаты округлены до 2 знаков — GPS-дрожание не сбрасывает кеш.
    func testCacheFileNameRounding() {
        let name = PrayerCache.fileName(latitude: PrayerStore.round2(43.3178),
                                        longitude: PrayerStore.round2(45.6949),
                                        method: 3, school: 0, year: 2026, month: 7)
        XCTAssertEqual(name, "calendar_43.32_45.69_m3_s0_2026-07.json")
        let jitter = PrayerCache.fileName(latitude: PrayerStore.round2(43.3211),
                                          longitude: PrayerStore.round2(45.6893),
                                          method: 3, school: 0, year: 2026, month: 7)
        XCTAssertEqual(jitter, name)                    // дрожание в пределах ~1 км — тот же файл
    }

    /// CachedMonth ездит на диск и обратно без потерь.
    func testCachedMonthRoundTrip() throws {
        let days = try JSONDecoder()
            .decode(APIEnvelope<[CalendarDay]>.self, from: fixture("calendar-grozny-2026-07"))
            .data.data
        let month = CachedMonth(latitude: 43.32, longitude: 45.7, method: 3, school: 0,
                                year: 2026, month: 7, timezone: "Europe/Moscow",
                                fetchedAt: Date(), days: days)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(CachedMonth.self, from: encoder.encode(month))
        XCTAssertEqual(back.days.count, 31)
        XCTAssertEqual(back.days[7].fajr, "02:09")
        XCTAssertEqual(back.timezone, "Europe/Moscow")
    }

    // MARK: - Цепочка источников

    /// prayerSource="local" — только локальный Adhan (калибровка Грозного),
    /// а поправки из "prayerOffsets" применяются поверх.
    func testLocalSourceAndOffsets() throws {
        let defaults = UserDefaults.standard
        defaults.set("local", forKey: "prayerSource")
        defer {
            defaults.removeObject(forKey: "prayerSource")
            defaults.removeObject(forKey: "prayerOffsets")
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let noon = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12)))

        let base = PrayerEngine.chips(on: noon)
        XCTAssertEqual(base.count, 6)

        defaults.set(["Fajr": 5, "Isha": -3], forKey: "prayerOffsets")
        let shifted = PrayerEngine.chips(on: noon)
        XCTAssertEqual(shifted[0].time.timeIntervalSince(base[0].time), 5 * 60)
        XCTAssertEqual(shifted[5].time.timeIntervalSince(base[5].time), -3 * 60)
        XCTAssertEqual(shifted[2].time, base[2].time)   // без поправки — без сдвига
    }
}
