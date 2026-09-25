# ADR 0002 — Local SPM package, one module per layer / feature

**Status:** Accepted

## Context
Monolithic app targets rebuild everything on every change, let features reach into each other,
and make it impossible to test a feature without the whole app.

## Decision
All code lives in `Packages/NovaKit` (18 library targets). The app target is a 20-line shell.

```
AppFeature ─► *Feature ─► ProductUI ─► DesignSystem ─► ImagePipeline ─► NovaCore
     │             └────► Routing ───► Domain ────────────────────────► NovaCore
     └──► Data ─► Networking ─► NovaCore
```

Rules enforced by the compiler (a feature literally cannot `import` what it is not allowed to):
1. Features never import other features or `Data`.
2. Cross-feature navigation happens through `Route` values (`Routing` module).
3. Only `AppFeature` (the composition root) knows concrete types.

## Consequences
- Incremental builds only recompile the touched module and its dependants.
- SPM libraries are linked **statically**: zero embedded dynamic frameworks → less dyld work at launch.
- Every module has its own test target; `TestSupport` provides shared fakes.
- Adding a screen: one `Route` case + one line in `Destinations.swift`.
