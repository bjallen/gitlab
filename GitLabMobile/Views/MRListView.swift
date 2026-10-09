import SwiftUI

struct MRListView: View {
    @Environment(Session.self) private var session
    @State private var scope: MRScope = .review
    @State private var mrs: [MergeRequest] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorBanner(message: error) }
                ForEach(mrs) { mr in
                    NavigationLink(value: mr) { MRRow(mr: mr) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if loading && mrs.isEmpty { ProgressView() }
                else if !loading && mrs.isEmpty && error == nil {
                    ContentUnavailableView("No open merge requests", systemImage: "tray")
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Scope", selection: $scope) {
                    ForEach(MRScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("Merge Requests")
            .navigationDestination(for: MergeRequest.self) { MRDetailView(mr: $0) { load() } }
            .navigationDestination(for: PipelineRef.self) {
                PipelineDetailView(projectId: $0.projectId, pipelineId: $0.pipelineId)
            }
            .refreshable { await fetch() }
            .task(id: scope) { mrs = []; await fetch() }
        }
    }

    private func load() { Task { await fetch() } }

    private func fetch() async {
        guard let client = session.client, let me = session.me else { return }
        loading = true; defer { loading = false }
        do {
            mrs = try await client.mergeRequests(scope: scope, userId: me.id)
            error = nil
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.error = error.localizedDescription }
    }
}

struct MRRow: View {
    let mr: MergeRequest

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if mr.isDraft {
                        Text("DRAFT").font(.caption2.bold())
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.gray.opacity(0.25), in: Capsule())
                    }
                    Text(mr.title).font(.headline).lineLimit(2)
                }
                Text(mr.fullReference).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("\(mr.sourceBranch) → \(mr.targetBranch)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let a = mr.author {
                    Text("@\(a.username)" + (mr.updatedAt.map { " · " + $0.formatted(.relative(presentation: .named)) } ?? ""))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if let p = mr.currentPipeline { StatusBadge(status: p.status).font(.title3) }
        }
        .padding(.vertical, 2)
    }
}
