import SwiftUI

/// The only persistent UI chrome: a tiny Liquid Glass capsule reporting
/// bridge state, branded with the terminal glyph (colored LED dots would
/// collide with iOS's own green/orange/red system indicators). Connected →
/// just the glyph (tap for servers). Anything else → glyph + state label;
/// tapping while offline or reconnecting retries immediately.
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
            Image(systemName: "apple.terminal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .glassEffect(.regular.interactive())
        case .idle:
            EmptyView()
        default:
            HStack(spacing: 6) {
                Image(systemName: "apple.terminal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular.interactive())
        }
    }

    /// State colors are only ever applied to text — never to pill
    /// backgrounds — so they can't be mistaken for iOS system indicators.
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
