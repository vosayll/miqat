import Foundation

// Свой «драйвер интерфейса» для Sparkle. Оборачивает стандартный драйвер и ведёт
// себя как он ВО ВСЁМ, кроме двух окон, которые делаем по-человечески и на языке
// приложения:
//   • «нет обновлений» (проверка прошла, версия актуальная) → мягкое
//     «У вас последняя версия»;
//   • ошибка проверки (нет связи/сервер недоступен/битая лента) → мягкое
//     «Не удалось проверить обновления», вместо пугающего системного окна
//     «Update Error! An error occurred in retrieving update information».
// Оба окна показываем только при РУЧНОЙ проверке (из меню). При ФОНОВОЙ (авто)
// проверке молчим — не дёргаем пользователя.
// Только для .dmg-сборки (в App Store Sparkle не подключён).
#if !APPSTORE
import AppKit
import Sparkle

@MainActor
final class MiqatUpdaterUI: NSObject, SPUUserDriver {
    private let standard: SPUStandardUserDriver
    /// Была ли последняя проверка инициирована пользователем (через меню).
    private var userInitiated = false

    init(hostBundle: Bundle) {
        standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        super.init()
    }

    private var isRU: Bool {
        (UserDefaults.standard.string(forKey: "miqat.language") ?? "ru") != "en"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Мягкое информационное окно на языке приложения.
    private func present(title: String, message: String) {
        // Свернуть спиннер/окна стандартного драйвера, чтобы ничего не висело.
        standard.dismissUpdateInstallation()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: — наши два окна

    /// Проверка прошла, но новее версии нет.
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if userInitiated {
            let v = appVersion.isEmpty ? "" : " \(appVersion)"
            present(title: isRU ? "У вас последняя версия" : "You’re up to date",
                    message: isRU ? "Установлена самая свежая версия Miqat\(v)."
                                  : "Miqat\(v) is already the latest version.")
        }
        userInitiated = false
        acknowledgement()
    }

    /// Не удалось проверить (нет связи, сервер недоступен, битая лента).
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if userInitiated {
            present(title: isRU ? "Не удалось проверить обновления"
                                : "Couldn’t check for updates",
                    message: isRU ? "Нет связи с сервером обновлений. Проверьте интернет и попробуйте позже."
                                  : "Couldn’t reach the update server. Check your internet connection and try again later.")
        } else {
            standard.dismissUpdateInstallation()
        }
        userInitiated = false
        acknowledgement()
    }

    // MARK: — всё остальное: как в стандартном драйвере

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request, reply: reply)
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        userInitiated = true
        standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standard.showUpdateReleaseNotes(with: downloadData)
    }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        standard.showDownloadInitiated(cancellation: cancellation)
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standard.showDownloadDidReceiveData(ofLength: length)
    }
    func showDownloadDidStartExtractingUpdate() {
        standard.showDownloadDidStartExtractingUpdate()
    }
    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        standard.showReady(toInstallAndRelaunch: reply)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication)
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }
    func showUpdateInFocus() {
        standard.showUpdateInFocus()
    }
    func dismissUpdateInstallation() {
        standard.dismissUpdateInstallation()
    }
}
#endif
