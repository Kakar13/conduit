import SwiftData
import SwiftUI

/// conduit — a fast, resilient SSH client.
///
/// The app is a single full-bleed terminal. On launch we drop straight into
/// the most recently used server; onboarding only appears when no server
/// profile exists yet.
@main
struct ConduitApp: App {
    private let container: ModelContainer
    @State private var model: AppModel

    @MainActor
    init() {
        let container = try! ModelContainer(for: ServerProfile.self, KnownHost.self)
        self.container = container
        _model = State(initialValue: AppModel(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
