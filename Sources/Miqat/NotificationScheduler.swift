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

    /// Текст: за 0 минут — «Время намаза», иначе — «Через N мин».
    static func body(time: Date, lead: Int) -> String {
        lead == 0 ? "Время намаза · \(Format.clock(time))"
                  : "Через \(lead) мин · \(Format.clock(time))"
    }

    private func scheduleNow() {
        center.removeAllPendingNotificationRequests()
        guard Self.enabled else { return }   // выключено в настройках — только чистим
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
