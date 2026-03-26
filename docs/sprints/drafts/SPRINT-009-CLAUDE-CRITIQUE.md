# Sprint 009 Critique — Codex and Gemini Drafts

Reviewer: Claude
Date: 2026-03-26
Compared against: SPRINT-009-INTENT.md, SPRINT-009-CLAUDE-DRAFT.md, and actual codebase state.

---

## Codex Draft Critique

### Strengths

1. **Wave 0 substrate-first approach**: The Codex draft is the only draft that dedicates an entire wave to building the execution substrate (runner, manifest, scenario seeding, test harness extensions) before touching renderer code. This is structurally sound — the other drafts jump into feature work without first making the wave system deterministic.

2. **Explicit wave manifests**: The `KitchenSinkWave` manifest concept (wave ID, owned files, targeted cases, scenario seeds, expected artifacts) is a strong organizational primitive. It gives each wave a machine-readable contract rather than relying on prose descriptions.

3. **Detailed DOT workflow per wave**: The per-wave DOT graph (lines 44-71) is the most operationally complete of any draft. It includes explicit retry targets (`retry_target="implement"`), human approval gates (`baseline_gate`), and granular stage prompts. This maps directly to the existing `AttractorTaskExecutor` stage model.

4. **Baseline promotion as a deliberate gate**: Treating baseline updates as an explicit human approval step (not a side effect of tests passing) is pragmatically correct given that pixel baselines are durable artifacts that can capture unintended terminal state.

5. **Scenario seeding via env vars**: The `OMNIUI_KITCHENSINK_SCENARIO`, `OMNIUI_KITCHENSINK_ACTIVE_TAB`, etc. approach cleanly avoids the flakiness of long Tab-chain focus traversal in tests. This directly addresses the intent doc's concern about deterministic validation.

6. **Scoped risk table**: Seven risks with concrete mitigations, including the important insight that `Primitives.swift` is monolithic and easy to regress (line 364).

7. **Open questions are actionable**: All six open questions (lines 389-395) have clear decision points with bounded options. They avoid hand-waving.

### Weaknesses

1. **`TUI_TEST_CASES` does not exist in `tui-test.sh`**: The draft heavily relies on `TUI_TEST_CASES=wave01_shapes,wave01_tabs` (lines 53, 136, 176, etc.) but the actual `scripts/tui-test.sh` (448 lines) only supports `TUI_TEST_MODE` (smoke, kitty, vhs, all). The per-case selection mechanism is aspirational — it would need to be built in Wave 0. The draft treats it as if it already exists.

2. **`KitchenSinkAttractorRunner` target doesn't exist**: The draft proposes `swift run KitchenSinkAttractorRunner wave-01` (line 122) but `Package.swift` has no such target. Wave 0 would need to create it, which is acknowledged in the files table but underestimated in effort — adding an executable target that correctly wires `AttractorTaskExecutor` dependencies is non-trivial.

3. **No `@Observable`/`@Bindable` runtime work**: The draft mentions re-auditing `@Observable` in Wave 4 (line 301) but explicitly suggests deferring it "if KitchenSink already behaves acceptably." The intent doc lists `@Observable/@Model` as a "not working / no-op" item (item 4 in the audit). Waving this away contingently is a gap — if the audit says it's a no-op, it needs work or an explicit documented deferral.

4. **No SwiftData/@Query implementation**: The draft is silent on `ModelContext`, `@Query`, or `FetchDescriptor`. The intent lists these as "not working" (item 5). Even an in-memory shim needs deliberate work. The draft doesn't address this at all.

5. **No gesture system work**: Gestures are listed as "not working" in the intent (item 6) but the Codex draft never mentions them. Not even a documented deferral.

6. **Animation work is underspecified**: Wave 3 mentions "move spinner/progress animation off wall-clock" and "make `.animation(value:)` meaningful" but doesn't specify the tick model, interpolation approach, or how `withAnimation` should behave. This is the vaguest section of the draft.

7. **Wave effort percentages don't sum to 100%**: 15 + 25 + 25 + 20 + 15 = 100%. This is fine arithmetically, but the ~15% for Wave 0 may be an underestimate given that it creates a new executable target, a new manifest system, extends the test harness with case selection, and adds scenario seeding. This is closer to 20-25% of effort.

8. **Missing transition implementation**: Transitions (intent item 7 under "not working") are not addressed in any wave.

### Gaps in Risk Analysis

