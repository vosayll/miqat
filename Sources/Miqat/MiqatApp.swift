import SwiftUI
import AppKit

/// Приложение живёт в чёлке + иконка в строке меню (без окна и иконки в доке).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let clock = ClockModel()
    private let location = LocationProvider()
    private let notifications = NotificationScheduler()
    private var controller: NotchController?
    private var settingsDebounce: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)      // без иконки в доке

        let controller = NotchController(clock: clock)
        controller.show()
        self.controller = controller

        // Геолокация → запоминаем GPS-фикс и пересчитываем времена намаза.
        // Пишем именно gps*: при ручной локации из настроек GPS её не перетирает —
        // PrayerEngine сам выбирает эффективные координаты.
        location.onUpdate = { [weak self] in
            guard let self = self else { return }
            if let coord = self.location.coordinate { PrayerEngine.gpsCoordinate = coord }
            if let city  = self.location.cityName    { PrayerEngine.gpsCityName = city }
            // Страна/регион — для авто-выбора метода расчёта по региону.
            if let cc = self.location.isoCountryCode     { PrayerEngine.gpsCountryCode = cc }
            if let aa = self.location.administrativeArea  { PrayerEngine.gpsAdminArea = aa }
            self.clock.refresh()
        }
        location.start()

        // Ручная локация: геокодим её координаты, чтобы «Авто (по региону)»
        // работал и без GPS. Гоняется при старте и при смене настроек локации.
        geocodeManualLocationIfNeeded()

        // Календарь с API скачался → пересчитать расписание (источник мог
        // смениться с локального расчёта на API-кеш).
        PrayerStore.shared.onUpdate = { [weak self] in self?.clock.refresh() }

        // Окно настроек пишет UserDefaults → живой пересчёт без перезапуска.
        // Дебаунс 0.3 с, чтобы степперы не молотили пересчёт на каждый тик.
        // refresh() сам тянет за собой всё: чипы читают источник/локацию/поправки,
        // PrayerStore при смене метода/локации видит новый ключ кеша и качает
        // календарь, onRefresh перепланирует уведомления.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.settingsDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.geocodeManualLocationIfNeeded()   // ручные координаты могли смениться
                self.clock.refresh()
            }
            self.settingsDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }

        // Локальные напоминания о намазе (на устройстве, оффлайн, бесплатно).
        clock.onRefresh = { [weak self] in self?.notifications.reschedule() }
        notifications.requestAuthorization()
    }

    // Последние заданные вручную координаты, для которых уже сделан геокод —
    // чтобы не гонять геокодер на каждый тик настроек.
    private var lastManualGeocode: (lat: Double, lon: Double)?

    /// Если включена ручная локация — геокодим её координаты в страну/регион,
    /// чтобы «Авто (по региону)» выбрал верный метод и без GPS. При авто-локации
    /// сбрасываем сохранённое, чтобы возврат к ручной снова триггерил геокод.
    private func geocodeManualLocationIfNeeded() {
        let d = UserDefaults.standard
        guard d.object(forKey: "autoLocation") as? Bool == false else {
            lastManualGeocode = nil
            return
        }
        let lat = d.double(forKey: "manualLat")
        let lon = d.double(forKey: "manualLon")
        guard abs(lat) <= 90, abs(lon) <= 180, lat != 0 || lon != 0 else { return }
        if let last = lastManualGeocode, last.lat == lat, last.lon == lon { return }
        lastManualGeocode = (lat, lon)

        location.geocode(latitude: lat, longitude: lon) { [weak self] country, area, _ in
            PrayerEngine.manualCountryCode = country
            PrayerEngine.manualAdminArea = area
            self?.clock.refresh()
        }
    }
}

@main
struct MiqatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Miqat", systemImage: "moon.stars.fill") {
            Button("Выйти из Miqat") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
