import Foundation
import CoreLocation

/// Город из каталога GeoNames — всё, что нужно для показа, поиска и (в будущем)
/// адреса готового файла Sajda: geonameId, координаты, часовой пояс.
struct City: Identifiable, Equatable {
    let id: Int              // geonameId — им же адресуется файл расписания Sajda
    let name: String         // английское название
    let asciiName: String
    let ru: String           // русское название (может быть пустым)
    let latitude: Double
    let longitude: Double
    let country: String      // ISO-код страны: RU, TR…
    let admin1: String       // код региона GeoNames
    let timezone: String     // IANA-пояс: Europe/Moscow
    let population: Int

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    /// Что показать пользователю: русское имя, если есть, иначе английское.
    var displayName: String { ru.isEmpty ? name : ru }
}

/// Встроенный каталог городов мира (срез GeoNames cities5000, ~69 тыс.).
/// Читается в память один раз; даёт поиск по названию и ближайший к координате.
/// Работает офлайн, интернет не нужен.
final class CityCatalog {
    static let shared = CityCatalog()

    private var cities: [City] = []
    private var keys: [String] = []       // предпосчитанный ключ поиска (name+ascii+ru), lower
    private var loaded = false
    private let lock = NSLock()

    /// Ленивая загрузка: парсим TSV из бандла при первом обращении.
    private func ensureLoaded() {
        lock.lock(); defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        guard let url = Bundle.module.url(forResource: "cities", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        var cs: [City] = []; cs.reserveCapacity(70_000)
        var ks: [String] = []; ks.reserveCapacity(70_000)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count >= 10,
                  let id = Int(f[0]), let lat = Double(f[4]),
                  let lon = Double(f[5]), let pop = Int(f[9]) else { continue }
            cs.append(City(id: id, name: String(f[1]), asciiName: String(f[2]), ru: String(f[3]),
                           latitude: lat, longitude: lon, country: String(f[6]),
                           admin1: String(f[7]), timezone: String(f[8]), population: pop))
            ks.append("\(f[1])\t\(f[2])\t\(f[3])".lowercased())
        }
        cities = cs; keys = ks
    }

    var count: Int { ensureLoaded(); return cities.count }

    /// Ближайший город к координате. Равнопромежуточное приближение расстояния —
    /// для «ближайшего» точнее не нужно, зато без тригонометрии на каждый город.
    func nearest(to c: CLLocationCoordinate2D) -> City? {
        ensureLoaded()
        guard !cities.isEmpty else { return nil }
        let cosLat = cos(c.latitude * .pi / 180)
        var bestIdx = -1
        var bestD = Double.greatestFiniteMagnitude
        for (i, city) in cities.enumerated() {
            let dx = (city.longitude - c.longitude) * cosLat
            let dy = (city.latitude - c.latitude)
            let d = dx * dx + dy * dy
            if d < bestD { bestD = d; bestIdx = i }
        }
        return bestIdx >= 0 ? cities[bestIdx] : nil
    }

    /// Поиск по названию. Латиница ищется как есть; кириллица дополнительно
    /// транслитерируется в латиницу и сверяется с англ. написанием — так ввод
    /// «Грозный» находит Grozny без словаря русских имён. Меньше 2 символов —
    /// пусто (не сканируем весь мир зря).
    func search(_ query: String, limit: Int = 20) -> [City] {
        ensureLoaded()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        // Транслит запроса — только если в нём есть кириллица.
        let tr = q.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }
            ? Self.translit(q) : nil

        var hits: [(city: City, rank: Int)] = []
        for (i, key) in keys.enumerated() {
            if key.contains(q) {
                hits.append((cities[i], rank(cities[i], q)))
            } else if let tr = tr, Self.matchesTranslit(cities[i].asciiName.lowercased(), tr) {
                hits.append((cities[i], 1))
            }
        }
        return Array(hits.sorted {
            $0.rank != $1.rank ? $0.rank > $1.rank : $0.city.population > $1.city.population
        }.prefix(limit).map(\.city))
    }

    /// Насколько «в лоб» совпал запрос: начало русского/англ. названия — выше всего.
    private func rank(_ c: City, _ q: String) -> Int {
        if c.ru.lowercased().hasPrefix(q) || c.name.lowercased().hasPrefix(q) { return 2 }
        if c.asciiName.lowercased().hasPrefix(q) { return 1 }
        return 0
    }

    /// Транслит запроса ≈ англ. написание: одно начинается с другого. Хвосты
    /// вроде «ый»→«yy» против «y» так не мешают (grozny/groznyy — совпадение).
    private static func matchesTranslit(_ ascii: String, _ tr: String) -> Bool {
        ascii.hasPrefix(tr) || tr.hasPrefix(ascii) || ascii.contains(tr)
    }

    /// Простая русско-латинская транслитерация запроса (ГОСТ-подобная).
    private static let translitMap: [Character: String] = [
        "а":"a","б":"b","в":"v","г":"g","д":"d","е":"e","ё":"e","ж":"zh","з":"z",
        "и":"i","й":"y","к":"k","л":"l","м":"m","н":"n","о":"o","п":"p","р":"r",
        "с":"s","т":"t","у":"u","ф":"f","х":"kh","ц":"ts","ч":"ch","ш":"sh",
        "щ":"sch","ъ":"","ы":"y","ь":"","э":"e","ю":"yu","я":"ya",
    ]
    static func translit(_ s: String) -> String {
        s.lowercased().reduce(into: "") { $0 += translitMap[$1] ?? String($1) }
    }
}
