import SwiftUI

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

    // Свёрнутая — всегда чёрная (сливается с чёлкой); развёрнутая — цвет темы.
    private var fill: Color { state.expanded ? theme.surface : .black }

    private var shape: UnevenRoundedRectangle {
        let top: CGFloat = state.detached ? 20 : 0   // парящая карточка скруглена со всех сторон
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: 20,
                                      bottomTrailingRadius: 20, topTrailingRadius: top)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(fill)
            Group {
                if state.expanded { ExpandedCard() } else { CollapsedPill() }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.06), lineWidth: 1))
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: state.expanded)
        .animation(.easeInOut(duration: 0.4), value: themeStore.isDark)
    }
}

// MARK: - Свёрнутая пилюля (всегда чёрная)

struct CollapsedPill: View {
    @EnvironmentObject var clock: ClockModel
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var themeStore: ThemeStore

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "moon.fill").font(.system(size: 11)).foregroundStyle(themeStore.theme.accent)
                Text((clock.next?.name ?? "—").uppercased())
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
                ProgressRing(progress: clock.progress, color: themeStore.theme.accent)
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

    private var theme: Theme { themeStore.theme }

    var body: some View {
        VStack(spacing: 14) {
            // Шапка: слева имя + крупный таймер, справа город + Хиджра + луна
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text((clock.next?.name ?? "—").uppercased())
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
                        Text(Format.hijri(clock.now))
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
            Divider()
            Button(themeStore.isDark ? "Тема: Зелёная" : "Тема: Тёмная") { themeStore.toggle() }
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

    var body: some View {
        VStack(spacing: 4) {
            Text(chip.name.uppercased())
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