- **No risk for `@Observable` macro correctness**: The `@Observable` macro emits `ObservationRegistrar` conformance, but whether the `willSet`/`didSet` hooks are correctly wired for render invalidation is uncertain. This is a medium-likelihood, high-impact risk.
- **No risk for `Primitives.swift` file size**: At 2,229 lines already, adding Table multi-column layout, Grid, tree expand/collapse, and more will push this file toward 3,000+ lines. The draft notes it's "monolithic" in the risk table but doesn't propose any mitigation beyond "targeted TUI cases."
- **No risk for interaction script reliability**: xdotool scripts depend on exact pixel coordinates and timing. The draft mentions xdotool-based interaction scripts but doesn't address the inherent fragility of coordinate-based automation.
- **No risk for CI/Docker environment differences**: The test infrastructure runs in Docker with Xvfb + Kitty. Font rendering, terminal size, and Unicode support can differ between local macOS development and CI. This could cause baseline mismatches.

### Missing Edge Cases

- What happens if a wave's scenario seed produces different output across notcurses versions?
- How does the wave runner handle partial completion (e.g., build passes but smoke fails on retry limit)?
- What if the human baseline gate is never approved? Is there a timeout or skip path?
- How are wave artifacts cleaned up between retries?

### Definition of Done Completeness

The DoD (lines 346-356) is thorough for the wave infrastructure but weak on feature coverage:
- No DoD item for `@Observable`/SwiftData working.
- No DoD item for gesture behavior.
- No DoD item for animation/transition behavior.
- "Every in-scope KitchenSink section renders meaningfully" is good but doesn't define "in-scope" — Wave 4 explicitly allows deferral of items, so the DoD could be satisfied while multiple intent-listed features remain no-ops.

---

## Gemini Draft Critique

### Strengths

1. **Concise and scannable**: At 124 lines, the draft is easy to read end-to-end. It covers all four waves without excessive detail, making it suitable as a quick overview.

2. **Includes all feature categories**: Unlike the Codex draft, Gemini addresses `@Observable`, SwiftData, gestures, and animation in Wave 4. This is the most comprehensive feature coverage of all drafts.

3. **Clear use case list**: The four use case categories (Shapes/Visuals, Advanced Layouts, Interactive Forms, Reactivity/Motion) map well to the intent doc's audit results.

4. **DOT graph is readable**: The clustered subgraph structure (lines 40-90) is visually clear and shows the linear wave dependency chain with pass/fail edges.

### Weaknesses

1. **Critically underspecified**: Every wave is described in 3-5 bullet points. Wave 1 says "Update `Primitives.swift` for shape properties" without specifying what properties, what the rendering strategy is, or how the Unicode fallback works. This is not implementable as written — an executor would need to make most design decisions independently.

2. **No execution substrate**: There is no equivalent of Codex's Wave 0. No manifest system, no scenario seeding, no test case selection, no runner. The draft assumes the attractor run infrastructure already works for this purpose, but the existing `AttractorWorkflowTemplate` doesn't have KitchenSink-specific wave support.

3. **No scenario seeding or deterministic test strategy**: The draft doesn't address how KitchenSink reaches stable states for pixel baselines. Without env-driven scenario seeds, tests depend on Tab traversal chains, which is exactly the flakiness problem the intent doc highlights.

4. **Files summary is incomplete**: Only 5 files are listed (lines 94-98). The actual scope touches at least 15-20 files based on the intent doc. Missing: `Runtime.swift`, `BrailleRaster.swift`, `Animation.swift`, `State.swift`, `Package.swift`, `scripts/tui-test.sh`, `scripts/ghostty-lab.sh`, parity docs.

5. **DOT graph doesn't match `AttractorWorkflowTemplate` conventions**: The draft's DOT graph (lines 40-90) uses `subgraph cluster_*` with cosmetic attributes (`style=rounded`, `fontname="Helvetica"`) but doesn't include `prompt`, `goal_gate`, `retry_target`, `auto_status`, or `interaction_kind` attributes that the actual `AttractorWorkflowTemplate` and `AttractorTaskExecutor` consume. This graph is illustrative, not executable.

6. **Wave ordering is questionable**: Wave 1 includes `AsyncImage` (placeholder text) alongside shapes. The intent doc lists `AsyncImage` as "not working" with URL fetching and potential Kitty rendering — this is high-risk and should be in a later wave, not the first. The Codex draft correctly isolates it in Wave 4.

