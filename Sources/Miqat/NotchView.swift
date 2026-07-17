import SwiftUI
import AppKit

/// Корень: чёрная пилюля ↔ карточка темы. Плавный морфинг.
struct NotchRootView: View {
    var body: some View {
        NotchContainer()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct NotchContainer: View {
    @EnvironmentObject var clock: ClockModel
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var themeStore: ThemeStore

    private var size: CGSize { state.expanded ? state.expandedSize : state.collapsedSize }
    private var theme: Theme { themeStore.theme }

    // Свёрнутая — всегда чёрная (сливается с чёлкой); развёрнутая — заливка стиля
    // (градиент или сплошной цвет).
    private var fill: AnyShapeStyle { state.expanded ? theme.cardStyle : AnyShapeStyle(.black) }

    private var shape: UnevenRoundedRectangle {
        let top: CGFloat = state.detached ? 20 : 0   // парящая карточка скруглена со всех сторон
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: 20,
                                      bottomTrailingRadius: 20, topTrailingRadius: top)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(fill)
            if state.expanded, themeStore.style == .custom, let bg = themeStore.backgroundImage {
                CustomBackground(image: bg, scale: themeStore.bgScale,
                                 offsetX: themeStore.bgOffsetX, offsetY: themeStore.bgOffsetY,
                                 size: size)
                    .clipShape(shape).allowsHitTesting(false)
            }
            if state.expanded, let wm = theme.watermark {
                Watermark(spec: wm, tint: theme.accent)
                    .clipShape(shape).allowsHitTesting(false)
            }
            Group {
                if state.expanded { ExpandedCard() } else { CollapsedPill() }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.06), lineWidth: 1))
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: state.expanded)
        .animation(.easeInOut(duration: 0.4), value: themeStore.isDark)
        .animation(.easeInOut(duration: 0.4), value: themeStore.style)
    }
}

// MARK: - Свёрнутая пилюля (всегда чёрная)

struct CollapsedPill: View {
    @EnvironmentObject var clock: ClockModel
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "moon.fill").font(.system(size: 11)).foregroundStyle(themeStore.pillAccent)
                Text(language.prayer(clock.next?.name ?? "—").uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1).fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: state.notchWidth)   // зазор под физический вырез

            HStack(spacing: 8) {
                Text(Format.big(clock.timeLeft))
                    .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1).fixedSize()
                ProgressRing(progress: clock.progress, color: themeStore.pillAccent)
                    .frame(width: 14, height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Развёрнутая карточка

struct ExpandedCard: View {
    @EnvironmentObject var clock: ClockModel
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var language: LanguageStore

    private var theme: Theme { themeStore.theme }

    var body: some View {
        VStack(spacing: 14) {
            // Шапка: слева имя + крупный таймер, справа город + Хиджра + луна
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(language.prayer(clock.next?.name ?? "—").uppercased())
                        .font(.system(size: 12, weight: .semibold)).tracking(0.5)
                        .foregroundStyle(theme.sub).lineLimit(1)
                    Text(Format.hms(clock.timeLeft))
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(theme.ink).lineLimit(1).minimumScaleFactor(0.6)
                }

                Spacer(minLength: 8)

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(PrayerEngine.cityName)
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(Format.hijri(clock.now, ru: language.isRU))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(theme.sub)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    ZStack {
                        Circle().strokeBorder(theme.accent.opacity(0.35), lineWidth: 1.5)
                        Image(systemName: "moon.fill").font(.system(size: 11)).foregroundStyle(theme.accent)
                    }
                    .frame(width: 24, height: 24)
                }
            }

            // Ряд из 6 чипов
            HStack(spacing: 5) {
                ForEach(Array(clock.chips.enumerated()), id: \.element.id) { i, chip in
                    ChipView(chip: chip, active: i == clock.activeIndex, theme: theme)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, state.detached ? 34 : state.notchHeight + 8)   // полоса под шестерёнку и в парящем режиме
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { themeStore.toggle() }   // клик по карточке = смена темы
        .onHover { state.onCardHover?($0) }
        .contextMenu {
            Button("Скрыть островок") { state.onHide?() }
            if themeStore.canToggleTheme {
                Divider()
                Button(themeStore.isDark ? "Тема: Зелёная" : "Тема: Тёмная") { themeStore.toggle() }
            }
            Divider()
            Button("Настройки…") { state.onOpenSettings?() }
            Button("Выйти из Miqat") { state.onQuit?() }
        }
        .overlay(alignment: .topTrailing) {
            SettingsGearButton(theme: theme) { state.onOpenSettings?() }
                .padding(.top, 8)
                .padding(.trailing, 14)
        }
    }
}

