import SwiftUI
import AppKit

/// Приложение живёт в чёлке + иконка в строке меню (без окна и иконки в доке).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)      // без иконки в доке
        let clock = ClockModel()
        let controller = NotchController(clock: clock)
        controller.show()
        self.controller = controller
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
