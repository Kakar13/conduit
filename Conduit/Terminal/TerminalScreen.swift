import SwiftUI

/// The whole point of the app: a full-bleed dark terminal. The only chrome
/// is a single status pill that appears when the bridge changes state.
struct TerminalScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var handle = TerminalHandle()

    var body: some View {
        ZStack(alignment: .top) {
            TerminalViewRepresentable(
                session: model.session,
                handle: handle
            )
            .ignoresSafeArea()

            StatusPill(
                state: model.sessionState,
                onTap: { model.isShowingServers = true },
                onRetry: { model.reconnect() }
            )
            .padding(.top, 4)
        }
        .background(Color.black)
        .task {
            // Pump remote output into the terminal. Single consumer.
            for await data in model.session.output {
                handle.view?.feed(byteArray: ArraySlice(data))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Dropped while backgrounded: drop straight back in on return.
            if phase == .active, model.sessionState == .disconnected {
                model.reconnect()
            }
        }
        .alert(
            "Trust this host?",
            isPresented: hostKeyChallengePresented,
            presenting: model.hostKeyChallenge
        ) { _ in
            Button("Trust and Connect") { model.respondToHostKeyChallenge(accept: true) }
            Button("Reject", role: .cancel) { model.respondToHostKeyChallenge(accept: false) }
        } message: { challenge in
            Text("\(challenge.host):\(challenge.port) presented a new \(challenge.keyType) host key.\n\n\(challenge.fingerprint)")
        }
        .alert(
            "Host Key Changed",
            isPresented: hostKeyAlertPresented,
            presenting: model.hostKeyAlert
        ) { alert in
            Button("Keep Blocking", role: .cancel) { model.hostKeyAlert = nil }
            Button("Reset Stored Key", role: .destructive) { model.resetKnownHost(alert) }
        } message: { alert in
            Text("The key for \(alert.host):\(alert.port) changed.\n\nExpected: \(alert.expectedFingerprint)\nGot: \(alert.presentedFingerprint)\n\nThis may be a man-in-the-middle attack. The connection was refused.")
        }
        .alert("Connection Error", isPresented: errorPresented) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: serversPresented) {
            ServerListView()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Presentation bindings

    private var hostKeyChallengePresented: Binding<Bool> {
        Binding(
            get: { model.hostKeyChallenge != nil },
            set: { if !$0 { model.respondToHostKeyChallenge(accept: false) } }
        )
    }

    private var hostKeyAlertPresented: Binding<Bool> {
        Binding(
            get: { model.hostKeyAlert != nil },
            set: { if !$0 { model.hostKeyAlert = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var serversPresented: Binding<Bool> {
        Binding(
            get: { model.isShowingServers },
            set: { model.isShowingServers = $0 }
        )
    }
}
