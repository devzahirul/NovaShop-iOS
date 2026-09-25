# ADR 0001 — MVVM with Observation, not TCA / VIPER / Redux

**Status:** Accepted

## Context
The app has ~35 screens, mostly "load → render → mutate shared state (cart, wishlist, session)".
It needs to be approachable for a mid-size team, fast to build, and fully unit-testable.

## Options considered
| Option | For | Against |
|---|---|---|
| **MVVM + `@Observable`** | First-party, zero dependencies, per-property dependency tracking, trivial to test | Discipline required to keep views dumb |
| TCA | Exhaustive testing, strong conventions | Large dependency, steep learning curve, compile-time cost, reducer boilerplate for simple screens |
| VIPER / Clean-VIP | Strict separation | 5 files per screen, protocol explosion, fights SwiftUI's data flow |
| `ObservableObject` MVVM | Familiar | Whole-object invalidation → extra view updates; `@Published` + Combine noise |

## Decision
`@MainActor @Observable final class` view models, one per screen that owns async work or local state.
Screens with no local state (Wishlist, Cart) read shared stores directly — adding a VM there is ceremony.
Shared app state lives in small stores (`CartStore`, `WishlistStore`, `SessionStore`, …) injected via
`.environment(_:)` once at the root.

## Consequences
- Observation tracks *which properties a view body reads*: the tab badge re-renders on cart changes,
  the product grid does not.
- View models have no SwiftUI import and no view references → plain `@Test` functions exercise them.
- Screen state is an explicit `LoadState<T>` enum, so "loading and failed at the same time" cannot exist.
