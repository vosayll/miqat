import Foundation

// MARK: - Модели ответов siylaha-qoran.ru
// Все ответы API обёрнуты дважды: {"data": {"code": 200, "status": "OK", "data": …}}.
// Внимание на регистры: /calculate отдаёт ключи времён С Заглавной ("Fajr"),
// /calendar — в нижнем регистре ("fajr") и без Midnight/Lastthird.

/// Один день из GET /prayer-times/calendar (ключи в нижнем регистре).
/// Codable — этой же структурой пишем дисковый кеш.
struct CalendarDay: Codable {
    let date: String        // "2026-07-01"
    let fajr: String        // "02:02" — всё в формате "HH:mm" в запрошенной timezone
    let sunrise: String
    let dhuhr: String
    let asr: String
    let maghrib: String
    let isha: String
}

/// Времена из GET /prayer-times/calculate (ключи С Заглавной).
struct CalculateTimings: Decodable {
    let fajr: String
    let sunrise: String
    let dhuhr: String
    let asr: String
    let maghrib: String
    let isha: String
    let midnight: String?
    let lastthird: String?

    enum CodingKeys: String, CodingKey {
        case fajr = "Fajr", sunrise = "Sunrise", dhuhr = "Dhuhr", asr = "Asr"
        case maghrib = "Maghrib", isha = "Isha", midnight = "Midnight", lastthird = "Lastthird"
    }
}

/// Полезная часть GET /prayer-times/calculate (лишние поля ответа игнорируем).
struct CalculateDay: Decodable {
    let timings: CalculateTimings
    let timezone: String?
    let qibla: Double?
    let method: Int?
}

/// Двойная обёртка ответов: data.code/status + data.data с полезной нагрузкой.
struct APIEnvelope<Payload: Decodable>: Decodable {
    let data: Inner
    struct Inner: Decodable {
        let code: Int?
        let status: String?
        let data: Payload
    }
}

// MARK: - Клиент

enum PrayerAPIError: Error {
    case badURL
    case rateLimited            // 429 — исчерпали ретраи
    case badStatus(Int)
}

/// HTTP-клиент публичного API времён намаза (проект Payde), без авторизации.
/// Лимиты по IP: /calculate и /plan — 60 запр/мин, /calendar — 30/мин,
/// поэтому при 429 ретраим с экспоненциальной паузой 1с → 4с → 16с.
enum PrayerAPI {

    static let baseURL = URL(string: "https://siylaha-qoran.ru/api")!

    /// Весь месяц одним запросом — основной метод для кеша.
    /// timezone (IANA) обязателен: без него API вернёт времена в UTC.
    static func fetchCalendar(latitude: Double, longitude: Double,
                              year: Int, month: Int,
                              timezone: String, method: Int, school: Int) async throws -> [CalendarDay] {
        let url = try makeURL(path: "prayer-times/calendar", query: [
            "latitude": String(latitude), "longitude": String(longitude),
            "year": String(year), "month": String(month),
            "timezone": timezone, "method": String(method), "school": String(school),
        ])
        let data = try await getWithRetry(url)
        return try JSONDecoder().decode(APIEnvelope<[CalendarDay]>.self, from: data).data.data
    }

    /// Один день (запасной метод; в приложении основной источник — /calendar).
    static func fetchCalculate(latitude: Double, longitude: Double, date: String,
                               timezone: String, method: Int, school: Int) async throws -> CalculateDay {
        let url = try makeURL(path: "prayer-times/calculate", query: [
            "latitude": String(latitude), "longitude": String(longitude), "date": date,
            "timezone": timezone, "method": String(method), "school": String(school),
        ])
        let data = try await getWithRetry(url)
        return try JSONDecoder().decode(APIEnvelope<CalculateDay>.self, from: data).data.data
    }

    // MARK: детали

    private static func makeURL(path: String, query: [String: String]) throws -> URL {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                        resolvingAgainstBaseURL: false) else { throw PrayerAPIError.badURL }
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted { $0.name < $1.name }
        guard let url = comps.url else { throw PrayerAPIError.badURL }
        return url
    }

    /// GET с ретраем только по 429: паузы 1с → 4с → 16с, дальше сдаёмся.
    /// Любая другая ошибка сети пробрасывается сразу — наверху тихий фолбэк на локальный расчёт.
    private static func getWithRetry(_ url: URL) async throws -> Data {
        let delays: [UInt64] = [1, 4, 16]
        for delay in delays {
            do { return try await get(url) }
            catch PrayerAPIError.rateLimited {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
        return try await get(url)
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PrayerAPIError.badStatus(-1) }
        switch http.statusCode {
        case 200: return data
        case 429: throw PrayerAPIError.rateLimited
        default: throw PrayerAPIError.badStatus(http.statusCode)
        }
    }
}
