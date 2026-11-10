import SwiftUI

/// One-line account/sync status: connected, syncing, or why it's local-only.
struct CloudStatusRow: View {
    @Environment(ClosetStore.self) private var store
    private var cloud: Cloud { Cloud.shared }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(cloud.isSignedIn && cloud.lastError == nil ? Theme.primary : Theme.secondaryText)
            Text(text).lineLimit(2)
            Spacer(minLength: 0)
            if canRetry {
                Button("Retry") { Task { await cloud.start(store) } }.font(.caption.weight(.medium))
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
        .accessibilityElement(children: .combine)
    }

    private var canRetry: Bool {
        switch cloud.status {
        case .anonymousDisabled, .failed: true
        case .signedIn: cloud.lastError != nil
        default: false
        }
    }

    private var icon: String {
        if cloud.syncing { return "arrow.triangle.2.circlepath" }
        switch cloud.status {
        case .signedIn: return cloud.lastError == nil ? "checkmark.icloud" : "exclamationmark.icloud"
        case .signingIn: return "icloud"
        default: return "icloud.slash"
        }
    }

    private var text: String {
        if cloud.syncing { return "Syncing…" }
        if cloud.isSignedIn, let error = cloud.lastError { return "Sync problem: \(error)" }
        if cloud.isSignedIn, let last = cloud.lastSync { return "Synced \(last.formatted(.relative(presentation: .named)))" }
        return cloud.status.message
    }
}
