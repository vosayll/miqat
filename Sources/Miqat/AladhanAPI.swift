import Foundation

// MARK: - Модели ответов api.aladhan.com
//
// Aladhan оборачивает полезную нагрузку один раз: {"code":200,"status":"OK","data": …}.
// Времена приходят строками "HH:mm" — но у /calendar к ним прицеплен суффикс с
// аббревиатурой таймзоны: "02:31 (MSK)". Его срезаем в AladhanTime (см. ниже);
// у /timings суффикса нет. Ключи времён — С Заглавной ("Fajr", "Isha").

/// Время из ответа Aladhan: строка "HH:mm", возможно с суффиксом " (TZ)".
/// Обёртка над String, которая срезает суффикс при декодировании — дальше по
/// коду времена везде чистые "HH:mm".
struct AladhanTime: Decodable {
    let value: String   // всегда чистое "HH:mm"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        value = AladhanTime.strip(raw)
    }

    /// "02:31 (MSK)" → "02:31"; "02:31" → "02:31". Берём часть до первого пробела.
    static func strip(_ raw: String) -> String {
        raw.split(separator: " ", maxSplits: 1).first.map(String.init)
            ?? raw.trimmingCharacters(in: .whitespaces)
    }
}

/// Блок timings из ответа Aladhan (лишние поля — Imsak, Sunset, Midnight… — игнорируем).
struct AladhanTimings: Decodable {
    let fajr, sunrise, dhuhr, asr, maghrib, isha: AladhanTime

    enum CodingKeys: String, CodingKey {
        case fajr = "Fajr", sunrise = "Sunrise", dhuhr = "Dhuhr"
        case asr = "Asr", maghrib = "Maghrib", isha = "Isha"
    }
}

/// Дата по Хиджре из ответа Aladhan (нужны только цифры для отображения).
struct AladhanHijri: Decodable {
    let date: String    // "24-01-1448" (DD-MM-YYYY)
    let day: String     // "24"
    let month: Month
    let year: String    // "1448"
    struct Month: Decodable { let number: Int; let en: String }
}

/// Григорианская дата дня календаря — нужна, чтобы собрать ключ "YYYY-MM-DD".
struct AladhanGregorian: Decodable {
    let date: String    // "01-07-2026" (DD-MM-YYYY)
}

/// Дата дня из ответа (и Хиджра, и Григориан).
struct AladhanDate: Decodable {
    let gregorian: AladhanGregorian
    let hijri: AladhanHijri
}

/// Один день ответа /calendar (или полезная нагрузка /timings).
struct AladhanDay: Decodable {
    let timings: AladhanTimings
    let date: AladhanDate
}

/// Обёртка ответа Aladhan: code/status + data (день или массив дней).
struct AladhanEnvelope<Payload: Decodable>: Decodable {
    let code: Int?
    let status: String?
    let data: Payload
}

// MARK: - Клиент

enum AladhanError: Error {
    case badURL
    case rateLimited            // 429 — исчерпали ретраи
    case badStatus(Int)
}

/// HTTP-клиент публичного Aladhan API (без ключа, ~12 запросов/сек).
/// Основной метод — /calendar (месяц одним запросом для кеша); /timings — фолбэк на день.
/// При 429/5xx ретраим с экспоненциальной паузой 1с → 4с → 16с; прочие ошибки пробрасываем.
enum AladhanAPI {

    static let baseURL = URL(string: "https://api.aladhan.com/v1")!

    /// Весь месяц одним запросом — основной метод для кеша.
    /// timezone (IANA) передаём всегда: иначе времена уедут в UTC.
    /// tune (опц.) — строка смещений "imsak,fajr,…" в минутах.
    static func fetchCalendar(latitude: Double, longitude: Double,
                              year: Int, month: Int,
                              timezone: String, method: Int, school: Int,
                              tune: String? = nil) async throws -> [CalendarDay] {
        var query = [
            "latitude": String(latitude), "longitude": String(longitude),
            "method": String(method), "school": String(school),
            "timezonestring": timezone,
        ]
        if let tune { query["tune"] = tune }
        let url = try makeURL(path: "calendar/\(year)/\(month)", query: query)
        let data = try await getWithRetry(url)
        let days = try JSONDecoder().decode(AladhanEnvelope<[AladhanDay]>.self, from: data).data
        return days.map(Self.calendarDay)
    }

    /// Один день (запасной метод; основной источник — /calendar).
    static func fetchTimings(latitude: Double, longitude: Double, date: Date,
                             timezone: String, method: Int, school: Int,
                             tune: String? = nil) async throws -> CalendarDay {
        var query = [
            "latitude": String(latitude), "longitude": String(longitude),
            "method": String(method), "school": String(school),
            "timezonestring": timezone,
        ]
        if let tune { query["tune"] = tune }
        let url = try makeURL(path: "timings/\(Self.ddmmyyyy(date, timezone: timezone))", query: query)
        let data = try await getWithRetry(url)
        let day = try JSONDecoder().decode(AladhanEnvelope<AladhanDay>.self, from: data).data
        return Self.calendarDay(day)
    }

    // MARK: маппинг Aladhan → внутренняя CalendarDay

    /// AladhanDay → CalendarDay: дату "DD-MM-YYYY" переворачиваем в "YYYY-MM-DD"
    /// (в этом виде её ждёт PrayerStore), времена уже чистые "HH:mm".
    static func calendarDay(_ day: AladhanDay) -> CalendarDay {
        let t = day.timings
        return CalendarDay(date: Self.isoDate(day.date.gregorian.date),
                           fajr: t.fajr.value, sunrise: t.sunrise.value,
                           dhuhr: t.dhuhr.value, asr: t.asr.value,
                           maghrib: t.maghrib.value, isha: t.isha.value,
                           hijri: day.date.hijri.date)
    }

    /// "01-07-2026" → "2026-07-01". При неожиданном формате возвращаем как есть.
    static func isoDate(_ ddmmyyyy: String) -> String {
        let p = ddmmyyyy.split(separator: "-")
        guard p.count == 3 else { return ddmmyyyy }
        return "\(p[2])-\(p[1])-\(p[0])"
    }

    // MARK: детали

    /// Дата → "DD-MM-YYYY" в нужной таймзоне — путь эндпоинта /timings.
    private static func ddmmyyyy(_ date: Date, timezone: String) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezone) ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d-%02d-%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    private static func makeURL(path: String, query: [String: String]) throws -> URL {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                        resolvingAgainstBaseURL: false) else { throw AladhanError.badURL }
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted { $0.name < $1.name }
        guard let url = comps.url else { throw AladhanError.badURL }
        return url
    }

    /// GET с ретраем по 429 и 5xx: паузы 1с → 4с → 16с, дальше сдаёмся.
    /// Другие ошибки сети пробрасываются сразу — наверху тихий фолбэк на локальный расчёт.
    private static func getWithRetry(_ url: URL) async throws -> Data {
        let delays: [UInt64] = [1, 4, 16]
        for delay in delays {
            do { return try await get(url) }
            catch AladhanError.rateLimited {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
        return try await get(url)
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AladhanError.badStatus(-1) }
        switch http.statusCode {
        case 200: return data
        case 429, 500...599: throw AladhanError.rateLimited   // ретраим
        default: throw AladhanError.badStatus(http.statusCode)
        }
    }
}
