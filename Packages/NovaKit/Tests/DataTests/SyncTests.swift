@testable import Data
import Domain
import Foundation
import Networking
import Testing
import TestSupport

/// Scriptable server for `SyncedCollection`. Records every call; can fail, reject ids, or pause
/// inside `upsert` so a test can mutate the collection *while a push is in flight*.
actor FakeRemote<Record: Identifiable & Sendable>: RemoteCollection where Record.ID: Sendable {
    private(set) var rows: [Record] = []
    private(set) var upsertBatches: [[Record]] = []
    private(set) var deletedIDs: [Record.ID] = []
    private var failure: APIError?
    private var rejectedIDs: Set<Record.ID> = []
    private var pauseNextUpsert: CheckedContinuation<Void, Never>?
    private var pauseRequested = false
    private var pausedSignal: CheckedContinuation<Void, Never>?

    init(rows: [Record] = []) {
        self.rows = rows
    }

    func fail(with error: APIError?) {
        failure = error
    }

    func reject(_ ids: Set<Record.ID>) {
        rejectedIDs = ids
    }

    func setRows(_ rows: [Record]) {
        self.rows = rows
    }

    /// Next upsert suspends until `resume()`; `waitUntilPaused()` returns once it has.
    func pauseNextUpsertCall() {
        pauseRequested = true
    }

    func waitUntilPaused() async {
        if pauseNextUpsert != nil {
            return
        }
        await withCheckedContinuation { pausedSignal = $0 }
    }

    func resume() {
        pauseNextUpsert?.resume()
        pauseNextUpsert = nil
    }

    func fetchAll() async throws -> [Record] {
        if let failure {
            throw failure
        }
        return rows
    }

    func upsert(_ records: [Record]) async throws {
        if let failure {
            throw failure
        }
        if records.contains(where: { rejectedIDs.contains($0.id) }) {
            throw APIError.server(ServerError(status: 409, code: "23503", message: "violates foreign key constraint"))
        }
        upsertBatches.append(records)
        if pauseRequested {
            pauseRequested = false
            await withCheckedContinuation { continuation in
                pauseNextUpsert = continuation
                pausedSignal?.resume()
                pausedSignal = nil
            }
        }
        for record in records {
            if let index = rows.firstIndex(where: { $0.id == record.id }) {
                rows[index] = record
            } else {
                rows.append(record)
            }
        }
    }

    func delete(_ ids: [Record.ID]) async throws {
        if let failure {
            throw failure
        }
        deletedIDs += ids
        rows.removeAll { ids.contains($0.id) }
    }
}

@Suite("SyncedCollection — local-first reconciliation")
struct SyncedCollectionTests {
    let dress = Product.fixture(id: "dress", price: 129)
    let coat = Product.fixture(id: "coat", price: 200)

    func line(_ product: Product, quantity: Int = 1) -> CartItem {
        CartItem(product: product, color: nil, size: .medium, quantity: quantity)
    }

    func makeCollection(_ remote: FakeRemote<CartItem>) -> SyncedCollection<CartItem, FakeRemote<CartItem>> {
        SyncedCollection(remote: remote, filename: "test", inMemory: true)
    }

    @Test("Ten offline edits coalesce into ONE upsert of the final value")
    func coalescing() async throws {
        let remote = FakeRemote<CartItem>()
        let collection = makeCollection(remote)
        for quantity in 1 ... 10 {
            await collection.save(line(dress, quantity: quantity))
        }
        _ = try await collection.sync()
        #expect(await remote.upsertBatches.count == 1)
        #expect(await remote.upsertBatches.first?.first?.quantity == 10)
        #expect(await collection.pendingIDs().isEmpty)
    }

    @Test("Offline: sync throws, nothing is lost, everything stays pending")
    func offlineKeepsPending() async throws {
        let remote = FakeRemote<CartItem>()
        await remote.fail(with: .offline)
        let collection = makeCollection(remote)
        await collection.save(line(dress))
        await #expect(throws: APIError.offline) { _ = try await collection.sync() }
        #expect(await collection.records().count == 1)
        #expect(await collection.pendingIDs().count == 1)

        await remote.fail(with: nil) // connectivity restored
        _ = try await collection.sync()
        #expect(await collection.pendingIDs().isEmpty)
        #expect(await remote.rows.count == 1)
    }

    @Test("Server is the source of truth for synced records; other devices' changes flow in")
    func serverWinsForSynced() async throws {
        let remote = FakeRemote<CartItem>()
        let collection = makeCollection(remote)
        await collection.save(line(dress, quantity: 1))
        _ = try await collection.sync()

        // Another device bumps the dress to 3 and adds a coat.
        await remote.setRows([line(dress, quantity: 3), line(coat)])
        let report = try await collection.sync()
        #expect(report.records.map(\.quantity) == [3, 1])
    }

