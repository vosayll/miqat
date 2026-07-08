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
        if !window.isVisible { window.center() }   // по центру экрана при открытии
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
