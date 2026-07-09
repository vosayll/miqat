import AppKit
import SwiftUI

/// Состояние чёлки, общее между окном (AppKit) и интерфейсом (SwiftUI).
final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var notchWidth:  CGFloat = 190
    @Published var notchHeight: CGFloat = 32
    @Published var collapsedSize = CGSize(width: 350, height: 34)
    @Published var expandedSize  = CGSize(width: 430, height: 195)
    @Published var detached = false        // окно оторвано от чёлки и парит

    // Действия развёрнутой карточки — проставляет NotchController (см. init).
    var onOpenSettings: (() -> Void)?
    var onHide: (() -> Void)?
    var onQuit: (() -> Void)?
    var onCardHover: ((Bool) -> Void)?   // мышь над карточкой: держать/сворачивать
}

/// Окно-панель у выреза сверху по центру.
/// • держится на всех рабочих столах (и, в обычной сборке, на локскрине) —
///   всё платформенное размещение спрятано в `SpacePlacement`, которое само
///   выбирает приватный или публичный путь в зависимости от сборки;
/// • пилюля — клики насквозь; развёрнутая карточка ловит клики (шестерёнка→настройки);
/// • наведение → разворот; КЛИК по островку → смена темы (через мониторы);
/// • ПРАВЫЙ клик (или Ctrl+клик) → контекстное меню (скрыть/тема/выход);
/// • «Скрыть островок» — окно плавно гаснет; возврат — наведением на зону
///   чёлки или автоматически через 60 секунд (страховка);
/// • пилюля «вырастает» в карточку средствами SwiftUI.
/// NSObject — чтобы быть target'ом пунктов NSMenu (селекторы Obj-C).
final class NotchController: NSObject {
    private let panel: NSPanel
    private let state = NotchState()
    private let themeStore = ThemeStore()
    private let clock: ClockModel
    // Размещение на всех Spaces / локскрине — приватный или публичный путь
    // выбирается внутри по флагу сборки (см. SpacePlacement).
    private lazy var placement = SpacePlacement(panel: panel)

    private var moveMonitor: Any?
    private var clickMonitor: Any?
    private var closeWorkItem: DispatchWorkItem?

    // Скрытие островка: флаг + отложенный автовозврат (страховка).
    private var islandHidden = false
    private var unhideWorkItem: DispatchWorkItem?

    // Окно настроек: одно на приложение, создаётся при первом открытии.
    private var settingsController: SettingsWindowController?

    private let collapsedSize: CGSize
    private let expandedSize: CGSize
    private let closeDelay: TimeInterval = 0.18
    private let hideFadeDuration: TimeInterval = 0.25
    private let autoUnhideDelay: TimeInterval = 60
    // Запас над верхней кромкой экрана: чтобы наведение на самый верх (кромка
    // шторки, зона камеры/чёлки) считалось попаданием, а не «мимо» — NSRect
    // не включает верхнюю границу, а курсор там сидит ровно на maxY.
    private let topOverscan: CGFloat = 8

    // Перетаскивание / магнитное отлипание (прототип).
    private var dragMonitor: Any?
    private var potentialDrag = false
    private var dragging = false
    private var dragMouseStart = NSPoint.zero
    private var dragWinStart = NSPoint.zero
    private let dragThreshold: CGFloat = 6
    private let snapZone: CGFloat = 110      // магнитная зона у чёлки (px)

    init(clock: ClockModel) {
        self.clock = clock

        let screen = NotchController.notchScreen()
        let nh = max(screen?.safeAreaInsets.top ?? 0, 32)
        let nw: CGFloat = {
            if let s = screen, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
                return s.frame.width - l.width - r.width
            }
            return 190
        }()

        // Ширину пилюли считаем под самое длинное имя намаза — чтобы не переносилось.
        let nameW = PrayerEngine.names
            .map { Self.textWidth($0.uppercased(), size: 11, weight: .semibold, tracking: 1.0) }.max() ?? 60
        let leftCluster  = 12 + 6 + nameW
        let rightCluster = Self.textWidth("23:59", size: 14, weight: .semibold, tracking: 0) + 8 + 14
        let side = max(leftCluster, rightCluster)
        let collapsed = CGSize(width: nw + 2 * side + 2 * 14 + 8, height: nh)
        let expanded  = CGSize(width: 430, height: 195)
        collapsedSize = collapsed
        expandedSize  = expanded

