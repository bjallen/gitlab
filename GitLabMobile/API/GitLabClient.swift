import Foundation

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { status == 0 ? message : "\(message) (HTTP \(status))" }
}

struct GitLabClient: Sendable {
    let baseURL: String   // e.g. https://gitlab.com (no trailing slash)
    let token: String

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Bad date \(s)"))
        }
        return d
    }()

    // MARK: Transport

    private func request(_ method: String, _ path: String, _ query: [String: String]) async throws -> Data {
        guard var comps = URLComponents(string: baseURL + "/api/v4" + path) else {
            throw APIError(status: 0, message: "Invalid URL")
        }
        if !query.isEmpty {
            comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw APIError(status: 0, message: "Invalid URL") }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, message: Self.errorMessage(from: data) ?? "Request failed")
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let value = obj["message"] ?? obj["error"]
        if let s = value as? String { return s }
        if let v = value, JSONSerialization.isValidJSONObject(v),
           let d = try? JSONSerialization.data(withJSONObject: v),
           let s = String(data: d, encoding: .utf8) { return s }
        return nil
    }

    private func call<T: Decodable>(_ method: String, _ path: String,
                                    _ query: [String: String] = [:]) async throws -> T {
        let data = try await request(method, path, query)
        return try Self.decoder.decode(T.self, from: data)
    }

    // MARK: Endpoints

    func currentUser() async throws -> User { try await call("GET", "/user") }

    func projects(search: String = "") async throws -> [Project] {
        var q = ["membership": "true", "simple": "true", "order_by": "last_activity_at",
                 "per_page": "50", "archived": "false"]
        if !search.isEmpty { q["search"] = search }
        return try await call("GET", "/projects", q)
    }

    func mergeRequests(scope: MRScope, userId: Int) async throws -> [MergeRequest] {
        var q = ["state": "opened", "per_page": "50", "order_by": "updated_at", "sort": "desc"]
        switch scope {
        case .review: q["reviewer_id"] = String(userId); q["scope"] = "all"
        case .assigned: q["scope"] = "assigned_to_me"
        case .mine: q["scope"] = "created_by_me"
        }
        return try await call("GET", "/merge_requests", q)
    }

    func mergeRequest(project: Int, iid: Int) async throws -> MergeRequest {
        try await call("GET", "/projects/\(project)/merge_requests/\(iid)")
    }

    func approvals(project: Int, iid: Int) async throws -> Approvals {
        try await call("GET", "/projects/\(project)/merge_requests/\(iid)/approvals")
    }

    func approve(project: Int, iid: Int, sha: String?) async throws {
        var q: [String: String] = [:]
        if let sha { q["sha"] = sha }
        let _: Approvals = try await call("POST", "/projects/\(project)/merge_requests/\(iid)/approve", q)
    }

    func unapprove(project: Int, iid: Int) async throws {
        _ = try await request("POST", "/projects/\(project)/merge_requests/\(iid)/unapprove", [:])
    }

    func merge(project: Int, iid: Int, sha: String?, whenPipelineSucceeds: Bool,
               squash: Bool, removeSourceBranch: Bool) async throws {
        var q = ["merge_when_pipeline_succeeds": String(whenPipelineSucceeds),
                 "squash": String(squash),
                 "should_remove_source_branch": String(removeSourceBranch)]
        if let sha { q["sha"] = sha }   // guards against merging a commit nobody reviewed
        let _: MergeRequest = try await call("PUT", "/projects/\(project)/merge_requests/\(iid)/merge", q)
    }

    func pipelines(project: Int, status: String? = nil) async throws -> [Pipeline] {
        var q = ["per_page": "30", "order_by": "id", "sort": "desc"]
        if let status { q["status"] = status }
        let list: [Pipeline] = try await call("GET", "/projects/\(project)/pipelines", q)
        return list.map { var p = $0; p.projectId = p.projectId ?? project; return p }
    }

    func pipeline(project: Int, id: Int) async throws -> Pipeline {
        try await call("GET", "/projects/\(project)/pipelines/\(id)")
    }

    func jobs(project: Int, pipeline: Int) async throws -> [Job] {
        try await call("GET", "/projects/\(project)/pipelines/\(pipeline)/jobs", ["per_page": "100"])
    }

    func retryPipeline(project: Int, id: Int) async throws {
        let _: Pipeline = try await call("POST", "/projects/\(project)/pipelines/\(id)/retry")
    }

    func cancelPipeline(project: Int, id: Int) async throws {
        let _: Pipeline = try await call("POST", "/projects/\(project)/pipelines/\(id)/cancel")
    }

    func retryJob(project: Int, id: Int) async throws {
        let _: Job = try await call("POST", "/projects/\(project)/jobs/\(id)/retry")
    }

    func playJob(project: Int, id: Int) async throws {
        let _: Job = try await call("POST", "/projects/\(project)/jobs/\(id)/play")
    }

    func cancelJob(project: Int, id: Int) async throws {
        let _: Job = try await call("POST", "/projects/\(project)/jobs/\(id)/cancel")
    }
}

enum MRScope: String, CaseIterable, Identifiable {
    case review = "Review", assigned = "Assigned", mine = "Mine"
    var id: String { rawValue }
}