    @Test("A record deleted on another device disappears locally")
    func remoteDeletion() async throws {
        let remote = FakeRemote<CartItem>()
        let collection = makeCollection(remote)
        await collection.save(line(dress))
        _ = try await collection.sync()
        await remote.setRows([])
        #expect(try await collection.sync().records.isEmpty)
    }

    @Test("Local pending edits win over the server until pushed")
    func pendingWins() async throws {
        let remote = FakeRemote<CartItem>(rows: [line(dress, quantity: 5)])
        let collection = makeCollection(remote)
        _ = try await collection.sync() // adopt server
        await collection.save(line(dress, quantity: 2)) // user edits
        _ = try await collection.sync()
        #expect(await remote.rows.first?.quantity == 2)
        #expect(await collection.records().first?.quantity == 2)
    }

    @Test("Deleting a never-synced record needs no server call; a synced one is deleted remotely")
    func deletes() async throws {
        let remote = FakeRemote<CartItem>()
        let collection = makeCollection(remote)
        await collection.save(line(dress))
        await collection.remove(line(dress).id)
        _ = try await collection.sync()
        #expect(await remote.deletedIDs.isEmpty)

        await collection.save(line(coat))
        _ = try await collection.sync()
        await collection.remove(line(coat).id)
        #expect(await collection.records().isEmpty, "Hidden immediately")
        _ = try await collection.sync()
        #expect(await remote.deletedIDs == [line(coat).id])
        #expect(await remote.rows.isEmpty)
    }

    @Test("One rejected record doesn't block the rest of the batch")
    func rejectionIsolation() async throws {
        let remote = FakeRemote<CartItem>()
        await remote.reject([line(coat).id])
        let collection = makeCollection(remote)
        await collection.save(line(dress))
        await collection.save(line(coat))
        let report = try await collection.sync()
        #expect(report.rejected.map(\.id) == [line(coat).id])
        #expect(report.records.map(\.id) == [line(dress).id])
        #expect(await remote.rows.map(\.id) == [line(dress).id])
    }

    @Test("An edit made WHILE a push is in flight is not marked synced (version check)")
    func editDuringSync() async throws {
        let remote = FakeRemote<CartItem>()
        let collection = makeCollection(remote)
        await collection.save(line(dress, quantity: 1))
        await remote.pauseNextUpsertCall()

        async let pass = collection.sync()
        await remote.waitUntilPaused()
        await collection.save(line(dress, quantity: 4)) // actor reentrancy lets this interleave
        await remote.resume()
        _ = try await pass

        #expect(await collection.pendingIDs() == [line(dress).id], "Qty 4 still needs uploading")
        #expect(await collection.records().first?.quantity == 4, "Local intent survives reconciliation")
        _ = try await collection.sync()
        #expect(await remote.rows.first?.quantity == 4)
    }

    @Test("Sign-in merge: guest records are uploaded into the account")
    func merge() async throws {
        let remote = FakeRemote<CartItem>(rows: [line(coat)]) // account already had a coat
        let collection = makeCollection(remote)
        await collection.save(line(dress)) // guest added a dress
        await collection.prepareForMerge()
        let report = try await collection.sync()
        #expect(Set(report.records.map(\.product.id.rawValue)) == ["dress", "coat"])
    }
}

// MARK: - Auth / networking

