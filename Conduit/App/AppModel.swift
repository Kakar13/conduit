import Foundation
import SwiftData
import SwiftUI
import UIKit

/// The observable heart of the app. Owns the SSH session actor, pipes its
/// events into UI state, and coordinates the biometric gate that guards the
/// Secure Enclave keys.
@MainActor
@Observable
final class AppModel {
    // MARK: UI state

    private(set) var sessionState: SSHSession.State = .idle
    var activeProfile: ServerProfile?

    /// Set when the server presents a host key we have never seen. The UI
    /// must call `respondToHostKeyChallenge(accept:)`.
    var hostKeyChallenge: HostKeyChallenge?

    /// Set when the server's host key *changed* — a possible MITM. The
    /// connection is always refused; the user can clear the stored key.
    var hostKeyAlert: HostKeyAlert?

    var errorMessage: String?
    var isShowingServers = false

    // MARK: Services

    let session: SSHSession
    let keyStore: SecureEnclaveKeyStore
    private let biometrics: BiometricAuthenticator
    private let liveActivity = LiveActivityController()
    private let modelContext: ModelContext
    private var eventTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let keyStore = SecureEnclaveKeyStore()
        let knownHosts = KnownHostStore(modelContext: modelContext)
        self.keyStore = keyStore
        self.biometrics = BiometricAuthenticator()
        self.session = SSHSession(keyStore: keyStore, hostKeyVerifier: knownHosts)
    }

    // MARK: Event pump

    /// Consumes the session's event stream. Idempotent; call once at launch.
    func startObservingEvents() {
        guard eventTask == nil else { return }
        liveActivity.endStaleActivities()
        eventTask = Task { [weak self] in
            guard let session = self?.session else { return }
            for await event in session.events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: SSHSession.Event) {
        switch event {
        case .stateChanged(let state):
            sessionState = state
            liveActivity.handle(
                state: state,
                serverName: activeProfile?.name,
                serverDetail: activeProfile.map { "\($0.username)@\($0.host):\($0.port)" }
            )
        case .hostKeyChallenge(let challenge):
            hostKeyChallenge = challenge
        case .hostKeyAlert(let alert):
            hostKeyAlert = alert
        }
    }

    // MARK: Connections

    /// Face ID gate, then connect. Safe to call while connected — the
    /// session tears the old bridge down first.
    func connect(to profile: ServerProfile) {
        activeProfile = profile
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await biometrics.requireAuthentication(
                    reason: "Unlock the key for \(profile.name)"
                )
                try await session.connect(to: profile.endpoint)
                guard !Task.isCancelled else { return }
                profile.lastConnectedAt = .now
                try? modelContext.save()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                // Host key problems already have their own dedicated alerts.
                if let sshError = error as? SSHSessionError, sshError == .hostKeyRejected { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    func disconnect() {
        connectTask?.cancel()
        activeProfile = nil
        Task { await session.disconnect() }
    }

    /// Automatic reconnects after a network handoff must not hit the Face ID
    /// prompt again within the biometric reuse window; `connect(to:)` already
    /// funnels through the gate, and the gate no-ops while fresh.
    func reconnect() {
        guard let activeProfile else { return }
        connect(to: activeProfile)
    }

    // MARK: Pairing

    /// Creates a profile from a scanned/opened `conduit://connect` payload
    /// and connects immediately.
    func pair(from code: String) {
        guard let payload = PairingPayload.parse(code) else {
            errorMessage = "That isn't a conduit pairing code."
            return
        }
        let profile = ServerProfile(
            name: payload.name,
            host: payload.host,
            port: payload.port,
            username: payload.user
        )
        modelContext.insert(profile)
        try? modelContext.save()
        connect(to: profile)
    }

    // MARK: Background suspension

    /// iOS gives a short grace period in the background, then suspends the
    /// app and closes its sockets. We keep the bridge alive through that
    /// window (quick app switches survive), and on expiry we close it
    /// ourselves and end the Live Activity — nothing may claim "connected"
    /// while we're suspended. The profile is kept so returning to the app
    /// drops straight back in.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard activeProfile != nil, backgroundTask == .invalid else { return }
            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] _ in
                self?.backgroundTaskExpired()
            }
        case .active:
            endBackgroundTask()
            if needsReconnectOnActive, let activeProfile {
                needsReconnectOnActive = false
                connect(to: activeProfile)
            }
        default:
            break
        }
    }

    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var needsReconnectOnActive = false

    private func backgroundTaskExpired() {
        endBackgroundTask()
        guard activeProfile != nil else { return }
        needsReconnectOnActive = true
        liveActivity.endNow()
        // Deliberate teardown; activeProfile is intentionally preserved.
        Task { await session.disconnect() }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: Host key responses

    func respondToHostKeyChallenge(accept: Bool) {
        hostKeyChallenge = nil
        Task { await session.respondToHostKeyChallenge(accept: accept) }
    }

    /// The stored key no longer matches: wipe it so the next connect treats
    /// the server as first-use again. Only call on explicit user action.
    func resetKnownHost(_ alert: HostKeyAlert) {
        hostKeyAlert = nil
        Task { await session.resetKnownHost(host: alert.host, port: alert.port) }
    }
}

extension Error {
    /// True when the error is just `CancellationError` in disguise.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        return (self as NSError).code == NSUserCancelledError
    }
}
