import Foundation
import Combine

/// Тикает раз в секунду: текущее время, времена намаза, следующий намаз,
/// прогресс от предыдущего намаза к следующему (для кольца).
final class ClockModel: ObservableObject {
    @Published var now: Date = Date()
    @Published var slots: [PrayerSlot] = []
    @Published var next: PrayerSlot?
    @Published var progress: Double = 0

    private var timer: Timer?

    init() {
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

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
        slots = PrayerEngine.slots(on: now)
        next = PrayerEngine.next(after: now)
        updateProgress()
    }

    private func updateProgress() {
        guard let n = next, let prev = PrayerEngine.previousTime(before: now) else { progress = 0; return }
        let total = n.time.timeIntervalSince(prev)
        progress = total > 0 ? min(1, max(0, now.timeIntervalSince(prev) / total)) : 0
    }
}
