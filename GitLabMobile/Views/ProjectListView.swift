import SwiftUI

/// Pinned projects live on-device so the Pipelines tab opens on the repos you care about.
@Observable
final class PinnedProjects {
    private static let key = "gitlab.pinnedProjects"
    private(set) var projects: [Project]

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        projects = data.flatMap { try? JSONDecoder().decode([Project].self, from: $0) } ?? []
    }

    func contains(_ p: Project) -> Bool { projects.contains { $0.id == p.id } }

    func toggle(_ p: Project) {
        if let i = projects.firstIndex(where: { $0.id == p.id }) { projects.remove(at: i) } else { projects.append(p) }
        if let d = try? JSONEncoder().encode(projects) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}

struct ProjectListView: View {
    @Environment(Session.self) private var session
    @State private var pinned = PinnedProjects()
    @State private var results: [Project] = []
    @State private var search = ""
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorBanner(message: error) }
                if search.isEmpty && !pinned.projects.isEmpty {
                    Section("Pinned") { ForEach(pinned.projects) { row($0) } }
                }
                Section(search.isEmpty ? "Recently active" : "Results") {
                    ForEach(results) { row($0) }
                }
            }
            .overlay { if loading && results.isEmpty { ProgressView() } }
            .navigationTitle("Pipelines")
            .navigationDestination(for: Project.self) { ProjectPipelinesView(project: $0) }
            .navigationDestination(for: PipelineRef.self) {
                PipelineDetailView(projectId: $0.projectId, pipelineId: $0.pipelineId)
            }
            .searchable(text: $search, prompt: "Search projects")
            .refreshable { await fetch() }
            .task(id: search) {
                if !search.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }  // debounce
                guard !Task.isCancelled else { return }
                await fetch()
            }
        }
    }

    private func row(_ p: Project) -> some View {
        NavigationLink(value: p) {
            VStack(alignment: .leading) {
                Text(p.name).font(.headline)
                Text(p.nameWithNamespace).font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button(pinned.contains(p) ? "Unpin" : "Pin", systemImage: "pin") { pinned.toggle(p) }
                .tint(.orange)
        }
    }

    private func fetch() async {
        guard let client = session.client else { return }
        loading = true; defer { loading = false }
        do { results = try await client.projects(search: search); error = nil }
        catch is CancellationError {}
        catch let e as URLError where e.code == .cancelled {}
        catch { self.error = error.localizedDescription }
    }
}

struct ProjectPipelinesView: View {
    @Environment(Session.self) private var session
    let project: Project

    @State private var pipelines: [Pipeline] = []
    @State private var statusFilter: String?
    @State private var loading = false
    @State private var error: String?

    private let filters = ["running", "pending", "failed", "success", "manual"]

    var body: some View {
        List {
            if let error { ErrorBanner(message: error) }
            ForEach(pipelines) { p in
                NavigationLink(value: PipelineRef(projectId: project.id, pipelineId: p.id)) {
                    PipelineRow(pipeline: p)
                }
                .swipeActions(edge: .leading) {
                    if p.status == "failed" {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            Task { await act { try await $0.retryPipeline(project: project.id, id: p.id) } }
                        }.tint(.blue)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if ["running", "pending"].contains(p.status) {
                        Button("Cancel", systemImage: "stop") {
                            Task { await act { try await $0.cancelPipeline(project: project.id, id: p.id) } }
                        }.tint(.red)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if loading && pipelines.isEmpty { ProgressView() }
            else if !loading && pipelines.isEmpty && error == nil {
                ContentUnavailableView("No pipelines", systemImage: "gearshape.2")
            }
        }
        .navigationTitle(project.name)
        .toolbar {
            Menu {
                Picker("Status", selection: $statusFilter) {
                    Text("All").tag(String?.none)
                    ForEach(filters, id: \.self) { Text($0.capitalized).tag(String?.some($0)) }
                }
            } label: {
                Image(systemName: statusFilter == nil
                      ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
        }
        .refreshable { await fetch() }
        .task(id: statusFilter) { await fetch() }
    }

    private func act(_ work: (GitLabClient) async throws -> Void) async {
        guard let client = session.client else { return }
        do { try await work(client); await fetch() }
        catch { self.error = error.localizedDescription }
    }

    private func fetch() async {
        guard let client = session.client else { return }
        loading = true; defer { loading = false }
        do { pipelines = try await client.pipelines(project: project.id, status: statusFilter); error = nil }
        catch is CancellationError {}
        catch let e as URLError where e.code == .cancelled {}
        catch { self.error = error.localizedDescription }
    }
}

struct PipelineRow: View {
    let pipeline: Pipeline

    var body: some View {
        HStack {
            StatusBadge(status: pipeline.status).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("#\(pipeline.id) · \(pipeline.ref ?? "—")").font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    if let sha = pipeline.sha { Text(sha.prefix(8)).monospaced() }
                    if let src = pipeline.source { Text(src.replacingOccurrences(of: "_", with: " ")) }
                    if let c = pipeline.createdAt { Text(c, format: .relative(presentation: .named)) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
