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

    static func remaining(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval)); let h = s / 3600; let m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m remaining" : "\(m)m remaining"
    }

    static func hijri(_ date: Date) -> String {
        let cal = Calendar(identifier: .islamicUmmAlQura)
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "en")
        f.timeZone = .current
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
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
