import SwiftUI

/// Форма настроек — стандартный macOS-стиль (Form + секции).
/// Все значения пишутся в UserDefaults сразу (@AppStorage), без кнопки
/// «Сохранить». Ключи читают PrayerEngine/NotificationScheduler (подключение —
/// в соседней ветке); тема — существующий ThemeStore, отдельно не храним.
struct SettingsView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var language: LanguageStore

    // Источник времён: auto | api | local (читает движок расчёта).
    @AppStorage("prayerSource") private var prayerSource = "auto"

    // Метод по региону автоматически (дефолт) — метод/мазхаб берутся из карты
    // регион→метод. Если выключить — используются явные calcMethod/asrSchool.
    @AppStorage("methodAuto") private var methodAuto = true

    // Метод расчёта (коды Aladhan) и мазхаб для Асра (0 — Шафии, 1 — Ханафи).
    // Дефолты совпадают с PrayerMethod.fallback — иначе пикер показывал бы
    // не тот метод, который реально использует движок при незаполненном ключе.
    @AppStorage("calcMethod") private var calcMethod = PrayerMethod.fallback.method
    @AppStorage("asrSchool")  private var asrSchool = PrayerMethod.fallback.school

    // Местоположение: авто (CoreLocation) или вручную (выбор города из каталога).
    @AppStorage("autoLocation")   private var autoLocation = true
    @AppStorage("manualLat")      private var manualLat = 0.0
    @AppStorage("manualLon")      private var manualLon = 0.0
    @AppStorage("manualCity")     private var manualCity = ""
    // geonameId выбранного города — по нему в будущем берётся файл расписания Sajda.
    @AppStorage("manualGeonameId") private var manualGeonameId = 0

    // Поиск города по каталогу (рус/англ), результаты по населению.
    @State private var citySearch = ""
    private var cityResults: [City] {
        citySearch.count >= 2 ? CityCatalog.shared.search(citySearch, limit: 8) : []
    }

    // Уведомления. 0 минут = ровно во время намаза (текущее поведение
    // NotificationScheduler).
    @AppStorage("notifyEnabled")     private var notifyEnabled = true
    @AppStorage("notifyLeadMinutes") private var notifyLeadMinutes = 0

    // Ежедневный салават Пророку ﷺ.
    @AppStorage("salawatEnabled") private var salawatEnabled = true
    @AppStorage("salawatHour")    private var salawatHour = 13
    @AppStorage("salawatMinute")  private var salawatMinute = 0
    @AppStorage("salawatKahf")    private var salawatKahf = true

    // Поправки времён — словарь, @AppStorage его не умеет: своя обёртка.
    @StateObject private var offsets = PrayerOffsets()

    /// Методы расчёта: код Aladhan (/v1/methods) → название (рус/англ).
    private struct Method: Identifiable { let id: Int; let ru: String; let en: String }
    private static let methods: [Method] = [
        .init(id: 14, ru: "ДУМ России",                    en: "Muftiate of Russia"),
        .init(id: 3,  ru: "MWL — Всемирная исламская лига", en: "MWL — Muslim World League"),
        .init(id: 4,  ru: "Умм аль-Кура — Мекка",          en: "Umm al-Qura — Makkah"),
        .init(id: 5,  ru: "Египетское управление",          en: "Egyptian Authority"),
        .init(id: 13, ru: "Турция (Diyanet)",               en: "Turkey (Diyanet)"),
        .init(id: 2,  ru: "ISNA — Северная Америка",        en: "ISNA — North America"),
        .init(id: 1,  ru: "Университет Карачи",             en: "University of Karachi"),
        .init(id: 7,  ru: "Тегеран",                        en: "Tehran"),
        .init(id: 16, ru: "Дубай",                          en: "Dubai"),
        .init(id: 8,  ru: "Персидский залив",               en: "Gulf Region"),
        .init(id: 9,  ru: "Кувейт",                         en: "Kuwait"),
        .init(id: 10, ru: "Катар",                          en: "Qatar"),
        .init(id: 11, ru: "Сингапур",                       en: "Singapore"),
        .init(id: 15, ru: "Moonsighting Committee",         en: "Moonsighting Committee"),
    ]

    var body: some View {
        Form {
            Section(language.t("Язык", "Language")) {
                Picker(language.t("Язык интерфейса", "Interface language"), selection: $language.lang) {
                    Text("Русский").tag(AppLang.ru)
                    Text("English").tag(AppLang.en)
                }
                .pickerStyle(.segmented)
            }

            Section(language.t("Источник времён", "Time source")) {
                Picker(language.t("Источник", "Source"), selection: $prayerSource) {
                    Text(language.t("Авто", "Auto")).tag("auto")
                    Text("API").tag("api")
                    Text(language.t("Локальный расчёт", "On-device")).tag("local")
                }
            }

            Section(language.t("Метод расчёта", "Calculation method")) {
                Toggle(language.t("Авто (по региону)", "Auto (by region)"), isOn: $methodAuto)
                Picker(language.t("Метод", "Method"), selection: $calcMethod) {
                    ForEach(Self.methods) { Text(language.isRU ? $0.ru : $0.en).tag($0.id) }
                }
                .disabled(methodAuto)
                Picker(language.t("Мазхаб (Аср)", "Madhab (Asr)"), selection: $asrSchool) {
                    Text(language.t("Шафиитский", "Shafi")).tag(0)
                    Text(language.t("Ханафитский", "Hanafi")).tag(1)
                }
                .disabled(methodAuto)
            }

            Section(language.t("Местоположение", "Location")) {
                Toggle(language.t("Определять автоматически", "Detect automatically"), isOn: $autoLocation)
                if !autoLocation {
                    if !manualCity.isEmpty {
                        HStack(spacing: 8) {
                            Text("\(language.t("Сейчас", "Current")): \(manualCity)").fontWeight(.medium)
                            Spacer()
                            Button(action: clearCity) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(language.t("Сбросить город", "Clear city"))
                        }
                    }
                    TextField(language.t("Поиск города", "Search city"), text: $citySearch,
                              prompt: Text(language.t("Начните вводить: Грозный, Москва…",
                                                      "Start typing: Grozny, Moscow…")))
                    if citySearch.count >= 2 {
                        if cityResults.isEmpty {
                            Text(language.t("Ничего не найдено", "Nothing found"))
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            ForEach(cityResults) { city in
                                Button { select(city) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "mappin.circle.fill")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(city.displayName)
                                            Text(subtitle(city))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: city.id == manualGeonameId
                                              ? "checkmark.circle.fill" : "plus.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Text(language.t("Выберите город из списка — по нему считаются времена намаза",
                                        "Pick a city from the list — prayer times use it"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section(language.t("Поправки времён (минуты)", "Time offsets (minutes)")) {
                ForEach(PrayerOffsets.prayers) { p in
                    Stepper(value: offsets.binding(p.id), in: -59...59) {
                        LabeledContent(language.prayer(p.id), value: Self.signed(offsets.values[p.id] ?? 0))
                    }
                }
                Button(language.t("Сбросить поправки", "Reset offsets")) { offsets.reset() }
            }

            Section(language.t("Уведомления", "Notifications")) {
                Toggle(language.t("Напоминать о намазе", "Prayer reminders"), isOn: $notifyEnabled)
                Stepper(value: $notifyLeadMinutes, in: 0...60) {
                    LabeledContent(language.t("Заранее, минут", "Lead, minutes"),
                                   value: notifyLeadMinutes == 0 ? language.t("во время намаза", "at prayer time")
                                                                 : "\(notifyLeadMinutes) \(language.t("мин", "min"))")
                }
                .disabled(!notifyEnabled)
            }

            Section(language.t("Салават", "Salawat")) {
                Toggle(language.t("Ежедневный салават Пророку ﷺ", "Daily salawat ﷺ"), isOn: $salawatEnabled)
                Toggle(language.t("Пятница: сура «Аль-Кахф»", "Friday: Surah Al-Kahf"), isOn: $salawatKahf)
                DatePicker(language.t("Время", "Time"), selection: salawatTimeBinding, displayedComponents: .hourAndMinute)
                    .disabled(!salawatEnabled && !salawatKahf)
            }

            Section(language.t("Оформление", "Appearance")) {
                Picker(language.t("Тема", "Theme"), selection: $themeStore.isDark) {
                    Text(language.t("Зелёная", "Green")).tag(false)
                    Text(language.t("Тёмная", "Dark")).tag(true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
    }

    /// Выбор города из каталога → в ручную локацию (её читает PrayerEngine).
    private func select(_ c: City) {
        manualLat = c.latitude
        manualLon = c.longitude
        manualCity = c.displayName
        manualGeonameId = c.id
        citySearch = ""
    }

    /// Сброс выбранного города — крестик у строки «Сейчас: …».
    /// Локация уходит на фоллбэк (Грозный), пока не выберут заново.
    private func clearCity() {
        manualCity = ""
        manualLat = 0
        manualLon = 0
        manualGeonameId = 0
        citySearch = ""
    }

    /// Подпись под названием: страна и население (для различения тёзок).
    /// Подпись под названием: страна и население (для различения тёзок).
    private func subtitle(_ c: City) -> String {
        var parts = [c.country]
        if c.population > 0 { parts.append(population(c.population)) }
        return parts.joined(separator: " · ")
    }

    private func population(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1f \(language.t("млн", "M"))", Double(n) / 1_000_000)
                       : n >= 1_000 ? "\(n / 1_000) \(language.t("тыс.", "K"))" : "\(n)"
    }

    /// Время салавата как Date для DatePicker (храним час/минуту отдельно).
    private var salawatTimeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: salawatHour, minute: salawatMinute, second: 0, of: Date()) ?? Date() },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                salawatHour = c.hour ?? 13
                salawatMinute = c.minute ?? 0
            }
        )
    }

    /// «+5» / «−3» / «0» — чтобы поправка читалась с одного взгляда.
    private static func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : "\(v)" }
}

/// Поправки времён в минутах — словарь [имя намаза: минуты] в UserDefaults.
/// Всегда хранит все шесть ключей (читателю не нужно домысливать отсутствующие).
final class PrayerOffsets: ObservableObject {
    struct Prayer: Identifiable { let id: String; let title: String }
    static let prayers: [Prayer] = [
        .init(id: "Fajr",    title: "Фаджр"),
        .init(id: "Sunrise", title: "Восход"),
        .init(id: "Dhuhr",   title: "Зухр"),
        .init(id: "Asr",     title: "Аср"),
        .init(id: "Maghrib", title: "Магриб"),
        .init(id: "Isha",    title: "Иша"),
    ]
    private static let key = "prayerOffsets"

    @Published var values: [String: Int] {
        didSet { UserDefaults.standard.set(values, forKey: Self.key) }
    }

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
        values = Self.prayers.reduce(into: [:]) { $0[$1.id] = stored[$1.id] ?? 0 }
    }

    func binding(_ id: String) -> Binding<Int> {
        Binding(get: { self.values[id] ?? 0 }, set: { self.values[id] = $0 })
    }

    func reset() {
        values = Self.prayers.reduce(into: [:]) { $0[$1.id] = 0 }
    }
}