struct ChipView: View {
    let chip: PrayerChip
    let active: Bool
    let theme: Theme
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        VStack(spacing: 4) {
            Text(language.prayer(chip.name).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(active ? theme.activeText : theme.sub)
                .lineLimit(1)
            Image(systemName: chip.symbol)
                .font(.system(size: 12))
                .foregroundStyle(active ? theme.activeText : theme.accent)
            Text(Format.clock(chip.time))
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(active ? theme.activeText : theme.chipInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 11).fill(active ? theme.accent : theme.chipBg))
    }
}

// MARK: - Фоновый водяной знак карточки (girih / полумесяц)

/// Фоновый узор карточки — размещается точно по данным из макета (WatermarkSpec):
/// размер, центр (доля карточки), поворот, прозрачность. Эталонная карточка —
/// шириной 420, размеры масштабируются под фактическую ширину.
struct Watermark: View {
    let spec: WatermarkSpec
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 420
            let sz = spec.size * scale
            content(size: sz)
                .frame(width: sz, height: sz)
                .rotationEffect(.degrees(spec.rotation))
                .position(x: spec.cx * geo.size.width, y: spec.cy * geo.size.height)
        }
    }

    @ViewBuilder private func content(size: CGFloat) -> some View {
        switch spec.kind {
        case .girih:
            // Тесселяция girih (розетка в центре + четвертинки по углам), тонкой
            // белой линией — «гравировка» по стеклу.
            GirihPattern()
                .stroke(Color.white.opacity(spec.opacity), lineWidth: max(1, size * 0.009))
        case .crescent:
            // Крупный тусклый полумесяц (цвет акцента).
            Image(systemName: "moon.fill")
                .resizable().scaledToFit()
                .foregroundStyle(tint.opacity(spec.opacity))
        }
    }
}

/// Пользовательская картинка-фон карточки (стиль «Свой фон»). Заполняет карточку,
/// масштабируется и сдвигается по настройкам; сверху — затемнение, чтобы белый
/// текст времён читался на любой картинке.
struct CustomBackground: View {
    let image: NSImage
    let scale: Double
    let offsetX: Double   // сдвиг в долях ширины карточки [-1…1]
    let offsetY: Double   // сдвиг в долях высоты карточки [-1…1]
    let size: CGSize

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(max(1, scale), anchor: .center)
            .offset(x: offsetX * size.width, y: offsetY * size.height)
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(
                // Сверху затемняем сильнее (там таймер и город), снизу — под чипы.
                LinearGradient(colors: [.black.opacity(0.50), .black.opacity(0.22), .black.opacity(0.42)],
                               startPoint: .top, endPoint: .bottom)
            )
    }
}

/// Узор girih из макета (viewBox 120×120): центральная 16-конечная розетка
/// (две восьмиконечные звезды со сдвигом 22.5°) + такие же четвертинки по углам.
struct GirihPattern: Shape {
    // Точки звёзд — ровно из SVG-эталона.
    private static let big: [CGPoint] = [(0,-34),(9,-14),(34,-14),(14,2),(22,26),
        (0,12),(-22,26),(-14,2),(-34,-14),(-9,-14)].map { CGPoint(x: $0.0, y: $0.1) }
    private static let small: [CGPoint] = [(0,-18),(5,-7),(18,-7),(7,1),(12,14),
        (0,6),(-12,14),(-7,1),(-18,-7),(-5,-7)].map { CGPoint(x: $0.0, y: $0.1) }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = min(rect.width, rect.height) / 120   // из системы 120×120 в rect

        func star(_ pts: [CGPoint], at c: CGPoint) {
            for rot in [0.0, 22.5] {              // звезда + её копия, повёрнутая на 22.5°
                let a = rot * .pi / 180, ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
                var poly = Path()
                for (i, pt) in pts.enumerated() {
                    let rx = pt.x * ca - pt.y * sa, ry = pt.x * sa + pt.y * ca
                    let q = CGPoint(x: (c.x + rx) * s, y: (c.y + ry) * s)
                    if i == 0 { poly.move(to: q) } else { poly.addLine(to: q) }
                }
                poly.closeSubpath()
                p.addPath(poly)
            }
        }

        star(Self.big, at: CGPoint(x: 60, y: 60))
        for c in [CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 0),
                  CGPoint(x: 0, y: 120), CGPoint(x: 120, y: 120)] {
            star(Self.small, at: c)
        }
        return p
    }
}

// MARK: - Кольцо прогресса

struct ProgressRing: View {
    var progress: Double
    var color: Color
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 3)
            Circle().trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Кнопка настроек (шестерёнка в углу карточки)

struct SettingsGearButton: View {
    let theme: Theme
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hover ? theme.ink : theme.sub)
                .frame(width: 22, height: 22)
                .background(Circle().fill(theme.chipBg).opacity(hover ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Настройки")
    }
}
