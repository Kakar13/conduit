import SwiftData
import SwiftUI

/// Routes between first-run onboarding and the terminal. When a server
/// profile exists we go straight to the terminal and connect — no home
/// screen, no chrome.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ServerProfile.lastConnectedAt, order: .reverse)
    private var profiles: [ServerProfile]

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingView()
            } else {
                TerminalScreen()
            }
        }
        .task {
            model.startObservingEvents()
        }
        .onChange(of: scenePhase) { _, phase in
            model.handleScenePhase(phase)
        }
        // Instant drop-in: connect to the most recently used server. The
        // @Query fetch lands after first appear, so re-run when it does.
        .task(id: profiles.first?.id) {
            if model.activeProfile == nil, let profile = profiles.first {
                model.connect(to: profile)
            }
        }
        // Deep links: pairing QR codes / `conduit://connect` opens straight
        // into the (new) server; `conduit://servers` opens the switcher.
        .onOpenURL { url in
            switch url.host() {
            case "connect":
                model.pair(from: url.absoluteString)
            case "servers":
                model.isShowingServers = true
            default:
                break
            }
        }
    }
}
