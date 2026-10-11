import SwiftUI

struct MRDetailView: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State var mr: MergeRequest
    var onChange: () -> Void = {}

    @State private var approvals: Approvals?
    @State private var busy = false
    @State private var error: String?
    @State private var confirmMerge = false
    @State private var squash = false
    @State private var removeSource = true

    init(mr: MergeRequest, onChange: @escaping () -> Void = {}) {
        _mr = State(initialValue: mr)
        _squash = State(initialValue: mr.squash ?? false)
        _removeSource = State(initialValue: mr.shouldRemoveSourceBranch ?? mr.forceRemoveSourceBranch ?? true)
        self.onChange = onChange
    }

    private var pipelineRunning: Bool {
        guard let s = mr.currentPipeline?.status else { return false }
        return ["running", "pending", "created", "preparing", "waiting_for_resource"].contains(s)
    }

    /// Merge now, or queue auto-merge, depending on what GitLab says is blocking.
    private enum MergeMode { case now, whenPipelineSucceeds, blocked(String) }

    private var mergeMode: MergeMode {
        guard mr.isOpen else { return .blocked("Merge request is \(mr.state)") }
        switch mr.detailedMergeStatus {
        case "mergeable": return .now
        case "ci_still_running": return .whenPipelineSucceeds
        case "checking", "unchecked", "preparing": return .blocked("GitLab is still checking mergeability")
        case .some(let s): return .blocked(Self.describe(s))
        case nil: return pipelineRunning ? .whenPipelineSucceeds : .now
        }
    }

    static func describe(_ s: String) -> String {
        switch s {
        case "not_approved": "Needs approval"
        case "draft_status": "Marked as draft"
        case "discussions_not_resolved": "Unresolved discussions"
        case "ci_must_pass": "Pipeline must succeed"
        case "conflict": "Has merge conflicts"
        case "need_rebase": "Needs rebase"
        case "blocked_status": "Blocked by another MR"
        case "external_status_checks": "External status checks pending"
        case "requested_changes": "Changes requested"
        case "jira_association_missing": "Missing Jira association"
        case "not_open": "Not open"
        default: s.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var body: some View {
        List {
            Section {
                Text(mr.title).font(.title3.bold())
                LabeledContent("Project", value: mr.fullReference)
                LabeledContent("Branch", value: "\(mr.sourceBranch) → \(mr.targetBranch)")
                if let a = mr.author { LabeledContent("Author", value: "@\(a.username)") }
                LabeledContent("State", value: mr.state.capitalized)
                if let s = mr.detailedMergeStatus {
                    LabeledContent("Merge status", value: Self.describe(s))
                }
            }

            if let p = mr.currentPipeline {
                Section("Pipeline") {
                    NavigationLink(value: PipelineRef(projectId: mr.projectId, pipelineId: p.id)) {
                        HStack {
                            StatusBadge(status: p.status)
                            Text("#\(p.id)")
                            Spacer()
                            Text(p.status.replacingOccurrences(of: "_", with: " "))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let approvals {
                Section("Approvals") {
                    if let req = approvals.approvalsRequired, req > 0 {
                        LabeledContent("Required", value: "\(req - (approvals.approvalsLeft ?? 0)) of \(req)")
                    }
                    ForEach(approvals.approvedBy ?? [], id: \.user.id) { a in
                        Label(a.user.name, systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                    if (approvals.approvedBy ?? []).isEmpty { Text("No approvals yet").foregroundStyle(.secondary) }
                }
            }

            if let d = mr.description, !d.isEmpty {
                Section("Description") {
                    Text((try? AttributedString(markdown: d, options: .init(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(d))
                        .font(.callout)
                }
            }

            if let error { Section { ErrorBanner(message: error) } }

            if mr.isOpen {
                Section { actions }
            }

            if let url = mr.webUrl {
                Section { Button("Open in GitLab", systemImage: "safari") { openURL(url) } }
            }
        }
        .navigationTitle("!\(mr.iid)")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .refreshable { await reload() }
        .task { await reload() }
        .sheet(isPresented: $confirmMerge) { mergeSheet }
    }

    @ViewBuilder private var actions: some View {
        if approvals?.userHasApproved == true {
            Button("Revoke approval", systemImage: "hand.thumbsdown") {
                Task { await run { try await $0.unapprove(project: mr.projectId, iid: mr.iid) } }
            }
        } else {
            Button("Approve", systemImage: "checkmark.seal") {
                Task { await run { try await $0.approve(project: mr.projectId, iid: mr.iid, sha: mr.sha) } }
            }
            .disabled(approvals?.userCanApprove == false)
        }

        switch mergeMode {
        case .now:
            Button("Merge…", systemImage: "arrow.triangle.merge") { confirmMerge = true }
        case .whenPipelineSucceeds:
            Button("Merge when pipeline succeeds…", systemImage: "arrow.triangle.merge") { confirmMerge = true }
        case .blocked(let why):
            Label(why, systemImage: "lock").foregroundStyle(.secondary)
        }
    }

    private var mergeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Squash commits", isOn: $squash)
                    Toggle("Delete source branch", isOn: $removeSource)
                } footer: {
                    if case .whenPipelineSucceeds = mergeMode {
                        Text("The pipeline is still running. GitLab will merge automatically once it succeeds.")
                    }
                }
            }
            .navigationTitle("Merge !\(mr.iid)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { confirmMerge = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") {
                        confirmMerge = false
                        let auto: Bool = { if case .whenPipelineSucceeds = mergeMode { true } else { false } }()
                        Task {
                            await run {
                                try await $0.merge(project: mr.projectId, iid: mr.iid, sha: mr.sha,
                                                   whenPipelineSucceeds: auto, squash: squash,
                                                   removeSourceBranch: removeSource)
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func run(_ action: (GitLabClient) async throws -> Void) async {
        guard let client = session.client else { return }
        await perform(busy: $busy, error: $error) {
            try await action(client)
            try await refresh(client)
            onChange()
        }
    }

    private func reload() async {
        guard let client = session.client else { return }
        do { try await refresh(client); error = nil }
        catch is CancellationError {}
        catch let e as URLError where e.code == .cancelled {}
        catch { self.error = error.localizedDescription }
    }

    private func refresh(_ client: GitLabClient) async throws {
        // Merge status is computed lazily by GitLab, so the first fetch may say "checking".
        async let fresh = client.mergeRequest(project: mr.projectId, iid: mr.iid)
        async let appr = client.approvals(project: mr.projectId, iid: mr.iid)
        mr = try await fresh
        approvals = try? await appr
    }
}
