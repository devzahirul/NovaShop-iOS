import Foundation
import NovaCore
import Observation

public enum SessionState: Equatable, Sendable {
    /// Keychain lookup in flight. UI treats this as "guest" so launch is never blocked on auth.
    case restoring
    case signedOut
    case signedIn(User)
}

/// Authentication state. Browsing is always allowed as a guest (App Review guideline 5.1.1);
/// sign-in is requested only at the moment it is needed — checkout or the Account tab.
@MainActor
@Observable
public final class SessionStore {
    public private(set) var state: SessionState = .restoring
    @ObservationIgnored private let auth: any AuthService

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

    public func restore() async {
        guard state == .restoring else { return }
        state = await auth.restoreSession().map(SessionState.signedIn) ?? .signedOut
    }

    public func signIn(email: String, password: String) async throws {
        state = try await .signedIn(auth.signIn(email: email, password: password))
    }

    public func signUp(name: String, email: String, password: String) async throws {
        state = try await .signedIn(auth.signUp(name: name, email: email, password: password))
    }

    public func signIn(with provider: SocialProvider) async throws {
        state = try await .signedIn(auth.signIn(with: provider))
    }

    public func updatePreferences(_ preferences: Set<StylePreference>) async throws {
        guard var user else { return }
        user.stylePreferences = preferences
        state = try await .signedIn(auth.update(user))
    }

    public func signOut() async {
        await auth.signOut()
        state = .signedOut
    }

    public func deleteAccount() async throws {
        try await auth.deleteAccount()
        state = .signedOut
    }
}
