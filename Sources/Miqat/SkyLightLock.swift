import Cocoa
import SkyLightWindow

/// Пакет `SkyLightWindow` умеет `delegateWindow` (поднять окно на слой локскрина),
/// но не умеет вернуть его обратно. Добавляем `undelegateWindow` сами — как в
/// Boring.Notch. Использует приватный SkyLight API (ок для прямой раздачи, не App Store).
extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else { return }

        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}
