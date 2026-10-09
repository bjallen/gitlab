import SwiftUI

struct PipelineDetailView: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL

    let projectId: Int
    let pipelineId: Int

    @State private var pipeline: Pipeline?
    @State private var jobs: [Job] = []
    @State private var busy = false
    @State private var error: String?
    @State private var confirmAdvance = false

    private struct Stage: Identifiable { let name: String; var jobs: [Job]; var id: String { name } }

    /// Stages in execution order (GitLab returns jobs newest-first, so order by lowest job id).
    private var stages: [Stage] {
        var order: [String] = []
        var byName: [String: [Job]] = [:]
        for j in jobs.sorted(by: { $0.id < $1.id }) {
            if byName[j.stage] == nil { order.append(j.stage) }
            byName[j.stage, default: []].append(j)
        }
        return order.map { Stage(name: $0, jobs: byName[$0]!) }
    }

    /// The first stage that is waiting on a manual job — what "advance" should kick off.
    private var nextManualStage: Stage? {
        stages.first { $0.jobs.contains { $0.status == "manual" } }
    }

    private var isActive: Bool {
        guard let s = pipeline?.status else { return true }
        return ["running", "pending", "created", "preparing", "waiting_for_resource", "scheduled"].contains(s)
    }

    var body: some View {
        List {
            if let p = pipeline {
                Section {
                    HStack {
                        StatusBadge(status: p.status).font(.title2)
                        VStack(alignment: .leading) {
                            Text(p.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.headline)
                            Text("\(p.ref ?? "—") · \(p.sha.map { String($0.prefix(8)) } ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let d = p.duration { LabeledContent("Duration", value: Self.format(d)) }
                    if let u = p.user { LabeledContent("Triggered by", value: "@\(u.username)") }
                }
            }

            if let error { Section { ErrorBanner(message: error) } }

            if let stage = nextManualStage {
                Section {
                    Button("Advance: run manual jobs in “\(stage.name)”", systemImage: "forward.fill") {
                        confirmAdvance = true
                    }
                }
            }

            ForEach(stages) { stage in
                Section(stage.name) {
                    ForEach(stage.jobs) { jobRow($0) }
                }
            }
        }
        .navigationTitle("Pipeline #\(pipelineId)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Retry failed jobs", systemImage: "arrow.clockwise") {
                    Task { await act { try await $0.retryPipeline(project: projectId, id: pipelineId) } }
                }
                if isActive {
                    Button("Cancel pipeline", systemImage: "stop", role: .destructive) {
                        Task { await act { try await $0.cancelPipeline(project: projectId, id: pipelineId) } }
                    }
                }
                if let url = pipeline?.webUrl {
                    Button("Open in GitLab", systemImage: "safari") { openURL(url) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .disabled(busy)
        .refreshable { await load() }
        .task {
            // Poll while the pipeline is still moving; stops when the view disappears.
            repeat {
                await load()
                if !isActive && nextManualStage == nil { try? await Task.sleep(for: .seconds(30)) }
                else { try? await Task.sleep(for: .seconds(5)) }
            } while !Task.isCancelled
        }
        .confirmationDialog("Run manual jobs?", isPresented: $confirmAdvance, titleVisibility: .visible) {
            Button("Run \(nextManualStage?.jobs.filter { $0.status == "manual" }.count ?? 0) job(s)") {
                guard let stage = nextManualStage else { return }
                let manual = stage.jobs.filter { $0.status == "manual" }
                Task { await act { c in
                    for j in manual { try await c.playJob(project: projectId, id: j.id) }
                } }
            }
        } message: {
            Text(nextManualStage?.jobs.filter { $0.status == "manual" }.map(\.name).joined(separator: ", ") ?? "")
        }
    }

    private func jobRow(_ j: Job) -> some View {
        HStack {
            StatusBadge(status: j.status)
            VStack(alignment: .leading) {
                Text(j.name)
                if j.allowFailure == true && j.status == "failed" {
                    Text("allowed to fail").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let d = j.duration { Text(Self.format(d)).font(.caption).foregroundStyle(.secondary) }
            jobMenu(j)
        }
        .swipeActions(edge: .trailing) {
            if j.status == "manual" {
                Button("Play", systemImage: "play.fill") {
                    Task { await act { try await $0.playJob(project: projectId, id: j.id) } }
                }.tint(.indigo)
            } else if ["running", "pending"].contains(j.status) {
                Button("Cancel", systemImage: "stop") {
                    Task { await act { try await $0.cancelJob(project: projectId, id: j.id) } }
                }.tint(.red)
            } else if ["success", "failed", "canceled"].contains(j.status) {
                Button("Retry", systemImage: "arrow.clockwise") {
                    Task { await act { try await $0.retryJob(project: projectId, id: j.id) } }
                }.tint(.blue)
            }
        }
    }

    @ViewBuilder private func jobMenu(_ j: Job) -> some View {
        if let url = j.webUrl {
            Button { openURL(url) } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.borderless)
        }
    }

    private func act(_ work: (GitLabClient) async throws -> Void) async {
        guard let client = session.client else { return }
        await perform(busy: $busy, error: $error) {
            try await work(client)
            try await Task.sleep(for: .milliseconds(500))   // let GitLab update job states
            await load()
        }
    }

    private func load() async {
        guard let client = session.client else { return }
        do {
            async let p = client.pipeline(project: projectId, id: pipelineId)
            async let j = client.jobs(project: projectId, pipeline: pipelineId)
            pipeline = try await p
            jobs = try await j
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.error = error.localizedDescription }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds)
        return s >= 3600 ? "\(s / 3600)h \(s % 3600 / 60)m" : s >= 60 ? "\(s / 60)m \(s % 60)s" : "\(s)s"
    }
}
