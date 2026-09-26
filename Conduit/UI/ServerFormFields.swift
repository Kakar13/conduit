import SwiftUI

/// Shared server field set used by onboarding and the add-server sheet.
struct ServerFormFields: View {
    @Binding var name: String
    @Binding var host: String
    @Binding var username: String
    @Binding var port: String
    @Binding var reattachCommand: String

    private var mono: Font { .system(.body, design: .monospaced) }

    var body: some View {
        TextField("Name (e.g. prod-web-1)", text: $name)
        TextField("Host (e.g. ec2-1-2-3-4.compute-1.amazonaws.com)", text: $host)
            .font(mono)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        TextField("Username (e.g. ec2-user or ubuntu)", text: $username)
            .font(mono)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        TextField("Port", text: $port)
            .font(mono)
            .keyboardType(.numberPad)
        TextField("Reattach command (optional)", text: $reattachCommand)
            .font(mono)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}
