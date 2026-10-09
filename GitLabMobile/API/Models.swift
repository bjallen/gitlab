import Foundation

struct User: Codable, Identifiable, Hashable {
    let id: Int
    let username: String
    let name: String
    var avatarUrl: URL?
}

struct Project: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let nameWithNamespace: String
    let pathWithNamespace: String
}

struct Pipeline: Codable, Identifiable, Hashable {
    let id: Int
    var projectId: Int?
    var status: String
    var ref: String?
    var sha: String?
    var source: String?
    var webUrl: URL?
    var createdAt: Date?
    var duration: Double?
    var user: User?
}

struct Job: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var stage: String
    var status: String
    var allowFailure: Bool?
    var duration: Double?
    var webUrl: URL?
}

struct MergeRequest: Codable, Identifiable, Hashable {
    struct References: Codable, Hashable { var full: String? }

    let id: Int
    let iid: Int
    let projectId: Int
    var title: String
    var description: String?
    var state: String
    var draft: Bool?
    var author: User?
    var sourceBranch: String
    var targetBranch: String
    var webUrl: URL?
    var updatedAt: Date?
    var sha: String?
    var detailedMergeStatus: String?
    var hasConflicts: Bool?
    var squash: Bool?
    var shouldRemoveSourceBranch: Bool?
    var forceRemoveSourceBranch: Bool?
    var headPipeline: Pipeline?
    var pipeline: Pipeline?
    var references: References?

    var currentPipeline: Pipeline? { headPipeline ?? pipeline }
    var isOpen: Bool { state == "opened" }
    var isDraft: Bool { draft ?? false }
    var fullReference: String { references?.full ?? "!\(iid)" }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Approvals: Codable {
    struct Approver: Codable { let user: User }
    var approved: Bool?
    var approvalsRequired: Int?
    var approvalsLeft: Int?
    var approvedBy: [Approver]?
    var userHasApproved: Bool?
    var userCanApprove: Bool?
}

/// Navigation value for pipeline detail screens.
struct PipelineRef: Hashable {
    let projectId: Int
    let pipelineId: Int
}
