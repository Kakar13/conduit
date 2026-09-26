import SwiftUI

/// Shared server field set used by onboarding and the add-server sheet.
struct ServerFormFields: View {
    @Binding var name: String
    @Binding var host: String
    @Binding var username: String
    @Binding var port: String
    @Binding var reattachCommand: String

    var body: some View {
        TextField("Name (e.g. prod-web-1)", text: $name)
        TextField("Host (e.g. ec2-1-2-3-4.compute-1.amazonaws.com)", text: $host)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        TextField("Username (e.g. ec2-user or ubuntu)", text: $username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        TextField("Port", text: $port)
            .keyboardType(.numberPad)
        TextField("Reattach command (optional)", text: $reattachCommand)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}
