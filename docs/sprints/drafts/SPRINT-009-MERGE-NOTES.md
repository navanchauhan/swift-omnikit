# Sprint 009 Merge Notes

## Draft Strengths

**Claude**: Most implementable feature plan. Concrete behavioral decisions (tick-driven animation, Unicode shape fallback, multi-column Table, @Observable bridge). Strongest security and validation discipline. Best use case coverage aligned to audit.

**Codex**: Only draft with Wave 0 substrate. Wave manifests, scenario seeding, per-wave DOT graphs with retry targets, baseline promotion as human gate. Most operationally mature for Attractor execution.

**Gemini**: Comprehensive feature coverage (addresses all 21 audit items). Good high-level structure. Useful as overview. Correctly identified merge strategy in its own critique.

## Valid Critiques Accepted

1. Codex's `TUI_TEST_CASES` doesn't exist yet — must be built (Claude critique)
2. Gemini is too abstract to execute (Claude + Codex critiques)
3. Gemini's DOT graph is illustrative, not executable (Claude critique)
4. Claude's file paths don't match repo (Codex critique: no Observable.swift, SwiftData.swift)
5. Claude treats some partial implementations as greenfield (Codex critique)
6. Wave 4 in Gemini is overloaded (Claude critique)
7. Claude's single super-graph makes retries/baseline approval heavy (Codex critique)
8. Gemini missing baseline management strategy (Claude critique)
9. Gemini's risk table insufficient (2 risks) (Claude + Codex critiques)

## Valid Critiques Rejected

1. "Codex Wave 0 effort is 15%, should be 20-25%" — Kept at ~15%. Thin runner reusing existing executor.
2. "@Observable is farther from real Observation than Claude assumes" — Claude's plan explicitly names the bridging mechanism and carries it as a risk.
3. "Scope is too broad" (Codex on Claude) — User explicitly chose full implementation for @Observable, SwiftData, and gestures.

## Interview Refinements Applied

1. **Wave 0**: Yes — full substrate (runner, manifest, scenario seeding, test harness)
2. **@Observable/SwiftData**: Full implementation (user chose over conditional/minimal)
3. **Gestures**: Full mouse mapping (user chose over stubs)
4. **main.swift**: Keep unchanged — agents/LLMs drive testing via screenshots (user override)
5. **DOT structure**: Simple linear attractor per wave: plan → critique → implement → validate → critique/postmortem → done (user override — not the multi-stage wave graphs from any draft)

## Merge Strategy

- Adopt Codex's Wave 0 substrate (manifests, runner, test harness) but keep main.swift unchanged per user
- Use Claude's UI implementation details (shapes, animation, @Observable, SwiftData, gestures, security)
- Use Codex's per-wave DOT graph approach, simplified to user's preferred linear attractor shape
- Combine DoDs from Claude (feature-level) and Codex (infrastructure-level)
- Use Claude's risk table as base, supplement with Codex's deterministic testing and file-size risks
- 6 waves total: Wave 0 (substrate) + 5 feature waves
