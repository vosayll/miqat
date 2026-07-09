import AppKit
#if !APPSTORE
import SkyLightWindow
#endif

/// Платформенное размещение островка на экране. Две реализации выбираются на
/// этапе сборки (см. Package.swift и флаг APPSTORE):
///
/// • ОБЫЧНАЯ сборка (прямая раздача) — приватные API Apple:
///   — «на всех рабочих столах» через собственное CGS-пространство (`CGSSpace`);
///   — показ на заблокированном экране через SkyLight (`SkyLightOperator`).
///   Мощнее, но Mac App Store такое не пропускает.
///
/// • Сборка для APP STORE — только публичные, разрешённые API:
///   — «на всех рабочих столах» через `NSWindow.collectionBehavior`
///     (`.canJoinAllSpaces` + `.fullScreenAuxiliary`) — максимально близкий
///     легальный аналог: островок так же виден на всех десктопах и поверх
///     полноэкранных приложений;
///   — показа на локскрине НЕТ: публичного API для рисования на заблокированном
///     экране не существует (Apple его намеренно запрещает), островок там просто
///     прячется. Аналога нет — эта фича только у прямой раздачи.
///
/// Весь код, зависящий от приватных API, изолирован здесь — остальное приложение
/// про разницу сборок не знает и работает одинаково.
final class SpacePlacement {
    private let panel: NSPanel

    #if !APPSTORE
    // Приватный путь: отдельное CGS-пространство максимального уровня. Держим
    // ссылку живой — при деините пространство уничтожается (см. CGSSpace.deinit).
    private let cgsSpace = CGSSpace(level: 2147483647)
    #endif

    init(panel: NSPanel) {
        self.panel = panel
    }

    /// Показывать островок на всех рабочих столах и поверх full-screen.
    func showOnAllSpaces() {
        #if APPSTORE
        // Публичный аналог: окно «прилипает» ко всем Spaces, живёт над
        // полноэкранными приложениями и не участвует в переключении окон.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
        #else
        cgsSpace.windows.insert(panel)
        #endif
    }

    /// Показ островка на заблокированном экране. В App Store-сборке — пусто
    /// (публичного API нет). `onReveal` вызывается на блокировке, чтобы
    /// приложение проявило островок перед подъёмом на слой локскрина.
    func observeLockScreen(onReveal: @escaping () -> Void) {
        #if !APPSTORE
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            onReveal()
            SkyLightOperator.shared.delegateWindow(self.panel)
            self.panel.orderFrontRegardless()
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            SkyLightOperator.shared.undelegateWindow(self.panel)
        }
        #endif
    }
}
