import QuartzCore
import os

/// Counts late frames ("hitches") while the app runs, for scroll-performance tests.
/// Off unless the app is launched with `-measureHitches` (only the UI performance test does that).
final class FrameHitchMonitor: NSObject {
    static let shared = FrameHitchMonitor()
    private let log = Logger(subsystem: "app.closetwise.perf", category: "hitches")
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0, hitches = 0
    private var hitchTime: CFTimeInterval = 0, elapsed: CFTimeInterval = 0, worst: CFTimeInterval = 0

    static func startIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-measureHitches") else { return }
        shared.start()
    }

    private func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.report() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last > 0 else { return }
        let delta = link.timestamp - last
        let expected = link.targetTimestamp - link.timestamp
        guard delta < 1 else { return }   // app was in the background
        frames += 1
        elapsed += delta
        if delta > expected * 1.5 {
            hitches += 1
            hitchTime += delta - expected
            worst = max(worst, delta)
        }
    }

    /// Logs the last 2-second window, then starts a new one.
    private func report() {
        guard elapsed > 0 else { return }
        let ratio = hitchTime * 1000 / elapsed   // ms of hitch per second, like Xcode's metric
        log.notice("HITCHES frames=\(self.frames) hitches=\(self.hitches) hitchMsPerSec=\(ratio, format: .fixed(precision: 1)) worstFrameMs=\(self.worst * 1000, format: .fixed(precision: 0))")
        frames = 0; hitches = 0; hitchTime = 0; elapsed = 0; worst = 0
    }
}
