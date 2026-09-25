import Domain
import Foundation
import Networking
import NovaCore

/// Supabase project coordinates. The publishable (anon) key is *designed* to ship in apps: it only
/// grants what Row Level Security allows. The secret/service key never leaves the server.
public struct SupabaseConfig: Sendable, Equatable {
    public let url: URL
    public let publishableKey: String

    public init(url: URL, publishableKey: String) {
        self.url = url
        self.publishableKey = publishableKey
    }
}

/// A signed-in session, persisted in the Keychain.
public struct AuthSession: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var user: User
}

/// Owns the session: Keychain persistence, proactive refresh, and **single-flight** refresh —
/// ten requests that hit a 401 at once cause exactly one refresh call, and all ten retry with the
/// new token. A permanently failed refresh (revoked / expired refresh token) ends the session and
/// is published on `expirations` so the UI can ask the user to sign in again.
public actor SessionVault {
    private static let keychainKey = "supabase.session"

    private let storage: any SecureStorage
    private let config: SupabaseConfig
    private let authClient: APIClient
    private let refreshLeeway: TimeInterval
    private var session: AuthSession?
    private var isLoaded = false
    private var refreshTask: Task<AuthSession, any Error>?
    private let expirationStream: AsyncStream<Void>
    private let expirationContinuation: AsyncStream<Void>.Continuation

    public init(config: SupabaseConfig, storage: any SecureStorage, transport: any HTTPTransport, refreshLeeway: TimeInterval = 60) {
        self.config = config
        self.storage = storage
        self.refreshLeeway = refreshLeeway
        authClient = APIClient(baseURL: config.url, transport: transport, retryPolicy: RetryPolicy(maxAttempts: 2))
        (expirationStream, expirationContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    /// Emits when the server revokes the session.
    public nonisolated var expirations: AsyncStream<Void> {
        expirationStream
    }

    public func current() -> AuthSession? {
        loadIfNeeded()
        return session
    }

    public func store(_ newSession: AuthSession) {
        loadIfNeeded()
        session = newSession
        if let data = try? JSONEncoder().encode(newSession) {
            try? storage.write(data, for: Self.keychainKey)
        }
    }

    public func clear() {
        session = nil
        refreshTask?.cancel()
        refreshTask = nil
        storage.delete(Self.keychainKey)
    }

    /// A token valid for at least `refreshLeeway` seconds, refreshing first if needed.
    /// `nil` when signed out (requests then go out with the publishable key only).
    public func validAccessToken() async -> String? {
        loadIfNeeded()
        guard let session else { return nil }
        if session.expiresAt.timeIntervalSinceNow > refreshLeeway {
            return session.accessToken
        }
        return try? await refresh().accessToken
    }

    /// Called after a 401. If someone already refreshed since `failedToken` was issued, just reuse it.
    public func recover(fromRejectedToken failedToken: String?) async -> Bool {
        loadIfNeeded()
        guard let session else { return false }
        if let failedToken, session.accessToken != failedToken {
            return true
        }
        return await (try? refresh()) != nil
    }

    // MARK: Refresh (single-flight)

    private func refresh() async throws -> AuthSession {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let current = session else { throw AuthError.sessionExpired }
        let client = authClient
        let key = config.publishableKey
        let task = Task<AuthSession, any Error> {
            let endpoint = try Endpoint<SessionDTO>.json(
                path: "auth/v1/token",
                method: .post,
                body: ["refresh_token": current.refreshToken],
                queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                headers: ["apikey": key],
                isRetrySafe: true
            )
            return try await client.send(endpoint).toSession(fallbackUser: current.user)
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let fresh = try await task.value
            store(fresh)
            Log.network.info("Access token refreshed")
            return fresh
        } catch let error as APIError where error.isClientRejection || error.status == 401 {
            // The refresh token itself was rejected: this session is over.
            Log.network.notice("Session revoked: \(String(describing: error), privacy: .public)")
            clear()
            expirationContinuation.yield()
            throw AuthError.sessionExpired
        }
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        if let data = storage.read(Self.keychainKey) {
            session = try? JSONDecoder().decode(AuthSession.self, from: data)
        }
    }
}

/// Adds Supabase credentials to every request and recovers from 401s via the vault.
public struct SupabaseAuthorizer: RequestAuthorizing {
    private let vault: SessionVault
    private let publishableKey: String

    public init(vault: SessionVault, publishableKey: String) {
        self.vault = vault
        self.publishableKey = publishableKey
    }

    public func authorize(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        let token = await vault.validAccessToken() ?? publishableKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    public func refreshAfterUnauthorized(_ request: URLRequest) async -> Bool {
        let failedToken = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
        guard failedToken != publishableKey else { return false }
        return await vault.recover(fromRejectedToken: failedToken)
    }
}

// MARK: - Auth service

/// `AuthService` over Supabase Auth (GoTrue) REST. Email + password; Sign in with Apple / Google
/// need provider configuration in the Supabase dashboard (and a paid Apple team), so they report
/// `supportsSocialSignIn = false` and the UI hides them instead of offering a broken button.
public struct SupabaseAuthService: AuthService {
    private let config: SupabaseConfig
    private let vault: SessionVault
    private let authClient: APIClient
    private let api: APIClient

    public init(config: SupabaseConfig, vault: SessionVault, transport: any HTTPTransport, api: APIClient) {
        self.config = config
        self.vault = vault
        authClient = APIClient(baseURL: config.url, transport: transport, retryPolicy: .none)
        self.api = api
    }

    public nonisolated var supportsSocialSignIn: Bool {
        false
    }

    public func restoreSession() async -> User? {
        // Local only — launch never waits on the network. The token is refreshed lazily on first use.
        await vault.current()?.user
    }

    public func signIn(email: String, password: String) async throws -> User {
        let endpoint = try Endpoint<SessionDTO>.json(
            path: "auth/v1/token",
            method: .post,
            body: ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "password": password],
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            headers: ["apikey": config.publishableKey]
        )
        let session = try await Self.mapAuthErrors { try await authClient.send(endpoint).toSession() }
        await vault.store(session)
        return await (try? loadProfile(for: session.user)) ?? session.user
    }

    public func signUp(name: String, email: String, password: String) async throws -> User {
        struct Body: Encodable {
            let email: String
            let password: String
            let data: [String: String]
        }
        let normalizedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        let endpoint = try Endpoint<SignUpResponseDTO>.json(
            path: "auth/v1/signup",
            method: .post,
            body: Body(email: normalizedEmail, password: password, data: ["full_name": name]),
            headers: ["apikey": config.publishableKey]
        )
        let response = try await Self.mapAuthErrors { try await authClient.send(endpoint) }
        guard let session = response.session else {
            // Project has "Confirm email" on: account created, no session until the link is opened.
            throw AuthError.confirmationRequired(email: normalizedEmail)
        }
        await vault.store(session)
        return session.user
    }

    public func signIn(with _: SocialProvider) async throws -> User {
        throw AuthError.unsupportedProvider
    }

    public func update(_ user: User) async throws -> User {
        struct Patch: Encodable {
            let fullName: String
            let stylePreferences: [String]
        }
        let endpoint = try Endpoint<EmptyResponse>.json(
            path: "rest/v1/profiles",
            method: .patch,
            body: Patch(fullName: user.name, stylePreferences: user.stylePreferences.map(\.rawValue).sorted()),
            queryItems: [URLQueryItem(name: "id", value: "eq.\(user.id.uuidString.lowercased())")],
            headers: ["Prefer": "return=minimal"]
        )
        _ = try await api.send(endpoint)
        if var session = await vault.current() {
            session.user = user
            await vault.store(session)
        }
        return user
    }

    public func signOut() async {
        // Best effort: revoke server-side, but local sign-out must succeed even offline.
        _ = try? await api.send(Endpoint<EmptyResponse>(path: "auth/v1/logout", method: .post))
        await vault.clear()
    }

    public func deleteAccount() async throws {
        _ = try await api.send(Endpoint<EmptyResponse>(path: "rest/v1/rpc/delete_my_account", method: .post, body: Data("{}".utf8)))
        await vault.clear()
    }

    private func loadProfile(for user: User) async throws -> User {
        struct ProfileDTO: Decodable {
            let fullName: String
            let stylePreferences: [String]
        }
        let endpoint = Endpoint<[ProfileDTO]>(
            path: "rest/v1/profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "full_name,style_preferences"),
                URLQueryItem(name: "id", value: "eq.\(user.id.uuidString.lowercased())"),
            ]
        )
        guard let profile = try await api.send(endpoint).first else { return user }
        var enriched = user
        if !profile.fullName.isEmpty {
            enriched.name = profile.fullName
        }
        enriched.stylePreferences = Set(profile.stylePreferences.compactMap(StylePreference.init(rawValue:)))
        if var session = await vault.current() {
            session.user = enriched
            await vault.store(session)
        }
        return enriched
    }

    /// GoTrue error codes → domain errors.
    static func mapAuthErrors<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as APIError {
            if case .offline = error {
                throw AuthError.network
            }
            if error.status == 429 {
                throw AuthError.rateLimited
            }
            guard case let .server(server) = error else { throw error }
            let code = server.code ?? ""
            let message = server.message ?? ""
            switch code {
            case "invalid_credentials", "invalid_grant": throw AuthError.invalidCredentials
            case "user_already_exists", "email_exists": throw AuthError.emailAlreadyInUse
            case "email_not_confirmed": throw AuthError.emailNotConfirmed
            case "weak_password": throw AuthError.weakPassword(message.isEmpty ? "Use a longer password." : message)
            case "over_request_rate_limit", "over_email_send_rate_limit": throw AuthError.rateLimited
            default:
                if message.localizedCaseInsensitiveContains("invalid login") {
                    throw AuthError.invalidCredentials
                }
                if message.localizedCaseInsensitiveContains("already registered") {
                    throw AuthError.emailAlreadyInUse
                }
                throw error
            }
        }
    }
}