        panel = NSPanel(contentRect: NSRect(origin: .zero, size: expanded),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        state.notchWidth = nw
        state.notchHeight = nh
        state.collapsedSize = collapsed
        state.expandedSize = expanded

        // Действия карточки → в контроллер (weak — без цикла удержания).
        state.onOpenSettings = { [weak self] in self?.openSettings() }
        state.onHide         = { [weak self] in self?.hideIsland() }
        state.onQuit         = { NSApp.terminate(nil) }
        state.onCardHover    = { [weak self] over in
            if over { self?.cancelScheduledClose() } else { self?.scheduleClose() }
        }

        let root = NotchRootView()
            .environmentObject(clock)
            .environmentObject(state)
            .environmentObject(themeStore)
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    func show() {
        positionWindow()
        panel.orderFrontRegardless()
        placement.showOnAllSpaces()
        startTracking()
        setupLockScreen()
    }

    private func positionWindow() {
        guard let screen = NotchController.notchScreen() else { return }
        let sf = screen.frame
        let x = sf.minX + (sf.width - expandedSize.width) / 2
        let y = sf.maxY - expandedSize.height
        panel.setFrame(NSRect(x: x, y: y, width: expandedSize.width, height: expandedSize.height), display: true)
    }

    // MARK: - Мониторы мыши: наведение (разворот) + клик (тема) + правый клик (меню)

    private func startTracking() {
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.evaluateHover()
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }
            if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                self.handleRightClick()  // правый клик или Ctrl+клик = контекстное меню
            } else {
                self.handleClick()
            }
        }
        // Локальный монитор — перетаскивание развёрнутой карточки (отлипание).
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return event }
            return self.handleDrag(event)
        }
        evaluateHover()
    }

    private func handleClick() {
        guard !islandHidden else { return }              // скрытый островок клики не ловит
        guard let screen = NotchController.notchScreen() else { return }
        let sf = screen.frame
        let rect = state.expanded ? openRect(sf) : triggerRect(sf)
        if rect.contains(NSEvent.mouseLocation) {
            themeStore.toggle()          // клик по островку = смена темы
        }
    }

    private func handleRightClick() {
        guard !islandHidden else { return }
        guard let screen = NotchController.notchScreen() else { return }
        let sf = screen.frame
        let rect = state.expanded ? openRect(sf) : triggerRect(sf)
        if rect.contains(NSEvent.mouseLocation) {
            showContextMenu(at: NSEvent.mouseLocation)
        }
    }

    // MARK: - Перетаскивание и магнитное отлипание (прототип)

    /// Тянем развёрнутую карточку → окно «отлипает» от чёлки и парит за курсором;
    /// бросаем у чёлки → примагничивается обратно.
    private func handleDrag(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            guard event.window === panel, state.expanded, !islandHidden else { return event }
            potentialDrag = true
            dragMouseStart = NSEvent.mouseLocation
            dragWinStart = panel.frame.origin
            return event                     // не поглощаем — клик (тема/шестерёнка) работает
        case .leftMouseDragged:
            guard potentialDrag else { return event }
            let m = NSEvent.mouseLocation
            let dx = m.x - dragMouseStart.x, dy = m.y - dragMouseStart.y
            if !dragging, abs(dx) + abs(dy) > dragThreshold {
                dragging = true
                cancelScheduledClose()
                setDetached(true)
            }
            if dragging {
                panel.setFrameOrigin(NSPoint(x: dragWinStart.x + dx, y: dragWinStart.y + dy))
                return nil                   // поглощаем — SwiftUI не реагирует во время драга
            }
            return event
        case .leftMouseUp:
            let wasDragging = dragging
            potentialDrag = false
            dragging = false
            if wasDragging { finishDrag(); return nil }
            return event
        default:
            return event
        }
    }

    /// Отпустили: близко к чёлке — примагнитить, иначе оставить парить.
    private func finishDrag() {
        guard let screen = NotchController.notchScreen() else { return }
        let sf = screen.frame
        let dockedX = sf.minX + (sf.width - expandedSize.width) / 2
        let dockedY = sf.maxY - expandedSize.height
        let o = panel.frame.origin
        if hypot(o.x - dockedX, o.y - dockedY) < snapZone { snapToNotch() }
    }

    /// Плавно вернуть окно к чёлке и выйти из режима отлипания.
    private func snapToNotch() {
        guard let screen = NotchController.notchScreen() else { return }
        let sf = screen.frame
        let target = NSRect(x: sf.minX + (sf.width - expandedSize.width) / 2,
                            y: sf.maxY - expandedSize.height,
                            width: expandedSize.width, height: expandedSize.height)
        let p = panel
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            self?.setDetached(false)
        })
    }

    private func setDetached(_ v: Bool) {
        guard state.detached != v else { return }
        state.detached = v
        panel.hasShadow = v                  // парящая карточка отбрасывает тень
    }

    private func openRect(_ sf: NSRect) -> NSRect {
        NSRect(x: sf.midX - expandedSize.width / 2, y: sf.maxY - expandedSize.height,
               width: expandedSize.width, height: expandedSize.height + topOverscan)
    }

    private func triggerRect(_ sf: NSRect) -> NSRect {
        let h = collapsedSize.height + 6
        return NSRect(x: sf.midX - collapsedSize.width / 2, y: sf.maxY - h,
                      width: collapsedSize.width, height: h + topOverscan)
    }

    /// Зона пробуждения скрытого островка: полоса у чёлки шириной с пилюлю + запас.
    private func wakeRect(_ sf: NSRect) -> NSRect {
        triggerRect(sf).insetBy(dx: -30, dy: 0)
    }

    private func evaluateHover() {
        guard let screen = NotchController.notchScreen() else { return }
        let sf = screen.frame
        let mouse = NSEvent.mouseLocation

        // Островок скрыт: ждём наведения на зону чёлки, чтобы вернуть его.
        if islandHidden {
            if wakeRect(sf).contains(mouse) { unhideIsland() }
            return
        }

        if state.detached { return }   // оторван и парит — наведением не управляем

        if state.expanded {
            if openRect(sf).contains(mouse) { cancelScheduledClose() } else { scheduleClose() }
        } else if triggerRect(sf).contains(mouse) {
            cancelScheduledClose()
            setExpanded(true)
        }
    }

    private func scheduleClose() {
        guard closeWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.closeWorkItem = nil
            guard !self.state.detached else { return }   // парит — не сворачиваем в пилюлю
            if let screen = NotchController.notchScreen(),
               !self.openRect(screen.frame).contains(NSEvent.mouseLocation) {
                self.setExpanded(false)
            }
        }
        closeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: item)
    }

    private func cancelScheduledClose() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
    }

    private func setExpanded(_ v: Bool) {
        guard state.expanded != v else { return }
        state.expanded = v
        // Развёрнутая карточка ловит клики (не проваливаются назад); пилюля —
        // сквозная, чтобы не перехватывать клики у чёлки/меню-бара.
        panel.ignoresMouseEvents = !v
    }

    // MARK: - Контекстное меню (правый клик / Ctrl+клик)

    private func showContextMenu(at point: NSPoint) {
        let menu = NSMenu()
        menu.autoenablesItems = false    // включённость пунктов задаём вручную

        let hide = NSMenuItem(title: "Скрыть островок", action: #selector(hideIslandAction), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)

        // Смена темы — через существующий ThemeStore; галочка на текущей.
        let green = NSMenuItem(title: "Тема: Зелёная", action: #selector(selectGreenTheme), keyEquivalent: "")
        green.target = self
        green.state = themeStore.isDark ? .off : .on
        menu.addItem(green)

        let dark = NSMenuItem(title: "Тема: Тёмная", action: #selector(selectDarkTheme), keyEquivalent: "")
        dark.target = self
        dark.state = themeStore.isDark ? .on : .off
        menu.addItem(dark)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Выйти из Miqat", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        // Приложение — accessory (без фокуса); активируем, иначе меню не получит клики.
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: point, in: nil)   // in: nil → экранные координаты
    }

    @objc private func hideIslandAction() { hideIsland() }
    @objc private func selectGreenTheme() { themeStore.isDark = false }
    @objc private func selectDarkTheme()  { themeStore.isDark = true }
    @objc private func quitApp()          { NSApp.terminate(nil) }

    /// Открыть (или поднять уже открытое) окно настроек.
    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(themeStore: themeStore)
        }
        settingsController?.show()
    }

    // MARK: - Скрытие/возврат островка

    /// Скрыть: свернуть карточку и плавно погасить окно. Окно остаётся на месте
    /// (alpha 0) — не трогаем ни CGSSpace, ни SkyLight; клики оно и так не ловит.
    private func hideIsland() {
        guard !islandHidden else { return }
        islandHidden = true
        cancelScheduledClose()
        setExpanded(false)               // при возврате покажется пилюля, не карточка
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = hideFadeDuration
            panel.animator().alphaValue = 0
        }
        scheduleAutoUnhide()
    }

    /// Вернуть: плавно проявить окно (наведение на зону чёлки или страховка).
    private func unhideIsland() {
        guard islandHidden else { return }
        islandHidden = false
        unhideWorkItem?.cancel()
        unhideWorkItem = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = hideFadeDuration
            panel.animator().alphaValue = 1
        }
    }

    /// Страховка: через 60 секунд островок возвращается сам в любом случае.
    /// wallDeadline — чтобы сон машины не отодвигал возврат.
    private func scheduleAutoUnhide() {
        let item = DispatchWorkItem { [weak self] in self?.unhideIsland() }
        unhideWorkItem = item
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + autoUnhideDelay, execute: item)
    }

    // MARK: - Локскрин

    /// Показ островка на заблокированном экране. Вся платформенная часть — в
    /// SpacePlacement; в App Store-сборке это no-op (публичного API нет).
    private func setupLockScreen() {
        placement.observeLockScreen(onReveal: { [weak self] in
            guard let self = self else { return }
            self.unhideIsland()          // на локскрине островок виден всегда
            self.state.expanded = false
        })
    }

    // MARK: - Экран/утилиты

    private static func notchScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private static func textWidth(_ s: String, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat) -> CGFloat {
        let w = (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
        return ceil(w) + CGFloat(max(0, s.count - 1)) * tracking
    }
}
