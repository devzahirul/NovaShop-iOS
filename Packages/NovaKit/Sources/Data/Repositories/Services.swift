import CryptoKit
import Domain
import Foundation
import Networking
import NovaCore

// MARK: - Auth

/// Local auth adapter standing in for a real identity provider. It implements the full contract
/// (validation, duplicate accounts, session restore from the Keychain, account deletion) so the
/// UI and error handling are production-shaped.
public actor LocalAuthService: AuthService {
    private struct Account: Codable {
        var user: User
        let passwordHash: String
    }

    private let secureStorage: any SecureStorage
    private let accounts: any Persisting<[String: Account]>
    private let latency: Duration
    private let sessionKey = "session.user"

    public nonisolated var supportsSocialSignIn: Bool {
        true
    }

    public init(secureStorage: any SecureStorage, accountsDirectory: URL? = nil, inMemory: Bool = false, latency: Duration) {
        self.secureStorage = secureStorage
        self.latency = latency
        accounts = inMemory
            ? InMemoryStore<[String: Account]>()
            : FileStore<[String: Account]>(filename: "accounts", directory: accountsDirectory)
    }

    public func restoreSession() async -> User? {
        guard let data = secureStorage.read(sessionKey) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    public func signIn(email: String, password: String) async throws -> User {
        try await simulateNetwork()
        let key = email.lowercased()
        let all = await accounts.load() ?? [:]
        guard let account = all[key], account.passwordHash == Self.hash(password) else {
            // Demo convenience: any well-formed credentials create a session so reviewers aren't blocked.
            guard Validation.email(email) == nil, Validation.password(password) == nil else { throw AuthError.invalidCredentials }
            if all[key] != nil {
                throw AuthError.invalidCredentials
            }
            return try await signUp(name: Self.displayName(from: email), email: email, password: password)
        }
        try persistSession(account.user)
        return account.user
    }

    public func signUp(name: String, email: String, password: String) async throws -> User {
        try await simulateNetwork()
        let key = email.lowercased()
        var all = await accounts.load() ?? [:]
        guard all[key] == nil else { throw AuthError.emailAlreadyInUse }
        let user = User(name: name, email: email)
        all[key] = Account(user: user, passwordHash: Self.hash(password))
        try await accounts.save(all)
        try persistSession(user)
        return user
    }

    public func signIn(with provider: SocialProvider) async throws -> User {
        try await simulateNetwork()
        let user = User(name: "Olivia Chen", email: "olivia.\(provider.rawValue)@privaterelay.example")
        try persistSession(user)
        return user
    }

    public func update(_ user: User) async throws -> User {
        var all = await accounts.load() ?? [:]
        if var account = all[user.email.lowercased()] {
            account.user = user
            all[user.email.lowercased()] = account
            try await accounts.save(all)
        }
        try persistSession(user)
        return user
    }

    public func signOut() async {
        secureStorage.delete(sessionKey)
    }

    public func deleteAccount() async throws {
        try await simulateNetwork()
        if let data = secureStorage.read(sessionKey), let user = try? JSONDecoder().decode(User.self, from: data) {
            var all = await accounts.load() ?? [:]
            all[user.email.lowercased()] = nil
            try await accounts.save(all)
        }
        secureStorage.delete(sessionKey)
    }

    private func persistSession(_ user: User) throws {
        try secureStorage.write(JSONEncoder().encode(user), for: sessionKey)
    }

    private func simulateNetwork() async throws {
        if latency > .zero {
            try await Task.sleep(for: latency)
        }
    }

    /// Salted SHA-256 for the local demo store. A production client never persists passwords at all —
    /// the identity provider does, with a real KDF (Argon2 / scrypt).
    private static func hash(_ password: String) -> String {
        SHA256.hash(data: Data("novashop.local.\(password)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func displayName(from email: String) -> String {
        email.split(separator: "@").first.map { $0.replacingOccurrences(of: ".", with: " ").capitalized } ?? "Guest"
    }
}

// MARK: - Coupons

public struct LocalCouponService: CouponService {
    private let latency: Duration

    public static let catalog: [String: Coupon] = [
        "SUMMER20": Coupon(code: "SUMMER20", kind: .percentage(0.2)),
        "WELCOME10": Coupon(code: "WELCOME10", kind: .percentage(0.1)),
        "NOVA25": Coupon(code: "NOVA25", kind: .fixedAmount(25), minimumSubtotal: 150),
    ]

    public init(latency: Duration) {
        self.latency = latency
    }

    public func validate(code: String, subtotal: Decimal) async throws -> Coupon {
        if latency > .zero {
            try await Task.sleep(for: latency)
        }
        let normalized = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard let coupon = Self.catalog[normalized] else { throw CouponError.notFound }
        guard subtotal >= coupon.minimumSubtotal else { throw CouponError.minimumNotMet(coupon.minimumSubtotal) }
        return coupon
    }
}

// MARK: - Orders

public actor LocalOrderService: OrderService {
    private let store: any Persisting<[Order]>
    private let processingTime: Duration
    private let now: @Sendable () -> Date

    public init(store: any Persisting<[Order]>, processingTime: Duration, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.processingTime = processingTime
        self.now = now
    }

    public func placeOrder(_ draft: OrderDraft) async throws -> Order {
        if processingTime > .zero {
            try await Task.sleep(for: processingTime)
        }
        // Magic test card that always declines — exercises the failure path end to end.
        if case let .card(_, last4, _, _) = draft.payment.kind, last4 == "0002" {
            throw PaymentError.declined
        }

        let order = Order(
            number: "NS\(Int.random(in: 100_000 ... 999_999))",
            items: draft.items,
            address: draft.address,
            payment: draft.payment,
            shipping: draft.shipping,
            pricing: PricingCalculator.breakdown(items: draft.items, coupon: draft.coupon, shipping: draft.shipping),
            placedAt: now(),
            status: .processing
        )
        var all = await store.load() ?? []
        all.insert(order, at: 0)
        try await store.save(all)
        return order
    }

    public func orders() async throws -> [Order] {
        await store.load() ?? []
    }
}

// MARK: - Profile

public actor LocalProfileRepository: ProfileRepository {
    private let addressStore: any Persisting<[Address]>
    private let paymentStore: any Persisting<[PaymentMethod]>

    public init(addressStore: any Persisting<[Address]>, paymentStore: any Persisting<[PaymentMethod]>) {
        self.addressStore = addressStore
        self.paymentStore = paymentStore
    }

    public func addresses() async -> [Address] {
        await addressStore.load() ?? []
    }

    public func save(_ address: Address) async throws -> [Address] {
        var all = await addresses()
        var address = address
        if all.isEmpty {
            address.isDefault = true
        }
        if address.isDefault {
            for index in all.indices {
                all[index].isDefault = false
            }
        }
        if let index = all.firstIndex(where: { $0.id == address.id }) {
            all[index] = address
        } else {
            all.append(address)
        }
        try await addressStore.save(all)
        return all
    }

    public func deleteAddress(id: Address.ID) async throws -> [Address] {
        var all = await addresses()
        let wasDefault = all.first { $0.id == id }?.isDefault ?? false
        all.removeAll { $0.id == id }
        if wasDefault, !all.isEmpty {
            all[0].isDefault = true
        }
        try await addressStore.save(all)
        return all
    }

    public func paymentMethods() async -> [PaymentMethod] {
        await paymentStore.load() ?? []
    }

    public func save(_ method: PaymentMethod) async throws -> [PaymentMethod] {
        var all = await paymentMethods()
        all.removeAll { $0.id == method.id }
        all.insert(method, at: 0)
        try await paymentStore.save(all)
        return all
    }
}

// MARK: - Notifications

public struct RemoteNotificationRepository: NotificationRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func notifications() async throws -> [AppNotification] {
        try await client.send(API.notifications).map { $0.toDomain() }
    }
}
