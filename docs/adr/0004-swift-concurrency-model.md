# ADR 0004 — Concurrency model (Swift 6 strict concurrency)

**Status:** Accepted

| Layer | Isolation | Why |
|---|---|---|
| Views, view models, shared stores, `Router` | `@MainActor` | UI state is read by SwiftUI on the main thread; no hops, no races |
| Repositories / services with mutable state | `actor` | Caches, in-flight tables and file I/O serialised without locks |
| Stateless services (`APIClient`, `LocalCouponService`) | `Sendable` struct, `nonisolated async` | Work runs on the cooperative pool — decoding never touches the main thread |
| `MemoryCache` (wraps `NSCache`) | `@unchecked Sendable` | The single justified use: `NSCache` is documented thread-safe |

Patterns used deliberately:
- **Structured concurrency first** — `async let` for independent loads (home feed, bootstrap),
  `withTaskGroup` for bounded image prefetch. Children are cancelled with their parent.
- **View-bound lifetimes** — `.task` / `.task(id:)`; leaving a screen cancels its work.
  `.task(id: query)` means a new search cancels the stale one; the debounce is just a `clock.sleep`.
- **Single-flight** — `RemoteCatalogRepository` and `ImagePipeline` coalesce identical in-flight
  requests onto one `Task`.
- **Ordered persistence** — `SaveQueue` chains writes so unstructured tasks can't reorder them.
- **Caller isolation** — `Perf.measure(isolation: #isolation)` runs on the caller's actor, so
  main-actor code can measure non-`Sendable` closures without a hop.
- **Injected clocks** — `any Clock<Duration>` everywhere time matters; tests use `ImmediateClock`.

Compiled with `SWIFT_VERSION = 6` (complete checking) — zero warnings, zero `@preconcurrency` imports.
