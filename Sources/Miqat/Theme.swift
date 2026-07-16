import SwiftUI

/// Тема оформления РАЗВЁРНУТОЙ карточки. Свёрнутая пилюля не зависит от темы
/// (всегда чёрная с зелёным акцентом — см. ThemeStore.pillAccent).
struct Theme {
    let accent: Color
    let ink: Color
    let sub: Color
    let surface: Color        // сплошная заливка карточки (запасная, если нет градиента)
    let chipBg: Color
    let chipInk: Color
    let activeText: Color

    /// Градиент заливки карточки (если задан — используется вместо surface).
    var surfaceGradient: [Color]? = nil
    /// Фоновый водяной знак карточки (nil — без узора).
    var watermark: WatermarkSpec? = nil

    /// Заливка карточки: градиент, если он задан, иначе сплошной surface.
    var cardStyle: AnyShapeStyle {
        if let g = surfaceGradient {
            return AnyShapeStyle(LinearGradient(colors: g,
                                                startPoint: UnitPoint(x: 0.15, y: 0),
                                                endPoint: UnitPoint(x: 0.85, y: 1)))
        }
        return AnyShapeStyle(surface)
    }

    // MARK: - Стиль «Emerald» (по умолчанию) — со сменой светлая/тёмная

    /// Зелёная (по умолчанию) — белая карточка, тёмный текст.
    static let green = Theme(
        accent:     Color(hex: 0x0E9F6E),
        ink:        Color(hex: 0x0F1A15),
        sub:        Color(hex: 0x0F1A15).opacity(0.5),
        surface:    .white,
        chipBg:     Color(hex: 0xF0F4F2),
        chipInk:    Color(hex: 0x0F1A15).opacity(0.78),
        activeText: .white
    )

    /// Тёмная — чёрная карточка, светлый текст, мятный акцент.
    static let dark = Theme(
        accent:     Color(hex: 0x34D399),
        ink:        Color(hex: 0xF3F6F4),
        sub:        Color(hex: 0xF3F6F4).opacity(0.5),
        surface:    .black,
        chipBg:     Color.white.opacity(0.08),
        chipInk:    Color(hex: 0xF3F6F4).opacity(0.78),
        activeText: Color(hex: 0x04140D)
    )

    // MARK: - Новые стили (без переключения светлая/тёмная)

    /// 1d Olive Gold — тёплый оливковый градиент, золотой акцент (вечерний намаз).
    static let oliveGold = Theme(
        accent:     Color(hex: 0xC9A24B),
        ink:        Color(hex: 0xF4EFE1),
        sub:        Color(hex: 0xF4EFE1).opacity(0.5),
        surface:    Color(hex: 0x161409),
        chipBg:     Color.white.opacity(0.05),
        chipInk:    Color(hex: 0xF4EFE1).opacity(0.78),
        activeText: Color(hex: 0x1A1405),
        surfaceGradient: [Color(hex: 0x1E1C12), Color(hex: 0x161409), Color(hex: 0x100F08)],
        watermark: WatermarkSpec(kind: .crescent, size: 271, cx: 0.824, cy: 0.411,
                                 rotation: -8, opacity: 0.07)
    )

    /// 1e Glass girih — «стеклянный» глубокий зелёный градиент, светло-мятный
    /// акцент, узор girih водяным знаком.
    static let glassGirih = Theme(
        accent:     Color(hex: 0x8EF5CF),
        ink:        Color(hex: 0xF2FBF7),
        sub:        Color(hex: 0xF2FBF7).opacity(0.6),
        surface:    Color(hex: 0x0A4A37),
        chipBg:     Color.white.opacity(0.10),
        chipInk:    Color(hex: 0xF2FBF7).opacity(0.78),
        activeText: Color(hex: 0x05392A),
        surfaceGradient: [Color(hex: 0x0D5F45), Color(hex: 0x0A4A37), Color(hex: 0x073728)],
        watermark: WatermarkSpec(kind: .girih, size: 340, cx: 0.5, cy: 0.5,
                                 rotation: 0, opacity: 0.14)
    )

