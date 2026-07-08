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
    static var coordinate = grozny
    static var cityName = "Грозный"
    static let madhab: Madhab = .shafi

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
        if source != "local",
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

}
