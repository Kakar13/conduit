import ActivityKit
import Foundation

/// Mirrors the SSH bridge state into the Dynamic Island and Lock Screen via
/// a Live Activity. Started on the first connect, updated on every state
/// change, ended on disconnect.
@MainActor
final class LiveActivityController {
    private var activity: Activity<ConduitActivityAttributes>?

    /// Feeds a session state change into the Live Activity.
    func handle(state: SSHSession.State, serverName: String?, serverDetail: String?) {
        Task { await apply(state: state, serverName: serverName, serverDetail: serverDetail) }
    }

    /// Ends any activity left over from a previous app run. Call at launch.
    func endStaleActivities() {
        Task {
            for activity in Activity<ConduitActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Internals

    private func apply(state: SSHSession.State, serverName: String?, serverDetail: String?) async {
        switch state {
        case .idle:
            await endActivity()

        case .connecting:
            await updateOrStart(.init(status: .connecting), serverName: serverName, serverDetail: serverDetail)

        case .connected:
            await updateOrStart(.init(status: .connected), serverName: serverName, serverDetail: serverDetail)

        case .reconnecting(let attempt):
            await updateOrStart(.init(status: .reconnecting, attempt: attempt), serverName: serverName, serverDetail: serverDetail)

        case .disconnected:
            await updateOrStart(.init(status: .offline), serverName: serverName, serverDetail: serverDetail)
        }
    }

    private func updateOrStart(
        _ contentState: ConduitActivityAttributes.ContentState,
        serverName: String?,
        serverDetail: String?
    ) async {
        if let activity {
            await activity.update(ActivityContent(state: contentState, staleDate: nil))
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ConduitActivityAttributes(
            serverName: serverName ?? "server",
            serverDetail: serverDetail ?? ""
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: contentState, staleDate: nil)
            )
        } catch {
            // Live Activities unavailable (disabled or unsupported device):
            // the in-app pill remains the status surface.
        }
    }

    private func endActivity() async {
        guard let activity else { return }
        self.activity = nil
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
