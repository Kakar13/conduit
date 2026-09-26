import SwiftData
import SwiftUI

/// Routes between first-run onboarding and the terminal. When a server
/// profile exists we go straight to the terminal and connect — no home
/// screen, no chrome.
struct RootView: View {
    @Environment(AppModel.self) private var model
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
        // Instant drop-in: connect to the most recently used server. The
        // @Query fetch lands after first appear, so re-run when it does.
        .task(id: profiles.first?.id) {
            if model.activeProfile == nil, let profile = profiles.first {
                model.connect(to: profile)
            }
        }
        // Tapping the Dynamic Island live status opens the server switcher.
        .onOpenURL { url in
            if url.host() == "servers" {
                model.isShowingServers = true
            }
        }
    }
}
