# ADR 0005 — Local-first cart & wishlist with state-based sync

**Status:** Accepted

## Context
Shoppers edit their bag on trains, in lifts, in stores with bad reception. A cart that spins or
errors on every tap loses sales. The server must still be the source of truth (other devices,
pricing, stock) and checkout must be exact.

## Decision
**Local-first for the cart and wishlist only.** Catalog is cached read-only; checkout, payment and
orders are online-only ("You're offline. Connect to complete checkout.").

```
tap ─► SyncedList (@MainActor, optimistic) ─► SerialTaskQueue ─► SyncedCollection (actor, on disk)
                                                                   │  sync()
             NetworkMonitor ─┐                                     ▼
 launch/foreground/sign-in ──┼─► SyncCoordinator ──► push upserts ─► push deletes ─► pull + reconcile
      debounce 600 ms / BG ──┘                                     (Supabase REST, RLS-scoped)
```

### State-based, not an operation log
Each record carries `synced | pendingUpsert | pendingDelete`, a `version` and `existsRemotely`.

| | Operation log | **State-based (chosen)** |
|---|---|---|
| 10 offline quantity taps | 10 requests, replayed in order | **1 upsert** of the final value |
| Retry after timeout | must dedupe ops | upserts are absolute → idempotent |
| Storage growth | unbounded until flushed | one row per record |
| Delete of never-synced item | create + delete ops | dropped locally, no request |

### Reconciliation rules
1. Push pending upserts in one batch. On a **4xx rejection**, retry records individually to isolate
   the offender; drop it locally and tell the user ("… is no longer available"). **Transient**
   errors (offline, 5xx, timeout, 429) abort the pass — everything stays pending.
2. Push pending deletes.
3. Pull the server set:
   - local `synced` → replaced by the server copy, or removed if gone (deleted on another device);
   - local pending → **kept** (the user's latest intent wins until pushed);
   - server-only → added (created on another device).
4. A push only marks a record synced if its `version` is unchanged — edits made *during* the
   request (actor reentrancy) stay pending. Covered by `editDuringSync` test.

### Conflict policy
Last write from the user's own device wins for records they changed; for everything else the
server wins. For a cart (absolute quantities, one owner) this is simpler and more predictable than
field-level merges or CRDTs, and it is what users expect.

### Sync triggers
Launch · foreground · connectivity restored (`NWPathMonitor`) · sign-in (after merging guest items)
· each change (debounced 600 ms) · Background App Refresh when the app closes with pending changes.
Failures back off 2 → 4 → 8 … 60 s; offline doesn't poll — the monitor wakes it.

**`NWPathMonitor` is a hint, not truth**: a satisfied path doesn't mean the server is reachable
(captive portals, DNS, outages). Correctness comes from request outcomes; the monitor only makes
recovery instant.

### Checkout
The server prices the *server* cart, so checkout first runs a sync and refuses to proceed if
anything is still pending (`CheckoutError.cartNotSynced`) or the device is offline.

## Consequences
- The bag never blocks on the network; the UI shows honest sync state (cart header + per-line badge).
- Sign-out wipes the local copy (it belongs to the account); sign-in merges guest items.
- All rules are unit-tested against an in-memory remote that can fail, reject and pause mid-request.