// MARK: - DTOs

struct SessionDTO: Decodable, Sendable {
    struct UserDTO: Decodable, Sendable {
        struct Metadata: Decodable, Sendable {
            let fullName: String?
        }

        let id: UUID
        let email: String?
        let userMetadata: Metadata?

        func toDomain() -> User {
            let email = email ?? ""
            let fallbackName = email.split(separator: "@").first.map(String.init) ?? "NovaShop member"
            return User(id: id, name: userMetadata?.fullName ?? fallbackName, email: email)
        }
    }

    let accessToken: String
    let refreshToken: String
    let expiresIn: Double?
    let expiresAt: Double?
    let user: UserDTO?

    func toSession(fallbackUser: User? = nil) throws -> AuthSession {
        let expiry = expiresAt.map { Date(timeIntervalSince1970: $0) } ?? Date(timeIntervalSinceNow: expiresIn ?? 3600)
        guard let user = user?.toDomain() ?? fallbackUser else { throw APIError.decoding("SessionDTO.user") }
        var merged = user
        if let fallbackUser { // keep locally known profile fields across refreshes
            merged.name = fallbackUser.name
            merged.stylePreferences = fallbackUser.stylePreferences
        }
        return AuthSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiry, user: merged)
    }
}

/// Sign-up returns a session when email confirmation is off, or just the user when it's on.
struct SignUpResponseDTO: Decodable, Sendable {
    let session: AuthSession?

    init(from decoder: any Decoder) throws {
        session = try? SessionDTO(from: decoder).toSession()
    }
}
