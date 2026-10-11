import SwiftUI

@main
struct GitLabMobileApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isSignedIn { RootView() }
                else if session.hasStoredToken { RestoreView() }
                else { LoginView() }
            }
            .environment(session)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            MRListView()
                .tabItem { Label("Merge Requests", systemImage: "arrow.triangle.merge") }
            ProjectListView()
                .tabItem { Label("Pipelines", systemImage: "gearshape.2") }
            SettingsView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
    }
}

/// Shown when a token is stored but the server hasn't confirmed it yet (launching offline).
struct RestoreView: View {
    @Environment(Session.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            if session.isRestoring {
                ProgressView("Connecting…")
            } else {
                ContentUnavailableView("Can't reach GitLab", systemImage: "wifi.slash",
                                       description: Text(session.baseURL))
                Button("Retry") { Task { await session.restore() } }
                    .buttonStyle(.borderedProminent)
                Button("Sign out", role: .destructive) { session.signOut() }
            }
        }
        .padding()
    }
}
