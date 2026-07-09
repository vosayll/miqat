import Foundation
import CoreLocation
import Adhan

/// Один пункт расписания дня (5 намазов + восход) — для чипов и отсчёта.
struct PrayerChip: Identifiable {
    let id = UUID()
    let name: String
    let time: Date
    let symbol: String   // SF Symbol
}

/// Движок расчёта времён намаза.
///
/// Источники — цепочкой (ключ UserDefaults "prayerSource": "auto" | "api" | "local"):
/// при "auto"/"api" сначала кеш HTTP API (PrayerStore), нет кеша на дату —
/// локальный расчёт Adhan; при "local" — только локальный. Поверх любого
/// источника применяются ручные поправки из UserDefaults "prayerOffsets".
///
/// Локальный расчёт: рядом с Грозным — калибровка муфтията ЧР, иначе MWL.
/// Высокие широты: сначала пробуем угловой расчёт (не портит обычные города),
/// и только если он не вышел (белые ночи) — фоллбэк на правило «седьмой ночи».
enum PrayerEngine {

    static let grozny = CLLocationCoordinate2D(latitude: 43.3178, longitude: 45.6949)
    static let madhab: Madhab = .shafi

    /// Последний GPS-фикс и его город (пишет MiqatApp по данным LocationProvider).
    /// Хранятся отдельно от эффективных значений — GPS не перетирает ручную локацию.
    static var gpsCoordinate: CLLocationCoordinate2D?
    static var gpsCityName: String?

    /// Страна/регион по reverse-geocode (для выбора метода «по региону»).
    /// gps* — из GPS-фикса, manual* — из геокода ручных координат.
    static var gpsCountryCode: String?
    static var gpsAdminArea: String?
    static var manualCountryCode: String?
    static var manualAdminArea: String?

    /// Эффективные страна/регион под текущую локацию (ручная перебивает GPS).
    static var countryCode: String? { manualCoordinate != nil ? manualCountryCode : gpsCountryCode }
    static var adminArea: String?    { manualCoordinate != nil ? manualAdminArea   : gpsAdminArea }

    /// Эффективные координаты: при "autoLocation" == false — ручные из настроек,
    /// иначе GPS; фоллбэк — Грозный.
    static var coordinate: CLLocationCoordinate2D {
        manualCoordinate ?? gpsCoordinate ?? grozny
    }

    /// Отображаемый город: при ручной локации — "manualCity" (или координаты,
    /// если город не введён), иначе GPS-город; фоллбэк — Грозный.
    static var cityName: String {
        guard let manual = manualCoordinate else { return gpsCityName ?? "Грозный" }
        let city = (UserDefaults.standard.string(forKey: "manualCity") ?? "")
            .trimmingCharacters(in: .whitespaces)
        return city.isEmpty ? String(format: "%.2f, %.2f", manual.latitude, manual.longitude) : city
    }

    /// Ручная локация из настроек ("autoLocation" == false + "manualLat"/"manualLon").
    /// (0; 0) — незаполненные поля, а не Гвинейский залив: считаем, что локации нет.
    private static var manualCoordinate: CLLocationCoordinate2D? {
        let d = UserDefaults.standard
        guard d.object(forKey: "autoLocation") as? Bool == false else { return nil }  // дефолт — авто
        let lat = d.double(forKey: "manualLat")
        let lon = d.double(forKey: "manualLon")
        guard abs(lat) <= 90, abs(lon) <= 180, lat != 0 || lon != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    static let names   = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    static let symbols = ["sun.horizon.fill", "sunrise.fill", "sun.max.fill",
                          "sun.min.fill", "sunset.fill", "moon.fill"]

    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    private static func isNearGrozny(_ c: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: c.latitude, longitude: c.longitude)
            .distance(from: CLLocation(latitude: grozny.latitude, longitude: grozny.longitude)) < 60_000
    }

