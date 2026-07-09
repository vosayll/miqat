import XCTest
@testable import Miqat

/// Разбор ответов Aladhan на реальных фикстурах (сырые ответы API, сохранены
/// 2026-07-09) + обрезка суффикса " (TZ)", маппинг в CalendarDay, конвертация
/// "HH:mm" → Date с переходом через полночь, карта регион→метод.
final class PrayerAPITests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    // MARK: - Обрезка суффикса "HH:mm (TZ)"

    func testStripTimezoneSuffix() {
        XCTAssertEqual(AladhanTime.strip("02:31 (MSK)"), "02:31")
        XCTAssertEqual(AladhanTime.strip("21:24"), "21:24")
        XCTAssertEqual(AladhanTime.strip("04:18 (+03)"), "04:18")
    }

    // MARK: - /timings (один день) — ключи С Заглавной, без суффикса

    func testDecodeTimingsGrozny() throws {
        let day = try JSONDecoder()
            .decode(AladhanEnvelope<AladhanDay>.self, from: fixture("aladhan-timings-grozny")).data
        let cd = AladhanAPI.calendarDay(day)
        XCTAssertEqual(cd.date, "2026-07-09")       // "09-07-2026" → ISO
        XCTAssertEqual(cd.fajr, "02:31")            // метод 14 (ДУМ России)
        XCTAssertEqual(cd.dhuhr, "12:02")
        XCTAssertEqual(cd.maghrib, "19:39")
        XCTAssertEqual(cd.isha, "21:24")
        XCTAssertEqual(cd.hijri, "24-01-1448")      // дата по Хиджре из ответа
    }

    // MARK: - /calendar (месяц) — суффикс " (MSK)" у времён, 31 день

    func testDecodeCalendarGrozny() throws {
        let days = try JSONDecoder()
            .decode(AladhanEnvelope<[AladhanDay]>.self, from: fixture("aladhan-calendar-grozny-2026-07")).data
            .map(AladhanAPI.calendarDay)
        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(days[0].date, "2026-07-01")
        XCTAssertEqual(days[0].fajr, "02:23")       // суффикс " (MSK)" срезан
        XCTAssertFalse(days[0].isha.contains("("))  // ни у одного времени нет суффикса
        XCTAssertEqual(days[8].date, "2026-07-09")
        XCTAssertEqual(days[8].fajr, "02:31")       // совпадает с /timings на тот же день
        XCTAssertEqual(days[8].isha, "21:24")
    }

    func testDecodeCalendarMoscow() throws {
        let days = try JSONDecoder()
            .decode(AladhanEnvelope<[AladhanDay]>.self, from: fixture("aladhan-calendar-moscow-2026-07")).data
            .map(AladhanAPI.calendarDay)
        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(days[8].date, "2026-07-09")
        XCTAssertEqual(days[8].maghrib, "21:11")    // высокие широты, метод 14 / ханафи
        XCTAssertEqual(days[8].isha, "22:53")
    }

    // MARK: - "HH:mm" → Date

    /// Обычный день: все шесть времён на своей дате, по возрастанию.
    func testDatesPlainDay() throws {
        let day = CalendarDay(date: "2026-07-09", fajr: "02:31", sunrise: "04:26",
                              dhuhr: "12:02", asr: "16:07", maghrib: "19:39", isha: "21:24")
        let dates = try XCTUnwrap(PrayerStore.dates(for: day, timezone: "Europe/Moscow"))
        XCTAssertEqual(dates.count, 6)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(PrayerStore.dayKey(dates[0], timezone: "Europe/Moscow"), "2026-07-09")
        XCTAssertEqual(PrayerStore.dayKey(dates[5], timezone: "Europe/Moscow"), "2026-07-09")
    }

    /// Высокие широты: Isha "00:35" < Maghrib "21:12" → Isha уходит на следующий
    /// календарный день, отсчёт до неё не ломается.
    func testDatesIshaAfterMidnight() throws {
        let day = CalendarDay(date: "2026-07-08", fajr: "00:34", sunrise: "03:57",
                              dhuhr: "12:36", asr: "18:18", maghrib: "21:12", isha: "00:35")
        let dates = try XCTUnwrap(PrayerStore.dates(for: day, timezone: "Europe/Moscow"))
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(PrayerStore.dayKey(dates[0], timezone: "Europe/Moscow"), "2026-07-08")
        // Isha 00:35 — уже 9 июля, позже Maghrib.
        XCTAssertEqual(PrayerStore.dayKey(dates[5], timezone: "Europe/Moscow"), "2026-07-09")
        XCTAssertGreaterThan(dates[5], dates[4])
        XCTAssertEqual(dates[5].timeIntervalSince(dates[4]), 3 * 3600 + 23 * 60)  // 21:12 → 00:35
    }

    // MARK: - Карта регион → метод (PrayerMethod)

    func testMethodMapRussiaByRegion() {
        // Кавказ → шафии (school 0), метод ДУМ России (14).
        for area in ["Chechnya", "Республика Дагестан", "Ingushetia",
                     "Kabardino-Balkar Republic", "Karachay-Cherkess Republic",
                     "North Ossetia", "Republic of Adygea"] {
            let c = PrayerMethod.choice(countryCode: "RU", administrativeArea: area)
            XCTAssertEqual(c.method, 14, "\(area)")
            XCTAssertEqual(c.school, 0, "Кавказ шафии: \(area)")
        }
        // Остальная Россия → ханафи (school 1).
        for area in ["Moscow", "Республика Татарстан", "Bashkortostan"] {
            let c = PrayerMethod.choice(countryCode: "RU", administrativeArea: area)
            XCTAssertEqual(c.method, 14)
            XCTAssertEqual(c.school, 1, "не-Кавказ ханафи: \(area)")
        }
        // Регион неизвестен → метод 14, фолбэк-мазхаб шафии.
        let unknown = PrayerMethod.choice(countryCode: "RU", administrativeArea: nil)
        XCTAssertEqual(unknown, PrayerMethodChoice(method: 14, school: 0))
    }

    func testMethodMapCountries() {
        XCTAssertEqual(PrayerMethod.choice(countryCode: "TR", administrativeArea: nil).method, 13)
        XCTAssertEqual(PrayerMethod.choice(countryCode: "SA", administrativeArea: nil).method, 4)
        XCTAssertEqual(PrayerMethod.choice(countryCode: "EG", administrativeArea: nil).method, 5)
        XCTAssertEqual(PrayerMethod.choice(countryCode: "IR", administrativeArea: nil).method, 7)
        XCTAssertEqual(PrayerMethod.choice(countryCode: "AE", administrativeArea: nil).method, 16)
        XCTAssertEqual(PrayerMethod.choice(countryCode: "KW", administrativeArea: nil).method, 9)
        XCTAssertEqual(PrayerMethod.choice(countryCode: "QA", administrativeArea: nil).method, 10)
        XCTAssertEqual(PrayerMethod.choice(countryCode: "US", administrativeArea: nil).method, 2)
        XCTAssertEqual(PrayerMethod.choice(countryCode: "CA", administrativeArea: nil).method, 2)
        // Прочие страны → MWL (3), шафии.
        XCTAssertEqual(PrayerMethod.choice(countryCode: "DE", administrativeArea: nil),
                       PrayerMethodChoice(method: 3, school: 0))
        // Страна неизвестна → фолбэк ДУМ России (основная аудитория).
        XCTAssertEqual(PrayerMethod.choice(countryCode: nil, administrativeArea: nil),
                       PrayerMethodChoice(method: 14, school: 0))
    }

    // MARK: - Кеш

    /// Ключ кеша: координаты округлены до 2 знаков — GPS-дрожание не сбрасывает кеш.
    func testCacheFileNameRounding() {
        let name = PrayerCache.fileName(latitude: PrayerStore.round2(43.3178),
                                        longitude: PrayerStore.round2(45.6949),
                                        method: 14, school: 0, year: 2026, month: 7)
        XCTAssertEqual(name, "calendar_43.32_45.69_m14_s0_2026-07.json")
        let jitter = PrayerCache.fileName(latitude: PrayerStore.round2(43.3211),
                                          longitude: PrayerStore.round2(45.6893),
                                          method: 14, school: 0, year: 2026, month: 7)
        XCTAssertEqual(jitter, name)                    // дрожание в пределах ~1 км — тот же файл
    }

    /// CachedMonth ездит на диск и обратно без потерь (включая hijri).
    func testCachedMonthRoundTrip() throws {
        let days = try JSONDecoder()
            .decode(AladhanEnvelope<[AladhanDay]>.self, from: fixture("aladhan-calendar-grozny-2026-07")).data
            .map(AladhanAPI.calendarDay)
        let month = CachedMonth(latitude: 43.32, longitude: 45.7, method: 14, school: 0,
                                year: 2026, month: 7, timezone: "Europe/Moscow",
                                fetchedAt: Date(), days: days)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(CachedMonth.self, from: encoder.encode(month))
        XCTAssertEqual(back.days.count, 31)
        XCTAssertEqual(back.days[8].fajr, "02:31")
        XCTAssertEqual(back.days[8].hijri, "24-01-1448")
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
