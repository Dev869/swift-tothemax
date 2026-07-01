# Concurrency research (haiku agent) — with lead-agent annotations

## Trustworthy
- Migration path: -strict-concurrency=complete under 5.x first, then Swift 6 mode. (swift.org migration guide)
- SE-0478: default actor isolation (MainActor) — opt-in, per-module. Xcode "Default Actor Isolation" setting.
- SE-0414 region isolation + SE-0430 `sending` params: non-Sendable values may cross isolation when ownership transfers.
- Mutex for sync-only critical sections; actors default.
- Approachable concurrency recommended broadly in 6.2+, per-module rollout.

## SUSPECT (lead annotations)
- Agent attributed @concurrent to SE-0302/ConcurrentValue — WRONG/outdated. @concurrent is part of 6.2 approachable concurrency (paired with nonisolated(nonsending) semantics, SE-0461 "Run nonisolated async functions on the caller's actor").
- Agent said nonisolated(nonsending) "cannot send non-Sendable values" — garbled. Correct: async function runs on the caller's actor instead of hopping to global executor; "nonsending" = doesn't cross isolation.
- SE-0493 async defer: agent found "under review Oct 2025" (stale forum post). WWDC26 coverage (InfoQ, June 2026) places it in Swift 6.4 beta. Treat as 6.4 beta.
