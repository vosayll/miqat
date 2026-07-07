import Foundation
import Combine

/// Тикает раз в секунду: текущее время, расписание чипов, следующий пункт,
/// индекс текущего периода и прогресс (для кольца).
final class ClockModel: ObservableObject {
    @Published var now: Date = Date()
    @Published var chips: [PrayerChip] = []
    @Published var next: PrayerChip?
    @Published var activeIndex: Int = 0
    @Published var progress: Double = 0

    /// Вызывается после каждого пересчёта (для перепланирования напоминаний).
    var onRefresh: (() -> Void)?

    private var timer: Timer?

    init() {
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Сколько осталось до следующего пункта.
    var timeLeft: TimeInterval { next.map { $0.time.timeIntervalSince(now) } ?? 0 }

    private func tick() {
        now = Date()
        if let n = next, now >= n.time {
            refresh()
        } else {
            updateProgress()
        }
    }

    func refresh() {
        now = Date()
        chips = PrayerEngine.chips(on: now)
        next = PrayerEngine.nextChip(after: now)
        activeIndex = PrayerEngine.activeIndex(now: now)
        updateProgress()
        onRefresh?()
    }

    private func updateProgress() {
        guard let n = next else { progress = 0; return }
        let start = PrayerEngine.currentStart(before: now)
        let total = n.time.timeIntervalSince(start)
        progress = total > 0 ? min(1, max(0, now.timeIntervalSince(start) / total)) : 0
    }
}
