import SwiftUI

@main
struct GitLabMobileApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isSignedIn { RootView() } else { LoginView() }
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
