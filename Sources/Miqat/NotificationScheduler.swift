import Foundation
import UserNotifications

/// Локальные напоминания о намазе — на устройстве, оффлайн, бесплатно.
/// Это НЕ push с сервера: времена считаем сами и планируем уведомления локально.
final class NotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    /// Индексы намазов в расписании (без Восхода=1): Fajr, Dhuhr, Asr, Maghrib, Isha.
    private let prayerIdx = [0, 2, 3, 4, 5]

    /// Спросить разрешение (системный запрос один раз) и запланировать.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                self?.confirmEnabled()
                self?.scheduleNow()
            }
        }
    }

    /// Перепланировать (вызывать при смене намаза/локации). Требует уже выданного разрешения.
    func reschedule() {
        center.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .authorized else { return }
            DispatchQueue.main.async { self?.scheduleNow() }
        }
    }

    /// Включены ли напоминания (настройка "notifyEnabled", дефолт true).
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "notifyEnabled") as? Bool ?? true
    }

    /// За сколько минут напоминать (настройка "notifyLeadMinutes", 0–60, дефолт 0).
    static var leadMinutes: Int {
        min(60, max(0, UserDefaults.standard.object(forKey: "notifyLeadMinutes") as? Int ?? 0))
    }

    // Ежедневный салават Пророку ﷺ (настройки "salawat*").
    static var salawatEnabled: Bool {
        UserDefaults.standard.object(forKey: "salawatEnabled") as? Bool ?? true
    }
    static var salawatHour: Int {
        min(23, max(0, UserDefaults.standard.object(forKey: "salawatHour") as? Int ?? 13))
    }
    static var salawatMinute: Int {
        min(59, max(0, UserDefaults.standard.object(forKey: "salawatMinute") as? Int ?? 0))
    }
    static var salawatKahf: Bool {
        UserDefaults.standard.object(forKey: "salawatKahf") as? Bool ?? true
    }

    /// Текст: за 0 минут — «Время намаза», иначе — «Через N мин».
    static func body(time: Date, lead: Int) -> String {
        lead == 0 ? "Время намаза · \(Format.clock(time))"
                  : "Через \(lead) мин · \(Format.clock(time))"
    }

    private func scheduleNow() {
        center.removeAllPendingNotificationRequests()
        if Self.enabled { schedulePrayers() }   // намаз-напоминания — если включены
        scheduleSalawat()                        // салават — независимо от них
    }

    private func schedulePrayers() {
        let lead = Self.leadMinutes
        let now = Date()
        let cal = Calendar(identifier: .gregorian)

        for dayOffset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let chips = PrayerEngine.chips(on: day)
            for i in prayerIdx where i < chips.count {
                let chip = chips[i]
                let fireDate = chip.time.addingTimeInterval(TimeInterval(-lead * 60))
                guard fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "🕌 \(chip.name)"
                content.body = Self.body(time: chip.time, lead: lead)
                content.sound = .default

                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: "prayer-\(dayOffset)-\(i)",
                                                 content: content, trigger: trigger))
            }
        }
    }

    /// Салават — КАЖДЫЙ день; в пятницу ДОПОЛНИТЕЛЬНО напоминание про суру
    /// «Аль-Кахф». Повторяющиеся триггеры — срабатывают и когда приложение закрыто.
    private func scheduleSalawat() {
        let h = Self.salawatHour, m = Self.salawatMinute
        if Self.salawatEnabled {
            for wd in 1...7 {
                addWeekly(id: "salawat-\(wd)", weekday: wd, hour: h, minute: m,
                          title: "Салават Пророку Мухаммаду ﷺ",
                          body: "Аллахумма салли аля Мухаммадин ва аля али Мухаммад")
            }
        }
        if Self.salawatKahf {
            addWeekly(id: "kahf-fri", weekday: 6, hour: h, minute: m,
                      title: "Пятница — сура «Аль-Кахф»",
                      body: "Прочтите суру «Аль-Кахф» — свет до следующей пятницы")
        }
    }

    /// weekday: 1=Вс … 6=Пт … 7=Сб (Gregorian). Повторяющийся недельный триггер.
    private func addWeekly(id: String, weekday: Int, hour: Int, minute: Int, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        center.add(UNNotificationRequest(identifier: id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }

    /// Разовое подтверждение сразу после включения.
    private func confirmEnabled() {
        let content = UNMutableNotificationContent()
        content.title = "Miqat"
        content.body = "Напоминания о намазе включены ✓"
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "confirm", content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
    }
}