    private static func params(highLat: Bool) -> CalculationParameters {
        if isNearGrozny(coordinate) {
            // Точная калибровка под таблицу муфтията ЧР (Грозный не высокоширотный).
            var p = CalculationMethod.other.params
            p.fajrAngle = 14.75
            p.ishaAngle = 15.65
            p.madhab = madhab
            p.adjustments = PrayerAdjustments(fajr: 0, sunrise: -6, dhuhr: 28,
                                              asr: 8, maghrib: 5, isha: 0)
            return p
        } else {
            var p = CalculationMethod.muslimWorldLeague.params
            p.madhab = madhab
            if highLat { p.highLatitudeRule = .seventhOfTheNight }  // только как фоллбэк
            return p
        }
    }

    private static func prayerTimes(on date: Date) -> PrayerTimes? {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let coords = Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
        // 1) обычный угловой расчёт
        if let pt = PrayerTimes(coordinates: coords, date: comps, calculationParameters: params(highLat: false)) {
            return pt
        }
        // 2) не вышло (белые ночи) → правило высоких широт
        return PrayerTimes(coordinates: coords, date: comps, calculationParameters: params(highLat: true))
    }

    static var qiblaDirection: Double {
        Qibla(coordinates: Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)).direction
    }

    static func chips(on date: Date = Date()) -> [PrayerChip] {
        guard let times = sourceTimes(on: date) else { return [] }
        let offsets = manualOffsets
        return (0..<6).map { i in
            let shift = TimeInterval((offsets[names[i]] ?? 0) * 60)
            return PrayerChip(name: names[i], time: times[i].addingTimeInterval(shift), symbol: symbols[i])
        }
    }

    /// Цепочка источников: API-кеш (при "auto"/"api") → локальный Adhan (запасной всегда).
    private static func sourceTimes(on date: Date) -> [Date]? {
        let source = UserDefaults.standard.string(forKey: "prayerSource") ?? "auto"
        // В «авто» рядом с Грозным берём выверенную ЛОКАЛЬНУЮ калибровку муфтията
        // ЧР — она совпадает с расписанием муфтията точнее любого онлайн-метода.
        let preferLocalGrozny = (source == "auto") && isNearGrozny(coordinate)
        if source != "local", !preferLocalGrozny,
           let api = PrayerStore.shared.times(on: date, coordinate: coordinate) {
            return api
        }
        guard let pt = prayerTimes(on: date) else { return nil }
        return [pt.fajr, pt.sunrise, pt.dhuhr, pt.asr, pt.maghrib, pt.isha]
    }

    /// Ручные поправки «имя намаза → ±минуты» (UserDefaults "prayerOffsets") —
    /// применяются поверх любого источника; по умолчанию пусто. UI будет позже.
    private static var manualOffsets: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: "prayerOffsets") ?? [:])
            .compactMapValues { $0 as? Int }
    }

    static func nextChip(after now: Date = Date()) -> PrayerChip? {
        if let n = chips(on: now).first(where: { $0.time > now }) { return n }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return chips(on: tomorrow).first
    }

    static func activeIndex(now: Date = Date()) -> Int {
        let c = chips(on: now)
        var idx = -1
        for (i, ch) in c.enumerated() where ch.time <= now { idx = i }
        return idx >= 0 ? idx : max(0, c.count - 1)
    }

    static func currentStart(before now: Date = Date()) -> Date {
        if let p = chips(on: now).last(where: { $0.time <= now }) { return p.time }
        let y = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return chips(on: y).last?.time ?? now
    }

    // MARK: - Разрешение метода/мазхаба для онлайн-источника (Aladhan)

    /// Метод авто? (UserDefaults "methodAuto", дефолт true.) При авто метод и
    /// мазхаб берутся из карты PrayerMethod по стране/региону текущей локации;
    /// при выключенном авто — из явных настроек "calcMethod"/"asrSchool".
    static var methodAuto: Bool {
        UserDefaults.standard.object(forKey: "methodAuto") as? Bool ?? true
    }

    /// Эффективная пара (метод, мазхаб) для запроса к Aladhan и ключа кеша.
    static var effectiveMethod: PrayerMethodChoice {
        if methodAuto {
            return PrayerMethod.choice(countryCode: countryCode, administrativeArea: adminArea)
        }
        let d = UserDefaults.standard
        let method = d.object(forKey: "calcMethod") as? Int ?? PrayerMethod.fallback.method
        let school = d.object(forKey: "asrSchool")  as? Int ?? PrayerMethod.fallback.school
        return PrayerMethodChoice(method: method, school: school)
    }

}
