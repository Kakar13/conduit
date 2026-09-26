import SwiftUI

/// The only persistent UI chrome: a tiny Liquid Glass capsule reporting
/// bridge state. Connected → a single green dot (tap for servers). Anything
/// else → a labeled pill; tapping while offline or reconnecting retries
/// immediately.
struct StatusPill: View {
    let state: SSHSession.State
    let onTap: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Button(action: tapped) {
            content
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .connected:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .padding(10)
                .glassEffect(.regular.interactive())
        case .idle:
            EmptyView()
        default:
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular.interactive())
        }
    }

    private var color: Color {
        switch state {
        case .connected: .green
        case .connecting: .yellow
        case .reconnecting: .orange
        case .disconnected: .red
        case .idle: .gray
        }
    }

    private var text: String {
        switch state {
        case .connecting:
            "connecting…"
        case .reconnecting(let attempt):
            "reconnecting (\(attempt))…"
        case .disconnected:
            "offline — tap to retry"
        case .connected, .idle:
            ""
        }
    }

    private func tapped() {
        switch state {
        case .disconnected, .reconnecting:
            onRetry()
        default:
            onTap()
        }
    }
}
