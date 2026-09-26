import SwiftData
import SwiftUI

/// Server switcher and key management, presented as a sheet over the
/// terminal. Select a server to swap the bridge instantly.
struct ServerListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ServerProfile.lastConnectedAt, order: .reverse)
    private var profiles: [ServerProfile]

    @State private var isAddingServer = false
    @State private var publicKey: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Servers") {
                    ForEach(profiles) { profile in
                        Button {
                            select(profile)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text("\(profile.username)@\(profile.host):\(profile.port)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.id == model.activeProfile?.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .onDelete(perform: delete)
                    Button("Add Server…") { isAddingServer = true }
                }

                Section("Server key (Secure Enclave)") {
                    if let publicKey {
                        Text(publicKey)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button("Copy public key") {
                            UIPasteboard.general.string = publicKey
                        }
                    }
                }
            }
            .navigationTitle("conduit")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isAddingServer) {
                AddServerView()
            }
        }
        .task { publicKey = try? model.keyStore.openSSHPublicKey() }
    }

    private func select(_ profile: ServerProfile) {
        dismiss()
        model.connect(to: profile)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(profiles[index])
        }
        try? modelContext.save()
    }
}

/// Minimal add-server form.
struct AddServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var host = ""
    @State private var username = ""
    @State private var port = "22"
    @State private var reattachCommand = ""

    var body: some View {
        NavigationStack {
            Form {
                ServerFormFields(
                    name: $name,
                    host: $host,
                    username: $username,
                    port: $port,
                    reattachCommand: $reattachCommand
                )
            }
            .navigationTitle("Add Server")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
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
        dismiss()
    }
}
