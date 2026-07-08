import SwiftUI
import AppKit

/// Приложение живёт в чёлке + иконка в строке меню (без окна и иконки в доке).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let clock = ClockModel()
    private let location = LocationProvider()
    private let notifications = NotificationScheduler()
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)      // без иконки в доке

        let controller = NotchController(clock: clock)
        controller.show()
        self.controller = controller

        // Геолокация → обновляем координаты/город и пересчитываем времена намаза.
        location.onUpdate = { [weak self] in
            guard let self = self else { return }
            if let coord = self.location.coordinate { PrayerEngine.coordinate = coord }
            if let city  = self.location.cityName    { PrayerEngine.cityName = city }
            self.clock.refresh()
        }
        location.start()

        // Календарь с API скачался → пересчитать расписание (источник мог
        // смениться с локального расчёта на API-кеш).
        PrayerStore.shared.onUpdate = { [weak self] in self?.clock.refresh() }

        // Локальные напоминания о намазе (на устройстве, оффлайн, бесплатно).
        clock.onRefresh = { [weak self] in self?.notifications.reschedule() }
        notifications.requestAuthorization()
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
