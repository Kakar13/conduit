import SwiftData
import SwiftUI

/// First run only: mint the Secure Enclave key, show the public key to add
/// to the server, take one server profile, connect. After this the app never
/// shows anything but the terminal again.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var host = ""
    @State private var username = ""
    @State private var port = "22"
    @State private var reattachCommand = ""
    @State private var publicKey: String?
    @State private var keyError: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "faceid")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Secure Enclave key")
                            .font(.headline)
                        Text(publicKey != nil ? "Created — guarded by Face ID" : "Creating…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if publicKey != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                if let publicKey {
                    Text(publicKey)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy public key") {
                        UIPasteboard.general.string = publicKey
                        copied = true
                    }
                    Text("Add this key to ~/.ssh/authorized_keys on your server (EC2: use Instance Connect, the console, or user-data).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let keyError {
                    Text(keyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("1 — Your key stays on this iPhone")
            }

            Section {
                ServerFormFields(
                    name: $name,
                    host: $host,
                    username: $username,
                    port: $port,
                    reattachCommand: $reattachCommand
                )
            } header: {
                Text("2 — Your server")
            }

            Section {
                Button(action: connect) {
                    Text("Connect")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canConnect)
            }
            }
            .navigationTitle("conduit")
            .task { ensureKey() }
        }
    }

    private var canConnect: Bool {
        publicKey != nil && !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func ensureKey() {
        guard publicKey == nil, keyError == nil else { return }
        do {
            if !model.keyStore.keyExists() {
                try model.keyStore.createKey()
            }
            publicKey = try model.keyStore.openSSHPublicKey()
        } catch {
            keyError = error.localizedDescription
        }
    }

    private func connect() {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        let profile = ServerProfile(
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? trimmedHost : name,
            host: trimmedHost,
            port: Int(port) ?? 22,
            username: username.trimmingCharacters(in: .whitespaces),
            reattachCommand: reattachCommand.trimmingCharacters(in: .whitespaces)
        )
        modelContext.insert(profile)
        try? modelContext.save()
        model.connect(to: profile)
    }
}
