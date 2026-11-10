import SwiftUI
import Observation

/// Tracks one Gemini request as a list of steps, so the UI can show what's happening.
@MainActor
@Observable
final class GeminiTask {
    enum StepState { case pending, active, done, skipped, failed }
    struct Step: Identifiable {
        let id = UUID()
        var title: String
        var state: StepState = .pending
    }

    let title: String
    private(set) var steps: [Step]
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?
    private(set) var error: String?
    private(set) var successNote: String?

    init(title: String, steps: [String]) {
        self.title = title
        self.steps = steps.map { Step(title: $0) }
    }

    var isRunning: Bool { startedAt != nil && finishedAt == nil }
    var isFinished: Bool { finishedAt != nil }
    var succeeded: Bool { isFinished && error == nil }

    func begin() {
        steps = steps.map { Step(title: $0.title) }
        startedAt = .now
        finishedAt = nil
        error = nil
        successNote = nil
    }

    /// Marks step `index` active and everything before it done.
    func step(_ index: Int, title: String? = nil) {
        for i in steps.indices {
            if i < index, steps[i].state == .active || steps[i].state == .pending { steps[i].state = .done }
            if i == index {
                steps[i].state = .active
                if let title { steps[i].title = title }
            }
        }
    }

    func skip(_ index: Int) { if steps.indices.contains(index) { steps[index].state = .skipped } }

    func succeed(_ note: String? = nil) {
        for i in steps.indices where steps[i].state == .active || steps[i].state == .pending { steps[i].state = .done }
        successNote = note
        finishedAt = .now
    }

    func fail(_ message: String) {
        if let i = steps.firstIndex(where: { $0.state == .active }) { steps[i].state = .failed }
        error = message
        finishedAt = .now
    }

    func reset() {
        startedAt = nil
        finishedAt = nil
        error = nil
        successNote = nil
        steps = steps.map { Step(title: $0.title) }
    }

    var elapsed: TimeInterval { (finishedAt ?? .now).timeIntervalSince(startedAt ?? .now) }
}

/// Card showing a Gemini request's steps, a live timer and an animated bar.
struct GeminiProgressView: View {
    let task: GeminiTask
    var compact = false
    /// Typical duration, used for the "taking longer than usual" note.
    var expectedSeconds: Double = 10

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                header
                if task.isRunning { ShimmerBar() }
                if !compact || task.error != nil {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(task.steps) { stepRow($0) }
                    }
                } else if let active = task.steps.first(where: { $0.state == .active }) {
                    Text(active.title).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                footer
            }
            .padding(compact ? 12 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.primary.opacity(task.isRunning ? 0.35 : 0.15)))
            .animation(.easeInOut(duration: 0.25), value: task.steps.map(\.state.hashValue))
        }
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 8) {
            SparkleIcon(animating: task.isRunning, failed: task.error != nil)
            Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Spacer()
            if task.startedAt != nil {
                Text(String(format: "%.0fs", task.elapsed))
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if let error = task.error {
            Text(error).font(.caption).foregroundStyle(Color(hex: 0xB5651D)).fixedSize(horizontal: false, vertical: true)
        } else if let note = task.successNote {
            Label(note, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.primary)
        } else if task.isRunning && task.elapsed > expectedSeconds * 2 {
            Text("The fitting room's busy — ClosetWise is still in there (up to about a minute).")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        } else if task.isRunning && !compact {
            Text("Usually takes \(Int(expectedSeconds / 2))–\(Int(expectedSeconds)) seconds.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private func stepRow(_ step: GeminiTask.Step) -> some View {
        HStack(spacing: 8) {
            Group {
                switch step.state {
                case .pending: Image(systemName: "circle").foregroundStyle(Theme.border)
                case .active: ProgressView().controlSize(.mini).tint(Theme.primary)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary)
                case .skipped: Image(systemName: "minus.circle").foregroundStyle(Theme.secondaryText.opacity(0.6))
                case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color(hex: 0xB5651D))
                }
            }
            .frame(width: 16)
            Text(step.title)
                .font(.caption)
                .foregroundStyle(step.state == .pending || step.state == .skipped ? Theme.secondaryText : Theme.ink)
                .strikethrough(step.state == .skipped, color: Theme.secondaryText.opacity(0.5))
        }
    }
}

/// Indeterminate bar with a moving highlight.
private struct ShimmerBar: View {
    @State private var phase: CGFloat = -0.4

    var body: some View {
        GeometryReader { g in
            Capsule().fill(Theme.primary.opacity(0.15))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.primary.opacity(0), Theme.primary, Theme.primary.opacity(0)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * 0.4)
                        .offset(x: g.size.width * phase)
                }
                .clipShape(Capsule())
        }
        .frame(height: 4)
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.0 }
        }
    }
}

private struct SparkleIcon: View {
    let animating: Bool
    let failed: Bool
    @State private var pulse = false

    var body: some View {
        Image(systemName: failed ? "exclamationmark.triangle.fill" : "sparkles")
            .foregroundStyle(failed ? Color(hex: 0xB5651D) : Theme.primary)
            .scaleEffect(animating && pulse ? 1.18 : 1)
            .opacity(animating && pulse ? 0.7 : 1)
            .animation(animating ? .easeInOut(duration: 0.7).repeatForever() : .default, value: pulse)
            .onAppear { pulse = true }
    }
}
