import AppKit
import SwiftUI
import SkyLightWindow

/// Состояние чёлки, общее между окном (AppKit) и интерфейсом (SwiftUI).
final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var notchWidth:  CGFloat = 190
    @Published var notchHeight: CGFloat = 32
    @Published var collapsedSize = CGSize(width: 350, height: 34)
    @Published var expandedSize  = CGSize(width: 380, height: 440)
}

/// Окно-панель у выреза сверху по центру.
/// • держится на всех Spaces (через CGSSpace);
/// • показывается на заблокированном экране (через SkyLight);
/// • окно ФИКСИРОВАННОГО размера, клики проходят насквозь (ignoresMouseEvents);
/// • пилюля «вырастает» в панель средствами SwiftUI — плавно, без рывков окна;
/// • наведение ловим по позиции мыши (глобальный монитор) + гистерезис.
final class NotchController {
    private let panel: NSPanel
    private let state = NotchState()
    private let clock: ClockModel
    private let notchSpace = CGSSpace(level: 2147483647)   // все Spaces, макс. уровень

    private var moveMonitorGlobal: Any?
    private var moveMonitorLocal: Any?
    private var closeWorkItem: DispatchWorkItem?

    private let collapsedSize: CGSize
    private let expandedSize: CGSize
    private let closeDelay: TimeInterval = 0.18

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

        // Ширину пилюли считаем под самое длинное название намаза — чтобы текст не переносился.
        let names = PrayerEngine.displayNames.values.map { $0.uppercased() }
        let nameW = names.map { Self.textWidth($0, size: 11, weight: .semibold, tracking: 1.2) }.max() ?? 60
        let leftCluster  = 12 + 6 + nameW                                   // луна + отступ + название
        let rightCluster = Self.textWidth("23:59", size: 12, weight: .medium, tracking: 0) + 6 + 12
        let side = max(leftCluster, rightCluster)                           // симметрично → вырез по центру
        let collapsed = CGSize(width: nw + 2 * side + 2 * 12 + 8, height: nh)
        let expanded  = CGSize(width: 380, height: 440)
        collapsedSize = collapsed
        expandedSize  = expanded

        panel = NSPanel(contentRect: NSRect(origin: .zero, size: expanded),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true       // клики проходят насквозь; наведение — через монитор

        state.notchWidth = nw
        state.notchHeight = nh
        state.collapsedSize = collapsed
        state.expandedSize = expanded

        let root = NotchRootView()
            .environmentObject(clock)
            .environmentObject(state)
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    func show() {
        positionWindow()
        panel.orderFrontRegardless()
        notchSpace.windows.insert(panel)      // показывать на всех Spaces
        startMouseTracking()
        setupLockScreen()                     // показывать на заблокированном экране
    }

    /// Окно всегда одного размера (развёрнутого) и не двигается — контент рисуется сверху.
    private func positionWindow() {
        guard let screen = NotchController.notchScreen() else { return }
        let sf = screen.frame
        let x = sf.minX + (sf.width - expandedSize.width) / 2
        let y = sf.maxY - expandedSize.height
        panel.setFrame(NSRect(x: x, y: y, width: expandedSize.width, height: expandedSize.height),
                       display: true)
    }

    // MARK: - Локскрин (SkyLight)

    private func setupLockScreen() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.state.expanded = false                       // на локскрине — свёрнутая пилюля
            SkyLightOperator.shared.delegateWindow(self.panel)
            self.panel.orderFrontRegardless()
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            SkyLightOperator.shared.undelegateWindow(self.panel)
        }
    }

    // MARK: - Наведение по позиции мыши (без мерцания)

    private func startMouseTracking() {
        moveMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.evaluateHover()
        }
        moveMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.evaluateHover()
            return event
        }
        evaluateHover()
    }

    private func openRect(_ sf: NSRect) -> NSRect {
        NSRect(x: sf.midX - expandedSize.width / 2, y: sf.maxY - expandedSize.height,
               width: expandedSize.width, height: expandedSize.height)
    }

    private func triggerRect(_ sf: NSRect) -> NSRect {
        let h = collapsedSize.height + 6
        return NSRect(x: sf.midX - collapsedSize.width / 2, y: sf.maxY - h,
                      width: collapsedSize.width, height: h)
    }

    private func evaluateHover() {
        guard let screen = NotchController.notchScreen() else { return }
        let sf = screen.frame
        let mouse = NSEvent.mouseLocation

        if state.expanded {
            if openRect(sf).contains(mouse) {
                cancelScheduledClose()
            } else {
                scheduleClose()
            }
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
        state.expanded = v          // SwiftUI сам анимирует морфинг пилюля↔панель
    }

    private static func notchScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    /// Приблизительная ширина строки с учётом трекинга (для расчёта размера пилюли).
    private static func textWidth(_ s: String, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat) -> CGFloat {
        let w = (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
        return ceil(w) + CGFloat(max(0, s.count - 1)) * tracking
    }
}
