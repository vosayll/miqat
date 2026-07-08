import AppKit
import SwiftUI

/// Окно «Настройки Miqat» — обычное титулованное NSWindow с SwiftUI-формой
/// внутри (NSHostingController). Окно одно на приложение: живёт у
/// NotchController, повторное открытие поднимает существующее. Крестик
/// просто прячет окно — приложение продолжает жить в чёлке.
final class SettingsWindowController: NSWindowController {
    convenience init(themeStore: ThemeStore) {
        let hosting = NSHostingController(rootView: SettingsView().environmentObject(themeStore))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Настройки Miqat"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false   // иначе повторное открытие — крэш
        self.init(window: window)
    }

    /// Показать/поднять окно. Приложение — accessory (без дока и фокуса),
    /// поэтому без activate окно не станет ключевым.
    func show() {
        guard let window else { return }
        if !window.isVisible {
            // При ПЕРВОМ открытии окно ещё не разложено — frame.size неверный,
            // и центрирование уводило окно под чёлку. Фиксируем размер контента
            // (как в SettingsView) до вычисления центра.
            window.setContentSize(NSSize(width: 480, height: 620))
            // По центру ВИДИМОЙ области экрана с чёлкой (без меню-бара): center()
            // смещает высокое окно вверх, и верх уезжал под чёлку.
            let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? window.screen ?? NSScreen.main
            if let vf = screen?.visibleFrame {
                let s = window.frame.size
                window.setFrameOrigin(NSPoint(x: vf.midX - s.width / 2,
                                              y: vf.midY - s.height / 2))
            } else {
                window.center()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
