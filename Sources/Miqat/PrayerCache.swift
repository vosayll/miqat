import Foundation

/// Кешированный месячный календарь с API — то, что лежит на диске.
struct CachedMonth: Codable {
    let latitude: Double     // округлено до 2 знаков — GPS-дрожание не сбрасывает кеш
    let longitude: Double
    let method: Int
    let school: Int
    let year: Int
    let month: Int
    let timezone: String     // IANA, в ней приходят все "HH:mm"
    let fetchedAt: Date      // когда скачали — для суточного обновления
    let days: [CalendarDay]
}

/// Дисковый кеш календарей: Application Support/Miqat/, JSON-файл на каждую
/// комбинацию (локация × метод × школа × месяц). Оффлайн живём на этих файлах.
enum PrayerCache {

    /// ~/Library/Application Support/Miqat/
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Miqat", isDirectory: true)
    }

    /// Ключ кеша — имя файла: calendar_43.32_45.70_m3_s0_2026-07.json.
    /// Координаты округляем до 2 знаков (~1 км) здесь и в запросе к API.
    static func fileName(latitude: Double, longitude: Double,
                         method: Int, school: Int, year: Int, month: Int) -> String {
        String(format: "calendar_%.2f_%.2f_m%d_s%d_%04d-%02d.json",
               latitude, longitude, method, school, year, month)
    }

    static func load(fileName: String) -> CachedMonth? {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CachedMonth.self, from: data)
    }

    static func save(_ month: CachedMonth, fileName: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(month) else { return }
        try? data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    // ISO-даты в JSON — чтобы файл было легко читать глазами при отладке.
    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