7. **SwiftData scope answered prematurely**: Open Question 1 commits to "in-memory query support for `@Query` and `modelContainer`" but doesn't specify what that means technically — no mention of `FetchDescriptor`, `#Predicate`, sort descriptors, or how `@Query` observes context changes.

8. **No baseline management strategy**: The draft mentions capturing baselines but doesn't address how they're promoted, reviewed, or gated. Baselines just appear in `Tests/tui/baselines/*` with no approval workflow.

9. **Two risks is insufficient**: The risk table lists only terminal capabilities and reactivity overhead. Missing: baseline flakiness, scope creep, Primitives.swift complexity, macro correctness, CI environment divergence, interaction script fragility.

10. **Security section is thin**: Only SecureField masking and AsyncImage are addressed. No mention of keeping attractor prompts scoped, preventing secret leakage in screenshots, or baseline artifacts capturing unintended content.

### Gaps in Risk Analysis

- **No scope risk**: 21 features across partial/broken categories is enormous. No discussion of what gets cut if waves run long.
- **No baseline flakiness risk**: The most common failure mode in pixel-based TUI testing.
- **No risk for gesture mouse event conflicts**: Terminal mouse events are shared between scroll, click, and the proposed gesture system. Priority/routing conflicts are likely.
- **No risk for macro correctness**: `@Observable` and `@Model` macro output hasn't been verified against the runtime expectations.
- **No risk for `Primitives.swift` growing unmanageably large**: Already 2,229 lines; adding Table, Grid, GridRow, LazyHGrid, tree toggle, and more could double it.

### Missing Edge Cases

- What happens when `@Query` result set changes during a render cycle?
- How does `Table` handle zero rows or columns wider than terminal width?
- What if DragGesture and scroll conflict on the same mouse movement?
- How does `.transition` behave when the view is removed before the transition completes?
- What happens if AsyncImage URL fetch times out mid-render?

### Definition of Done Completeness

The DoD (lines 100-105) has five items, which is too few:
- "All 21 identified partial/broken features yield distinct terminal output" is ambitious but doesn't define "distinct" or set a threshold. A single character change technically yields "distinct" output.
- No DoD for interaction scripts passing.
- No DoD for Ghostty captures existing.
- No DoD for parity docs being updated.
- No DoD for the attractor DOT graph being actually executable (vs. illustrative).
- No DoD for `swift build` passing — only mentions `tui-test.sh` and smoke tests.
- Missing: build compiles with Swift 6 strict concurrency, no new warnings.

---

## Comparative Summary

| Dimension | Codex | Gemini |
|-----------|-------|--------|
| **Implementability** | High — wave manifests, DOT prompts, and file lists are specific enough to execute | Low — too vague to implement without significant design decisions by the executor |
| **Feature coverage** | Incomplete — misses @Observable, SwiftData, gestures, transitions | Complete — addresses all 21 items from the intent audit |
| **Infrastructure** | Strong — Wave 0 builds the substrate first | Absent — assumes infrastructure exists |
| **Risk analysis** | Good (7 risks) but misses macro correctness and CI divergence | Insufficient (2 risks) |
| **DoD quality** | Good for infrastructure, weak for feature-level verification | Too few items, no measurable thresholds |
| **DOT graph fidelity** | Executable — includes AttractorTaskExecutor attributes | Illustrative only — missing prompt/gate attributes |
| **Baseline strategy** | Explicit approval gates per wave | Unaddressed |
| **Scope management** | Conservative — Wave 4 time-boxes risky items | Optimistic — commits to all 21 features |

### Recommendation

The Codex draft is the stronger foundation for a merged sprint plan. Its substrate-first approach, wave manifest system, and executable DOT graphs align with the existing `AttractorTaskExecutor` conventions. However, it must be supplemented with:

1. Feature coverage from the Claude or Gemini drafts for `@Observable`, SwiftData, gestures, and transitions — even if some are documented deferrals.
2. The Gemini draft's willingness to address all audit items, tempered by the Codex draft's realistic scoping in Wave 4.
3. Acknowledgment that `TUI_TEST_CASES` and `KitchenSinkAttractorRunner` don't exist yet and must be built.
4. A more complete risk table incorporating macro correctness, CI divergence, and Primitives.swift file size.
5. A Definition of Done that covers both infrastructure and feature-level outcomes with measurable criteria.
