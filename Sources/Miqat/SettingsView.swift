import SwiftUI

/// Форма настроек — стандартный macOS-стиль (Form + секции).
/// Все значения пишутся в UserDefaults сразу (@AppStorage), без кнопки
/// «Сохранить». Ключи читают PrayerEngine/NotificationScheduler (подключение —
/// в соседней ветке); тема — существующий ThemeStore, отдельно не храним.
struct SettingsView: View {
    @EnvironmentObject var themeStore: ThemeStore

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

    /// Методы расчёта: код Aladhan (/v1/methods) → название.
    private struct Method: Identifiable { let id: Int; let name: String }
    private static let methods: [Method] = [
        .init(id: 14, name: "ДУМ России"),
        .init(id: 3,  name: "MWL — Всемирная исламская лига"),
        .init(id: 4,  name: "Умм аль-Кура — Мекка"),
        .init(id: 5,  name: "Египетское управление"),
        .init(id: 13, name: "Турция (Diyanet)"),
        .init(id: 2,  name: "ISNA — Северная Америка"),
        .init(id: 1,  name: "Университет Карачи"),
        .init(id: 7,  name: "Тегеран"),
        .init(id: 16, name: "Дубай"),
        .init(id: 8,  name: "Персидский залив"),
        .init(id: 9,  name: "Кувейт"),
        .init(id: 10, name: "Катар"),
        .init(id: 11, name: "Сингапур"),
        .init(id: 15, name: "Moonsighting Committee"),
    ]

    var body: some View {
        Form {
            Section("Источник времён") {
                Picker("Источник", selection: $prayerSource) {
                    Text("Авто").tag("auto")
                    Text("API").tag("api")
                    Text("Локальный расчёт").tag("local")
                }
            }

            Section("Метод расчёта") {
                Toggle("Авто (по региону)", isOn: $methodAuto)
                Picker("Метод", selection: $calcMethod) {
                    ForEach(Self.methods) { Text($0.name).tag($0.id) }
                }
                .disabled(methodAuto)
                Picker("Мазхаб (Аср)", selection: $asrSchool) {
                    Text("Шафиитский").tag(0)
                    Text("Ханафитский").tag(1)
                }
                .disabled(methodAuto)
            }

            Section("Местоположение") {
                Toggle("Определять автоматически", isOn: $autoLocation)
                if !autoLocation {
                    if !manualCity.isEmpty {
                        LabeledContent("Выбран город", value: manualCity)
                    }
                    TextField("Поиск города", text: $citySearch,
                              prompt: Text("Например: Грозный или Grozny"))
                    ForEach(cityResults) { city in
                        Button { select(city) } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(city.displayName)
                                    Text(Self.subtitle(city))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if city.id == manualGeonameId {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Поправки времён (минуты)") {
                ForEach(PrayerOffsets.prayers) { p in
                    Stepper(value: offsets.binding(p.id), in: -59...59) {
                        LabeledContent(p.title, value: Self.signed(offsets.values[p.id] ?? 0))
                    }
                }
                Button("Сбросить поправки") { offsets.reset() }
            }

            Section("Уведомления") {
                Toggle("Напоминать о намазе", isOn: $notifyEnabled)
                Stepper(value: $notifyLeadMinutes, in: 0...60) {
                    LabeledContent("Заранее, минут",
                                   value: notifyLeadMinutes == 0 ? "во время намаза"
                                                                 : "\(notifyLeadMinutes) мин")
                }
                .disabled(!notifyEnabled)
            }

            Section("Салават") {
                Toggle("Ежедневный салават Пророку ﷺ", isOn: $salawatEnabled)
                Toggle("Пятница: сура «Аль-Кахф»", isOn: $salawatKahf)
                DatePicker("Время", selection: salawatTimeBinding, displayedComponents: .hourAndMinute)
                    .disabled(!salawatEnabled && !salawatKahf)
            }

            Section("Оформление") {
                Picker("Тема", selection: $themeStore.isDark) {
                    Text("Зелёная").tag(false)
                    Text("Тёмная").tag(true)
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

    /// Подпись под названием: страна и население (для различения тёзок).
    private static func subtitle(_ c: City) -> String {
        var parts = [c.country]
        if c.population > 0 { parts.append(population(c.population)) }
        return parts.joined(separator: " · ")
    }

    private static func population(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1f млн", Double(n) / 1_000_000)
                       : n >= 1_000 ? "\(n / 1_000) тыс." : "\(n)"
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
