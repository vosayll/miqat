import SwiftUI
import AppKit

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

    /// «Свой фон» — палитра поверх пользовательской картинки: светлый текст,
    /// полупрозрачные тёмные чипы. Сама картинка рисуется отдельным слоем
    /// (см. NotchView), поверх неё — затемнение для читаемости.
    static let custom = Theme(
        accent:     Color(hex: 0x34D399),
        ink:        .white,
        sub:        Color.white.opacity(0.72),
        surface:    Color(hex: 0x0C100E),      // запасной фон, пока картинка не выбрана
        chipBg:     Color.black.opacity(0.30),
        chipInk:    Color.white.opacity(0.85),
        activeText: Color(hex: 0x04140D)
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
    case emerald, glassGirih, crescent, custom
    var id: String { rawValue }

    /// Только у базового стиля есть переключение светлая/тёмная.
    var hasThemeToggle: Bool { self == .emerald }

    func title(ru: Bool) -> String {
        switch self {
        case .emerald:    return ru ? "Изумруд" : "Emerald"
        case .glassGirih: return "Glass girih"
        case .crescent:   return ru ? "Полумесяц" : "Crescent"
        case .custom:     return ru ? "Свой фон" : "Custom"
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

    // MARK: Кастомный фон (стиль .custom)
    /// Картинка-фон (nil — не выбрана). Хранится копией в Application Support.
    @Published private(set) var backgroundImage: NSImage?
    /// Масштаб картинки внутри карточки (1.0 = вписана «по заполнению»).
    @Published var bgScale: Double {
        didSet { UserDefaults.standard.set(bgScale, forKey: Self.bgScaleKey) }
    }
    /// Сдвиг картинки в долях размера карточки (−1…1) — чтобы выбрать фрагмент.
    @Published var bgOffsetX: Double {
        didSet { UserDefaults.standard.set(bgOffsetX, forKey: Self.bgOffsetXKey) }
    }
    @Published var bgOffsetY: Double {
        didSet { UserDefaults.standard.set(bgOffsetY, forKey: Self.bgOffsetYKey) }
    }

    private static let themeKey = "miqat.theme.isDark"
    private static let styleKey = "miqat.theme.style"
    private static let bgScaleKey = "miqat.bg.scale"
    private static let bgOffsetXKey = "miqat.bg.offsetX"
    private static let bgOffsetYKey = "miqat.bg.offsetY"

    init() {
        let d = UserDefaults.standard
        isDark = d.bool(forKey: Self.themeKey)   // false => зелёная
        let raw = d.string(forKey: Self.styleKey) ?? AppStyle.emerald.rawValue
        style = AppStyle(rawValue: raw) ?? .emerald
        bgScale = d.object(forKey: Self.bgScaleKey) as? Double ?? 1.0
        bgOffsetX = d.double(forKey: Self.bgOffsetXKey)
        bgOffsetY = d.double(forKey: Self.bgOffsetYKey)
        backgroundImage = Self.loadBackgroundImage()
    }

    /// Тема развёрнутой карточки под текущий стиль.
    var theme: Theme {
        switch style {
        case .emerald:    return isDark ? .dark : .green
        case .glassGirih: return .glassGirih
        case .crescent:   return .crescent
        case .custom:     return .custom
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

    // MARK: Картинка кастомного фона — копия в Application Support

    /// Application Support/Miqat/background.img — куда копируем выбранную картинку.
    private static var backgroundFileURL: URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Miqat", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("background.img")
    }

    private static func loadBackgroundImage() -> NSImage? {
        guard let url = backgroundFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Скопировать выбранную картинку в папку приложения и сделать её фоном.
    func setBackground(from url: URL) {
        guard let dest = Self.backgroundFileURL else { return }
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: url, to: dest)
            backgroundImage = NSImage(contentsOf: dest)
        } catch {
            NSLog("[Miqat] setBackground failed: %@", String(describing: error))
        }
    }

    /// Убрать картинку кастомного фона.
    func clearBackground() {
        if let dest = Self.backgroundFileURL { try? FileManager.default.removeItem(at: dest) }
        backgroundImage = nil
    }
}
