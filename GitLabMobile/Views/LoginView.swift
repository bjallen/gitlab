import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session
    @State private var url = ""
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("GitLab server") {
                    TextField("https://gitlab.com", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    SecureField("glpat-…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Personal access token")
                } footer: {
                    Text("Create one under Preferences → Access tokens with the `api` scope. It is stored in the iOS Keychain.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        if busy { ProgressView() } else { Text("Sign in") }
                    }
                    .disabled(busy || token.isEmpty || url.isEmpty)
                }
            }
            .navigationTitle("Sign in")
            .onAppear { if url.isEmpty { url = session.baseURL } }
        }
    }

    private func signIn() async {
        busy = true; error = nil
        defer { busy = false }
        do { try await session.signIn(baseURL: url, token: token) }
        catch { self.error = error.localizedDescription }
    }
}

struct SettingsView: View {
    @Environment(Session.self) private var session
    @State private var authorsText = ""

    var body: some View {
        NavigationStack {
            Form {
                if let me = session.me {
                    Section("Signed in as") {
                        LabeledContent("Name", value: me.name)
                        LabeledContent("Username", value: "@\(me.username)")
                        LabeledContent("Server", value: session.baseURL)
                    }
                }
                Section {
                    TextField("e.g. claude-bot", text: $authorsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveAuthors)
                } header: {
                    Text("Service accounts")
                } footer: {
                    Text("Usernames (comma-separated) whose open MRs also appear under “Mine”.")
                }
                Section {
                    Button("Sign out", role: .destructive) { session.signOut() }
                }
            }
            .navigationTitle("Account")
            .onAppear { authorsText = session.extraAuthors.joined(separator: ", ") }
            .onDisappear(perform: saveAuthors)
        }
    }

    private func saveAuthors() {
        session.extraAuthors = authorsText
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "@")) }
            .filter { !$0.isEmpty }
    }
}