/// Transport that answers auth refresh calls and counts them; API calls return 401 for stale tokens.
final class AuthTestTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var refreshCalls = 0
    private var validToken = "fresh-token"

    var refreshCount: Int {
        lock.withLock { refreshCalls }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        func respond(_ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
            (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        if url.path().hasSuffix("/auth/v1/token") {
            try await Task.sleep(for: .milliseconds(20)) // widen the race window
            lock.withLock { refreshCalls += 1 }
            let expiry = Int(Date().timeIntervalSince1970) + 3600
            return respond(
                200,
                #"{"access_token":"fresh-token","refresh_token":"r2","expires_at":\#(expiry),"#
                    + #""user":{"id":"8F5B6C7D-1111-2222-3333-444455556666","email":"o@c.com"}}"#
            )
        }
        let bearer = request.value(forHTTPHeaderField: "Authorization")
        return bearer == "Bearer \(lock.withLock { validToken })" ? respond(200, "[]") : respond(
            401,
            #"{"code":"PGRST301","message":"JWT expired"}"#
        )
    }
}

@Suite("Supabase auth plumbing")
struct SupabaseAuthTests {
    let config = SupabaseConfig(url: URL(string: "https://demo.supabase.co")!, publishableKey: "pk")

    func expiredSession() -> AuthSession {
        AuthSession(
            accessToken: "old-token",
            refreshToken: "r1",
            expiresAt: .now.addingTimeInterval(-10),
            user: User(name: "Olivia", email: "o@c.com")
        )
    }

    @Test("Concurrent requests with an expired token trigger exactly ONE refresh")
    func singleFlightRefresh() async throws {
        let transport = AuthTestTransport()
        let vault = SessionVault(config: config, storage: EphemeralSecureStorage(), transport: transport)
        await vault.store(expiredSession())
        let client = APIClient(
            baseURL: config.url,
            transport: transport,
            authorizer: SupabaseAuthorizer(vault: vault, publishableKey: "pk")
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 8 {
                group.addTask { _ = try await client.send(Endpoint<[String]>(path: "rest/v1/cart_items")) }
            }
            try await group.waitForAll()
        }
        #expect(transport.refreshCount == 1)
        #expect(await vault.current()?.accessToken == "fresh-token")
    }

    @Test("A 401 on a token that looked valid is recovered by refresh + one retry")
    func unauthorizedRetry() async throws {
        let transport = AuthTestTransport()
        let vault = SessionVault(config: config, storage: EphemeralSecureStorage(), transport: transport)
        var revoked = expiredSession()
        revoked.expiresAt = .now.addingTimeInterval(3600) // not expired locally, but server says 401
        await vault.store(revoked)
        let client = APIClient(
            baseURL: config.url,
            transport: transport,
            authorizer: SupabaseAuthorizer(vault: vault, publishableKey: "pk")
        )

        let rows = try await client.send(Endpoint<[String]>(path: "rest/v1/cart_items"))
        #expect(rows.isEmpty)
        #expect(transport.refreshCount == 1)
    }

    @Test("GoTrue errors map to domain auth errors")
    func authErrorMapping() async {
        let invalid = APIError.server(ServerError(status: 400, code: "invalid_credentials", message: "Invalid login credentials"))
        await #expect(throws: AuthError.invalidCredentials) {
            try await SupabaseAuthService.mapAuthErrors { () async throws -> Int in throw invalid }
        }
        let exists = APIError.server(ServerError(status: 422, code: "user_already_exists", message: "User already registered"))
        await #expect(throws: AuthError.emailAlreadyInUse) {
            try await SupabaseAuthService.mapAuthErrors { () async throws -> Int in throw exists }
        }
        await #expect(throws: AuthError.network) {
            try await SupabaseAuthService.mapAuthErrors { () async throws -> Int in throw APIError.offline }
        }
    }
}

@Suite("Supabase adapters")
struct SupabaseAdapterTests {
    @Test("Server exceptions from place_order map to typed checkout errors")
    func checkoutErrorMapping() {
        func server(_ message: String, _ detail: String? = nil) -> APIError {
            .server(ServerError(status: 400, code: "P0001", message: message, detail: detail))
        }
        #expect(SupabaseOrderService
            .map(server("out_of_stock", "Rosie Maxi Dress")) as? CheckoutError == .outOfStock(products: "Rosie Maxi Dress"))
        #expect(SupabaseOrderService.map(server("payment_declined")) as? PaymentError == .declined)
        #expect(SupabaseOrderService.map(server("coupon_minimum_not_met", "15000")) as? CouponError == .minimumNotMet(150))
        #expect(SupabaseOrderService.map(APIError.offline) as? CheckoutError == .offline)
    }

    @Test("PostgREST in-list quoting survives commas, pipes and quotes")
    func inList() {
        #expect(PostgREST.inList(["a|Taupe Floral|M", #"b"c"#]) == #"in.("a|Taupe Floral|M","b\"c")"#)
    }

    @Test("Error bodies from PostgREST and GoTrue are both parsed")
    func serverErrorParsing() {
        let postgrest = ServerError.parse(status: 400, data: Data(#"{"code":"P0001","message":"out_of_stock","details":"Luna"}"#.utf8))
        #expect(postgrest == ServerError(status: 400, code: "P0001", message: "out_of_stock", detail: "Luna"))
        let gotrue = ServerError.parse(
            status: 400,
            data: Data(#"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#.utf8)
        )
        #expect(gotrue?.code == "invalid_credentials")
        #expect(ServerError.parse(status: 500, data: Data("oops".utf8)) == nil)
    }
}
