# ADR 0003 — Fixtures served through the real networking stack

**Status:** Accepted

## Context
The portfolio build has no backend, but mock repositories would leave networking, DTO decoding,
error mapping, retries and threading untested and unexercised at runtime.

## Decision
`FixtureTransport` implements `HTTPTransport` and serves bundled JSON (snake_case, integer cents,
ISO-8601 dates — a realistic API contract) with configurable latency. Everything above the transport
— `APIClient`, retry policy, DTO → Domain mapping, single-flight caching repository — is production code.

Switching to a real backend = set `NOVASHOP_API_BASE_URL`; the composition root picks `URLSessionTransport`.

## Consequences
- Contract tests (`DataTests`) decode the fixtures through the production DTOs: an API change that
  breaks decoding fails CI.
- Simulated latency makes skeletons, cancellation and loading states visible during development;
  UI tests run with zero latency for determinism.
