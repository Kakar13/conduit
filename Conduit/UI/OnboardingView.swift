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
        VStack(spacing: 0) {
            hero

            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "faceid")
                            .font(.title2)
                            .foregroundStyle(.green)
                            .symbolRenderingMode(.hierarchical)
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
                        Button {
                            UIPasteboard.general.string = publicKey
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy public key",
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        Text("Add this key to ~/.ssh/authorized_keys on your server (EC2: use Instance Connect, the console, or user-data).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let keyError {
                        Label(keyError, systemImage: "exclamationmark.triangle")
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
            }
            .scrollDismissesKeyboard(.interactively)

            // Floating glass CTA.
            Button(action: connect) {
                Text("Connect")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canConnect)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color.black)
        .task { ensureKey() }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image("AppIconImage")
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: .green.opacity(0.25), radius: 18, y: 6)
            Text("conduit")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("SSH, distilled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 28)
        .padding(.bottom, 8)
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
