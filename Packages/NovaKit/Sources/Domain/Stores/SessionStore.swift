import Foundation
import NovaCore
import Observation

public enum SessionState: Equatable, Sendable {
    /// Keychain lookup in flight. UI treats this as "guest" so launch is never blocked on auth.
    case restoring
    case signedOut
    case signedIn(User)
}

public enum SessionEvent: Equatable, Sendable {
    case signedIn(User)
    case signedOut
}

/// Authentication state. Browsing is always allowed as a guest (App Review guideline 5.1.1);
/// sign-in is requested only at the moment it is needed — checkout or the Account tab.
@MainActor
@Observable
public final class SessionStore {
    public private(set) var state: SessionState = .restoring
    /// Set when the server revoked the session (refresh token expired); the UI shows it once.
    public private(set) var expiredNotice = false

    @ObservationIgnored private let auth: any AuthService
    @ObservationIgnored private var continuations: [UUID: AsyncStream<SessionEvent>.Continuation] = [:]

    public init(auth: any AuthService) {
        self.auth = auth
    }

    public var user: User? {
        if case let .signedIn(user) = state {
            return user
        }
        return nil
    }

    public var isSignedIn: Bool {
        user != nil
    }

    public var supportsSocialSignIn: Bool {
        auth.supportsSocialSignIn
    }

    /// Sign-in / sign-out transitions (not restores). Each call returns an independent stream.
    public func events() -> AsyncStream<SessionEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.continuations[id] = nil }
            }
        }
    }

    public func restore() async {
        guard state == .restoring else { return }
        state = await auth.restoreSession().map(SessionState.signedIn) ?? .signedOut
    }

    public func signIn(email: String, password: String) async throws {
        try await transition(to: auth.signIn(email: email, password: password))
    }

    public func signUp(name: String, email: String, password: String) async throws {
        try await transition(to: auth.signUp(name: name, email: email, password: password))
    }

    public func signIn(with provider: SocialProvider) async throws {
        try await transition(to: auth.signIn(with: provider))
    }

    public func updatePreferences(_ preferences: Set<StylePreference>) async throws {
        guard var user else { return }
        user.stylePreferences = preferences
        state = try await .signedIn(auth.update(user))
    }

    public func signOut() async {
        await auth.signOut()
        endSession()
    }

    public func deleteAccount() async throws {
        try await auth.deleteAccount()
        endSession()
    }

    /// The backend revoked the session (refresh failed permanently).
    public func handleSessionExpired() {
        guard isSignedIn else { return }
        expiredNotice = true
        endSession()
    }

    public func dismissExpiredNotice() {
        expiredNotice = false
    }

    private func transition(to user: User) {
        let wasSignedIn = isSignedIn
        state = .signedIn(user)
        expiredNotice = false
        if !wasSignedIn {
            emit(.signedIn(user))
        }
    }

    private func endSession() {
        let wasSignedIn = isSignedIn
        state = .signedOut
        if wasSignedIn {
            emit(.signedOut)
        }
    }

    private func emit(_ event: SessionEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }
}
