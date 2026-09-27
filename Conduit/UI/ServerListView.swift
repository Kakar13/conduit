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
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                if let active = model.activeProfile {
                    Section {
                        Button(role: .destructive) {
                            dismiss()
                            model.disconnect()
                        } label: {
                            Label("Disconnect from \(active.name)", systemImage: "bolt.slash")
                        }
                    }
                }

                Section("Servers") {
                    ForEach(profiles) { profile in
                        Button {
                            select(profile)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "server.rack")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text("\(profile.username)@\(profile.host):\(profile.port)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                if profile.id == model.activeProfile?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .onDelete(perform: delete)
                    Button {
                        isAddingServer = true
                    } label: {
                        Label("Add Server…", systemImage: "plus")
                    }
                }

                Section("Server key (Secure Enclave)") {
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
                    }
                }
            }
            .navigationTitle("conduit")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isAddingServer) {
                AddServerView()
                    .presentationDetents([.medium, .large])
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
    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isScanning = true
                    } label: {
                        Label("Scan pairing QR", systemImage: "qrcode")
                    }
                    Text("Scanning a pairing QR fills the fields below — nothing is sent anywhere.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isScanning) {
                QRScannerSheet { code in
                    if let payload = PairingPayload.parse(code) {
                        name = payload.name
                        host = payload.host
                        username = payload.user
                        port = String(payload.port)
                    }
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
