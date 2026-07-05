import SwiftUI

/// Корень: чёрный контейнер, который плавно «вырастает» из пилюли в панель.
struct NotchRootView: View {
    var body: some View {
        NotchContainer()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct NotchContainer: View {
    @EnvironmentObject var clock: ClockModel
    @EnvironmentObject var state: NotchState

    private var size: CGSize { state.expanded ? state.expandedSize : state.collapsedSize }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 18,
                               bottomTrailingRadius: 18, topTrailingRadius: 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black)

            if state.expanded {
                StarPattern().clipShape(shape).transition(.opacity)
            }

            Group {
                if state.expanded {
                    ExpandedPanel().transition(.opacity)
                } else {
                    CollapsedPill().transition(.opacity)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.06), lineWidth: 1))
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: state.expanded)
    }
}

// MARK: - Свёрнутая пилюля (симметрично: вырез строго по центру, текст не переносится)

struct CollapsedPill: View {
    @EnvironmentObject var clock: ClockModel
    @EnvironmentObject var state: NotchState

    private var timeLeft: TimeInterval { clock.next?.time.timeIntervalSince(clock.now) ?? 0 }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "moon.fill").font(.system(size: 10)).foregroundStyle(Design.gold)
                Text(clock.next?.name.uppercased() ?? "—")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(Design.cream)
                    .lineLimit(1).fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: state.notchWidth)   // зазор под физический вырез

            HStack(spacing: 6) {
                Text(Format.big(timeLeft))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Design.cream)
                    .lineLimit(1).fixedSize()
                ProgressRing(progress: clock.progress).frame(width: 12, height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Развёрнутая панель

struct ExpandedPanel: View {
    @EnvironmentObject var clock: ClockModel
    @EnvironmentObject var state: NotchState

    private var timeLeft: TimeInterval { clock.next?.time.timeIntervalSince(clock.now) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("HIJRI").font(.system(size: 9, weight: .semibold)).tracking(3)
                        .foregroundStyle(Design.gold.opacity(0.7))
                    Text(Format.hijri(clock.now)).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Design.cream)
                }
                Spacer()
            }

            VStack(spacing: 4) {
                Text("UNTIL \(clock.next?.name.uppercased() ?? "")")
                    .font(.system(size: 10, weight: .semibold)).tracking(2.5)
                    .foregroundStyle(Design.gold)
                Text(Format.big(timeLeft))
                    .font(.system(size: 44, weight: .light, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Design.cream)
                Text(Format.remaining(timeLeft))
                    .font(.system(size: 12)).foregroundStyle(Design.cream.opacity(0.45))
            }
            .padding(.top, 16)

            VStack(spacing: 2) {
                ForEach(clock.slots) { slot in
                    PrayerRow(slot: slot, isNext: slot.prayer == clock.next?.prayer)
                }
            }
            .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, state.notchHeight + 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct PrayerRow: View {
    let slot: PrayerSlot
    let isNext: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isNext {
                Circle().fill(Design.gold).frame(width: 5, height: 5)
            }
            Text(slot.name)
            Spacer()
            Text(Format.clock(slot.time)).monospacedDigit()
        }
        .font(.system(size: 14, weight: isNext ? .semibold : .regular))
        .foregroundStyle(isNext ? Design.gold : Design.cream.opacity(0.8))
        .padding(.vertical, 8).padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isNext ? Design.gold.opacity(0.12) : Color.clear)
        )
        .overlay {
            if isNext {
                RoundedRectangle(cornerRadius: 10).stroke(Design.gold.opacity(0.35), lineWidth: 1)
            }
        }
    }
}

// MARK: - Мелкие элементы

struct ProgressRing: View {
    var progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 2)
            Circle().trim(from: 0, to: progress)
                .stroke(Design.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Фоновый узор из восьмиконечных звёзд (низкая насыщенность).
struct StarPattern: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 66
            let radius: CGFloat = 20
            var row = 0
            var y: CGFloat = 6
            while y < size.height + spacing {
                var x: CGFloat = (row % 2 == 0) ? 10 : 10 + spacing / 2
                while x < size.width + spacing {
                    ctx.stroke(Self.star(center: CGPoint(x: x, y: y), radius: radius),
                               with: .color(Design.gold.opacity(0.10)),
                               lineWidth: 0.7)
                    x += spacing
                }
                y += spacing; row += 1
            }
        }
        .allowsHitTesting(false)
    }

    static func star(center: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        let points = 8
        let inner = Double(radius) * 0.42
        for i in 0 ..< (points * 2) {
            let angle = Double(i) * .pi / Double(points) - .pi / 2
            let r = (i % 2 == 0) ? Double(radius) : inner
            let pt = CGPoint(x: Double(center.x) + cos(angle) * r,
                             y: Double(center.y) + sin(angle) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
