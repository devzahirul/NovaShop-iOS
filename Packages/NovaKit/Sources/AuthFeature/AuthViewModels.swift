import Domain
import Foundation
import NovaCore
import Observation

@MainActor
@Observable
public final class SignInViewModel {
    public enum Field: Hashable { case email, password }

    public var email = ""
    public var password = ""
    public private(set) var fieldErrors: [Field: String] = [:]
    public private(set) var error: UserFacingError?
    public private(set) var isSubmitting = false

    @ObservationIgnored private let session: SessionStore

    public init(session: SessionStore) {
        self.session = session
    }

    public func signIn() async -> Bool {
        var errors: [Field: String] = [:]
        errors[.email] = Validation.email(email)?.message
        errors[.password] = Validation.password(password)?.message
        fieldErrors = errors
        guard errors.isEmpty else { return false }
        return await submit { try await self.session.signIn(email: self.email, password: self.password) }
    }

    public func signIn(with provider: SocialProvider) async -> Bool {
        await submit { try await self.session.signIn(with: provider) }
    }

    private func submit(_ operation: @escaping () async throws -> Void) async -> Bool {
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        do {
            try await operation()
            return true
        } catch {
            self.error = error.userFacing
            return false
        }
    }
}

@MainActor
@Observable
public final class SignUpViewModel {
    public enum Field: Hashable { case name, email, password }

    public var name = ""
    public var email = ""
    public var password = ""
    public var acceptedTerms = false
    public private(set) var fieldErrors: [Field: String] = [:]
    public private(set) var error: UserFacingError?
    public private(set) var isSubmitting = false

    @ObservationIgnored private let session: SessionStore

    public init(session: SessionStore) {
        self.session = session
    }

    /// Live strength hint shown under the password field.
    public var passwordStrength: Double {
        var score = min(Double(password.count) / 12, 0.5)
        if password.contains(where: \.isNumber) {
            score += 0.2
        }
        if password.contains(where: \.isUppercase) {
            score += 0.15
        }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) {
            score += 0.15
        }
        return min(score, 1)
    }

    public var canSubmit: Bool {
        acceptedTerms && !isSubmitting
    }

    public func signUp() async -> Bool {
        var errors: [Field: String] = [:]
        errors[.name] = Validation.required(name, field: "Full name")?.message
        errors[.email] = Validation.email(email)?.message
        errors[.password] = Validation.password(password)?.message
        fieldErrors = errors
        guard errors.isEmpty else { return false }

        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        do {
            try await session.signUp(name: name.trimmingCharacters(in: .whitespaces), email: email, password: password)
            return true
        } catch {
            self.error = error.userFacing
            return false
        }
    }
}

@MainActor
@Observable
public final class StylePreferencesViewModel {
    public var selected: Set<StylePreference> = []
    public private(set) var isSaving = false
    @ObservationIgnored private let session: SessionStore

    public init(session: SessionStore) {
        self.session = session
        selected = session.user?.stylePreferences ?? []
    }

    public func toggle(_ preference: StylePreference) {
        selected.formSymmetricDifference([preference])
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        try? await session.updatePreferences(selected)
    }
}
