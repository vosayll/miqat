import Foundation
import CoreLocation

/// API-источник времён намаза: отдаёт времена на дату из кеша и сам держит
/// кеш свежим (раз в сутки, при смене локации, плюс следующий месяц заранее).
///
/// Цепочка выбора источника (API-кеш → локальный Adhan) живёт в PrayerEngine;
/// здесь только «дай шесть времён на дату или nil». Все вызовы — с главного
/// потока (таймер ClockModel и делегаты живут на main).
final class PrayerStore {

    static let shared = PrayerStore()

    /// Вызывается на главном потоке, когда скачался свежий календарь —
    /// сигнал пересчитать расписание (источник мог смениться с локального на API).
    var onUpdate: (() -> Void)?

    // Параметры расчёта для Aladhan — коды методов /v1/methods. Берутся из
    // PrayerEngine.effectiveMethod: при "methodAuto" (дефолт) — из карты
    // регион→метод (PrayerMethod) по стране/региону, иначе — из явных настроек
    // "calcMethod"/"asrSchool". Смена значения меняет имя файла кеша → старый
    // не подходит, качается новый.
    static var method: Int { PrayerEngine.effectiveMethod.method }
    static var school: Int { PrayerEngine.effectiveMethod.school }

    private var months: [String: CachedMonth] = [:]   // память: имя файла → месяц
    private var inFlight: Set<String> = []            // что уже качается
    private var lastAttempt: [String: Date] = [:]     // чтобы не долбить API при ошибках

    /// Времена шести пунктов (Fajr…Isha) на дату из кеша, или nil — тогда
    /// наверху сработает фолбэк на локальный расчёт. Заодно тихо обновляет кеш.
    func times(on date: Date, coordinate: CLLocationCoordinate2D) -> [Date]? {
        refreshIfNeeded(around: date, coordinate: coordinate)
        guard let month = cachedMonth(for: date, coordinate: coordinate) else { return nil }
        let key = Self.dayKey(date, timezone: month.timezone)
        guard let day = month.days.first(where: { $0.date == key }) else { return nil }
        return Self.dates(for: day, timezone: month.timezone)
    }

    // MARK: - Обновление кеша

    /// Тянет текущий месяц, а когда до конца месяца < 3 дней — заранее и следующий.
    func refreshIfNeeded(around date: Date, coordinate: CLLocationCoordinate2D) {
        let cal = Calendar(identifier: .gregorian)   // локальная timezone пользователя
        ensureMonth(for: date, coordinate: coordinate, calendar: cal)

        if let end = cal.dateInterval(of: .month, for: date)?.end,
           end.timeIntervalSince(date) < 3 * 86_400,
           let nextMonth = cal.date(byAdding: .day, value: 3, to: date) {
            ensureMonth(for: nextMonth, coordinate: coordinate, calendar: cal)
        }
    }

    /// Проверяет кеш месяца (память → диск) и при необходимости качает с API.
    private func ensureMonth(for date: Date, coordinate: CLLocationCoordinate2D, calendar: Calendar) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return }

        let lat = Self.round2(coordinate.latitude)
        let lon = Self.round2(coordinate.longitude)
        let name = PrayerCache.fileName(latitude: lat, longitude: lon,
                                        method: Self.method, school: Self.school,
                                        year: year, month: month)

        if months[name] == nil { months[name] = PrayerCache.load(fileName: name) }

        // Свежий кеш (< суток) — ничего не делаем; смена локации/метода даёт
        // другое имя файла, так что инвалидация происходит сама собой.
        if let cached = months[name], Date().timeIntervalSince(cached.fetchedAt) < 86_400 { return }
        guard !inFlight.contains(name) else { return }
        // После неудачи не ретраим чаще раза в 15 минут (оффлайн — живём на кеше).
        if let last = lastAttempt[name], Date().timeIntervalSince(last) < 900 { return }

        inFlight.insert(name)
        lastAttempt[name] = Date()
        let timezone = TimeZone.current.identifier

        Task { @MainActor [weak self] in
            defer { self?.inFlight.remove(name) }
            guard let days = try? await AladhanAPI.fetchCalendar(
                latitude: lat, longitude: lon, year: year, month: month,
                timezone: timezone, method: Self.method, school: Self.school
            ), !days.isEmpty else { return }   // ошибки сети — тихо в фолбэк

            let cached = CachedMonth(latitude: lat, longitude: lon,
                                     method: Self.method, school: Self.school,
                                     year: year, month: month, timezone: timezone,
                                     fetchedAt: Date(), days: days)
            self?.months[name] = cached
            PrayerCache.save(cached, fileName: name)
            self?.onUpdate?()
        }
    }

    private func cachedMonth(for date: Date, coordinate: CLLocationCoordinate2D) -> CachedMonth? {
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return nil }
        let name = PrayerCache.fileName(latitude: Self.round2(coordinate.latitude),
                                        longitude: Self.round2(coordinate.longitude),
                                        method: Self.method, school: Self.school,
                                        year: year, month: month)
        if months[name] == nil { months[name] = PrayerCache.load(fileName: name) }
        return months[name]
    }

    // MARK: - Конвертация "HH:mm" → Date

    /// Шесть времён дня как Date в timezone календаря.
    ///
    /// Переход через полночь: на высоких широтах Isha может «выпасть за полночь»
    /// (Москва: Maghrib "21:12", Isha "00:35"). Правило: времена в порядке
    /// Fajr → … → Isha не убывают; если очередное меньше предыдущего —
    /// значит, оно уже на следующем календарном дне.
    static func dates(for day: CalendarDay, timezone: String) -> [Date]? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezone) ?? .current

        let parts = day.date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        var result: [Date] = []
        var previous: Date?
        for hhmm in [day.fajr, day.sunrise, day.dhuhr, day.asr, day.maghrib, day.isha] {
            let t = hhmm.split(separator: ":").compactMap { Int($0) }
            guard t.count == 2 else { return nil }
            guard var d = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2],
                                                        hour: t[0], minute: t[1])) else { return nil }
            if let p = previous, d < p {
                d = cal.date(byAdding: .day, value: 1, to: d) ?? d
            }
            previous = d
            result.append(d)
        }
        return result
    }

    /// Дата как ключ строки календаря ("2026-07-08") в timezone кеша.
    static func dayKey(_ date: Date, timezone: String) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezone) ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