    /// 1f Crescent watermark — почти чёрная карточка, изумрудный акцент,
    /// водяной знак-полумесяц.
    static let crescent = Theme(
        accent:     Color(hex: 0x34D399),
        ink:        Color(hex: 0xF3F6F4),
        sub:        Color(hex: 0xF3F6F4).opacity(0.55),
        surface:    Color(hex: 0x0C100E),
        chipBg:     Color.white.opacity(0.06),
        chipInk:    Color(hex: 0xF3F6F4).opacity(0.78),
        activeText: Color(hex: 0x04140D),
        watermark: WatermarkSpec(kind: .crescent, size: 240, cx: 0.810, cy: 0.644,
                                 rotation: 0, opacity: 0.09)
    )
}

/// Параметры фонового узора карточки (сняты из макета концептов).
/// Координаты центра — доля от карточки-эталона (ширина 420, высота 180).
struct WatermarkSpec {
    enum Kind { case girih, crescent }
    let kind: Kind
    let size: CGFloat      // размер узора в координатах эталона (карточка 420 шир.)
    let cx: CGFloat        // центр по X, доля ширины [0…1]
    let cy: CGFloat        // центр по Y, доля высоты [0…1]
    let rotation: Double   // поворот, градусы
    let opacity: Double
}

/// Стиль оформления карточки. Emerald — базовый (со сменой светлая/тёмная);
/// остальные — фиксированные раскраски без переключения тем.
enum AppStyle: String, CaseIterable, Identifiable {
    case emerald, oliveGold, glassGirih, crescent
    var id: String { rawValue }

    /// Только у базового стиля есть переключение светлая/тёмная.
    var hasThemeToggle: Bool { self == .emerald }

    func title(ru: Bool) -> String {
        switch self {
        case .emerald:    return ru ? "Изумруд" : "Emerald"
        case .oliveGold:  return "Olive Gold"
        case .glassGirih: return "Glass girih"
        case .crescent:   return ru ? "Полумесяц" : "Crescent"
        }
    }
}

/// Хранит выбранный стиль + (для базового стиля) светлую/тёмную тему.
/// По умолчанию — Emerald, зелёная. Сохраняется в UserDefaults.
final class ThemeStore: ObservableObject {
    @Published var isDark: Bool {
        didSet { UserDefaults.standard.set(isDark, forKey: Self.themeKey) }
    }
    @Published var style: AppStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.styleKey) }
    }
    private static let themeKey = "miqat.theme.isDark"
    private static let styleKey = "miqat.theme.style"

    init() {
        isDark = UserDefaults.standard.bool(forKey: Self.themeKey)   // false => зелёная
        let raw = UserDefaults.standard.string(forKey: Self.styleKey) ?? AppStyle.emerald.rawValue
        style = AppStyle(rawValue: raw) ?? .emerald
    }

    /// Тема развёрнутой карточки под текущий стиль.
    var theme: Theme {
        switch style {
        case .emerald:    return isDark ? .dark : .green
        case .oliveGold:  return .oliveGold
        case .glassGirih: return .glassGirih
        case .crescent:   return .crescent
        }
    }

    /// Доступно ли переключение светлая/тёмная (только базовый стиль).
    var canToggleTheme: Bool { style.hasThemeToggle }

    /// Настройки/карточка в тёмном режиме? (Emerald — по isDark, новые — всегда.)
    var isDarkMood: Bool { style == .emerald ? isDark : true }

    /// Акцент свёрнутой пилюли — всегда базовый зелёный, чтобы пилюля не менялась
    /// от выбранного стиля (свёрнутый режим не трогаем).
    var pillAccent: Color { style == .emerald ? theme.accent : Theme.green.accent }

    /// Клик по карточке меняет светлую/тёмную только у базового стиля.
    func toggle() { if canToggleTheme { isDark.toggle() } }
}
