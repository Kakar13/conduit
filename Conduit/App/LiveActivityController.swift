import ActivityKit
import Foundation

/// Mirrors the SSH bridge state into the Dynamic Island and Lock Screen via
/// a Live Activity. Started on the first connect, updated on every state
/// change, ended on disconnect.
///
/// ActivityKit's `Activity` struct is not `Sendable` in the SDK, so Swift 6
/// rejects handing it from an actor-isolated context to ActivityKit's
/// nonisolated async methods. The calls themselves are safe — ActivityKit
/// marshals to its daemon — so we funnel every ActivityKit call through
/// small nonisolated helpers and hand the activity over inside an
/// explicitly-unchecked Sendable box. All controller state stays on the
/// main actor, which also keeps update ordering.
@MainActor
final class LiveActivityController {
    private var activity: Activity<ConduitActivityAttributes>?

    /// Feeds a session state change into the Live Activity.
    func handle(state: SSHSession.State, serverName: String?, serverDetail: String?) {
        Task {
            await apply(state: state, serverName: serverName, serverDetail: serverDetail)
        }
    }

    /// Ends any activity left over from a previous app run. Call at launch.
    func endStaleActivities() {
        Task {
            await Self.endAllExisting()
        }
    }

    /// Ends the current activity immediately, if any (user disconnect, or
    /// the app is about to be suspended).
    func endNow() {
        Task { await endActivity() }
    }

    // MARK: - Internals (main-actor)

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
            let box = ActivityBox(activity)
            let content = ActivityContent(state: contentState, staleDate: nil)
            await Self.performUpdate(box, content: content)
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
        let box = ActivityBox(activity)
        await Self.performEnd(box)
    }

    // MARK: - ActivityKit bridge (nonisolated)

    /// The one sanctioned unchecked crossing: `Activity` is SDK-non-Sendable
    /// but thread-safe; the box makes the single hand-off explicit.
    private final class ActivityBox: @unchecked Sendable {
        let activity: Activity<ConduitActivityAttributes>

        init(_ activity: Activity<ConduitActivityAttributes>) {
            self.activity = activity
        }
    }

    /// All ActivityKit async methods are called from nonisolated context —
    /// values never cross an isolation boundary.
    private nonisolated static func performUpdate(
        _ box: ActivityBox,
        content: ActivityContent<ConduitActivityAttributes.ContentState>
    ) async {
        await box.activity.update(content)
    }

    private nonisolated static func performEnd(_ box: ActivityBox) async {
        await box.activity.end(nil, dismissalPolicy: .immediate)
    }

    private nonisolated static func endAllExisting() async {
        for activity in Activity<ConduitActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
