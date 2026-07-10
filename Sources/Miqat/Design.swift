import SwiftUI
import Foundation

/// Палитра из макета Prayer Island.
enum Design {
    static let gold  = Color(hex: 0xC9A24B)   // акцент
    static let cream = Color(hex: 0xF4F2EC)   // тёплый белый (текст)
    static let bg    = Color(hex: 0x0B0B0F)   // фон панели
}

/// Форматирование времён и отсчёта.
enum Format {
    static let time24: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = .current; return f
    }()

    static func clock(_ d: Date) -> String { time24.string(from: d) }

    /// Крупный отсчёт: «4:32» (ч:мм) если > часа, иначе «32:05» (мм:сс).
    static func big(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval)); let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "%02d:%02d", m, sec)
    }

    /// Отсчёт с секундами: «3:08:59» (ч:мм:сс) или «08:59» (мм:сс).
    static func hms(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval)); let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    static func remaining(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval)); let h = s / 3600; let m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m remaining" : "\(m)m remaining"
    }

    /// Дата по Хиджре на языке интерфейса (ru/en): в русском — «10 Мухаррам 1448».
    /// Русская локаль даёт строчный месяц — поднимаем первую букву (только её,
    /// чтобы «раби аль-авваль» не стало «Раби Аль-Авваль»). День/год форматируем
    /// отдельно, чтобы регистр не задел цифры.
    static func hijri(_ date: Date, ru: Bool) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .islamicUmmAlQura)
        f.locale = Locale(identifier: ru ? "ru" : "en")
        f.timeZone = .current

        f.dateFormat = "MMMM"
        let raw = f.string(from: date)
        let month = raw.prefix(1).uppercased() + raw.dropFirst()

        f.dateFormat = "d"; let day = f.string(from: date)
        f.dateFormat = "yyyy"; let year = f.string(from: date)
        return "\(day) \(month) \(year)"
    }
}

extension Color {
    /// Цвет из HEX-числа, напр. Color(hex: 0xC9A24B).
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
