# ADR 0006 — Supabase backend behind our own REST layer

**Status:** Accepted

## Context
A real backend (auth, per-user data, transactional checkout) without spending weeks writing and
hosting one, at zero cost.

## Decision
Supabase free tier (Postgres + Auth + auto-generated REST + RLS), accessed through **our own**
`APIClient` — no Supabase SDK.

- **No SDK**: zero dependencies; features depend on `Domain` protocols; the Supabase adapters are
  one file (`Data/Supabase`). Replacing the backend (e.g. Spring Boot) means rewriting that file,
  not the app.
- **Security model**: the app holds only the *publishable* key. Every user table has Row Level
  Security (`user_id = (select auth.uid())`); coupons are invisible to clients; orders are
  read-only and can only be created by a `SECURITY DEFINER` function with a pinned `search_path`.
- **CRUD via REST, business operations via RPC**: cart/wishlist/addresses are plain PostgREST
  upserts/deletes (idempotent). Checkout is `place_order()`, one transaction that:
  locks product rows in a stable order (no deadlocks) → validates stock → prices from the database
  (the client can't tamper) → applies the coupon → inserts order + snapshot line items →
  decrements stock → clears the cart. An **idempotency key** makes a retried request return the
  first order instead of charging twice.
- **Auth**: GoTrue REST (email + password). Tokens in the Keychain; proactive refresh 60 s before
  expiry; **single-flight** refresh on 401 (N concurrent failures → 1 refresh → N retries); a
  rejected refresh token ends the session and the UI asks the user to sign in again.
- **Account deletion** (App Review 5.1.1(v)) via `delete_my_account()` — no admin key in the app.
- Sign in with Apple / Google need provider setup (and a paid Apple team for Apple), so the
  backend reports `supportsSocialSignIn = false` and the buttons are hidden, not broken.

## Consequences
- Fixtures remain the default: the repo runs with no account, UI tests are deterministic.
- Free-tier projects pause after 7 days of inactivity (one click to resume).
