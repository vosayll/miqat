import SwiftUI

/// Тема оформления островка. Переключается кликом по островку.
struct Theme {
    let accent: Color
    let ink: Color
    let sub: Color
    let surface: Color
    let chipBg: Color
    let chipInk: Color
    let activeText: Color

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
}

/// Хранит выбранную тему и сохраняет её в UserDefaults. По умолчанию — зелёная.
final class ThemeStore: ObservableObject {
    @Published var isDark: Bool {
        didSet { UserDefaults.standard.set(isDark, forKey: Self.key) }
    }
    private static let key = "miqat.theme.isDark"

    init() { isDark = UserDefaults.standard.bool(forKey: Self.key) }   // false => зелёная

    var theme: Theme { isDark ? .dark : .green }
    func toggle() { isDark.toggle() }
}
