import Foundation
import Observation
import Security

enum Keychain {
    private static let service = "GitLabMobile"
    private static let account = "personal-access-token"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ token: String) {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}

@Observable
@MainActor
final class Session {
    private static let baseURLKey = "gitlab.baseURL"

    var baseURL: String
    private(set) var token: String?
    private(set) var me: User?
    private(set) var isRestoring = false
    var hasStoredToken: Bool { token != nil }

    /// Usernames of service accounts (e.g. an AI agent) whose MRs appear under "Mine".
    var extraAuthors: [String] = UserDefaults.standard.stringArray(forKey: "gitlab.extraAuthors") ?? [] {
        didSet { UserDefaults.standard.set(extraAuthors, forKey: "gitlab.extraAuthors") }
    }

    var isSignedIn: Bool { client != nil && me != nil }

    var client: GitLabClient? {
        guard let token, !baseURL.isEmpty else { return nil }
        return GitLabClient(baseURL: baseURL, token: token)
    }

    init() {
        baseURL = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? "https://gitlab.com"
        token = Keychain.load()
        if token != nil {
            isRestoring = true
            Task { await restore() }
        }
    }

    /// Validates the stored token. A 401 signs out; any other failure (offline, server down)
    /// keeps the token so the user can retry instead of being sent back to the login form.
    func restore() async {
        guard let client else { return }
        isRestoring = true
        defer { isRestoring = false }
        do { me = try await client.currentUser() }
        catch let e as APIError where e.status == 401 { signOut() }
        catch {}
    }

    func signIn(baseURL rawURL: String, token rawToken: String) async throws {
        var url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        if !url.contains("://") { url = "https://" + url }
        let tok = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = try await GitLabClient(baseURL: url, token: tok).currentUser()
        baseURL = url
        token = tok
        me = user
        UserDefaults.standard.set(url, forKey: Self.baseURLKey)
        Keychain.save(tok)
    }

    func signOut() {
        Keychain.delete()
        token = nil
        me = nil
    }
}
