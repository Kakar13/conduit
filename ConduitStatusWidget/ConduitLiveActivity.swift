import ActivityKit
import SwiftUI
import WidgetKit

/// Renders the bridge status in the Dynamic Island and on the Lock Screen.
/// The system renders this out-of-process; the app only pushes
/// `ContentState` updates via ActivityKit.
struct ConduitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConduitActivityAttributes.self) { context in
            // MARK: Lock Screen
            HStack(spacing: 8) {
                Circle()
                    .fill(color(for: context.state.status))
                    .frame(width: 8, height: 8)
                Text(text(for: context.state))
                    .font(.system(.footnote, design: .monospaced))
                Spacer()
                Text(context.attributes.serverName)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded (long-press)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: context.state.status))
                            .frame(width: 8, height: 8)
                        Text(text(for: context.state))
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.serverName)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.serverDetail)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } compactLeading: {
                // MARK: Compact
                Circle()
                    .fill(color(for: context.state.status))
                    .frame(width: 7, height: 7)
            } compactTrailing: {
                Text(compactText(for: context.state))
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(1)
            } minimal: {
                // MARK: Minimal (island shared with another activity)
                Circle()
                    .fill(color(for: context.state.status))
                    .frame(width: 6, height: 6)
            }
            .keylineTint(color(for: context.state.status))
            .widgetURL(URL(string: "conduit://servers"))
        }
    }

    private func color(for status: ConduitActivityAttributes.ContentState.Status) -> Color {
        switch status {
        case .connecting: .yellow
        case .connected: .green
        case .reconnecting: .orange
        case .offline: .red
        }
    }

    private func text(for state: ConduitActivityAttributes.ContentState) -> String {
        switch state.status {
        case .connecting: "connecting…"
        case .connected: "connected"
        case .reconnecting: "reconnecting (\(state.attempt))…"
        case .offline: "offline"
        }
    }

    /// The compact trailing slot is narrow: prefer the attempt count while
    /// reconnecting, otherwise a short status word.
    private func compactText(for state: ConduitActivityAttributes.ContentState) -> String {
        switch state.status {
        case .connecting: "…"
        case .connected: "ssh"
        case .reconnecting: "×\(state.attempt)"
        case .offline: "off"
        }
    }
}
