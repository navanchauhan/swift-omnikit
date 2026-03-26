# Sprint 009 Critique — Claude and Gemini Drafts

Reviewer: Codex  
Date: 2026-03-26  
Compared against: `SPRINT-009-INTENT.md` and current repo state.

## `SPRINT-009-CLAUDE-DRAFT.md`

### Strengths

- Most executable draft of the two. Each wave has goals, files, validation commands, baselines, and concrete behavioral decisions.
- Strongest product decisions on ambiguous TUI behavior: tick-driven animation, Unicode plus Kitty shape rendering, a real multi-column `Table`, bounded SwiftData scope, and explicit deferral of preference propagation.
- Best validation discipline. The per-wave gates, interaction scripts, security notes, and dependency section are specific enough to drive real implementation work.
- Closest to the KitchenSink audit. It reads like a renderer-and-runtime sprint, not just a symbol-parity checklist.

### Weaknesses

- It says "attractor run" but still behaves mostly like a manual feature plan. There is no wave manifest, no `tui-test.sh` case-selection design, no deterministic KitchenSink scenario seeding, and no runner/template work that would make the five waves reproducible inside `AttractorTaskExecutor`.
- Several file seams do not match the repo as it exists today. There is no `Sources/OmniUICore/Observable.swift` or `Sources/SwiftUI/SwiftData.swift`; the real work is split across `ObservableMacro.swift`, `ObservableObjects.swift`, `State.swift`, `Runtime.swift`, `Environment.swift`, and `SwiftDataCompat.swift`.
- It occasionally treats partial implementations as greenfield work. `SwiftDataCompat.swift` already has in-memory `ModelContext` support and sort-only `@Query`, and `SecureField` already masks the rendered node, so the sprint should say what is being extended versus replaced.
- Wave 4 assumes `@Observable` is closer to real Observation than it is. In the current repo, `ObservableMacro.swift` only adds `ObservableObject` conformance, so bridging to true mutation tracking is more than a small runtime hook-up.
- Scope is still too broad for a KitchenSink-focused sprint. `Grid/GridRow`, `LazyHGrid`, richer gestures, transition semantics, and Kitty-backed `AsyncImage` all read more like parity work than the main demo blockers.
- The sprint-level rule that `Sources/KitchenSink/main.swift` must remain unchanged is too rigid. Deterministic scenario seeding and stable test anchors likely belong there.
- The single five-wave super-graph is workable on paper, but it will make retries and baseline approvals heavier than wave-local execution would.

### Gaps In Risk Analysis

- No explicit risk for deterministic testing. `scripts/tui-test.sh` is 448 lines today and has no wave or case selection support, so per-wave baselines will still churn without harness work.
- No explicit risk for state identity bugs. `ForEach` currently does not key runtime state off `id`, which makes tree expansion, row deletion, and selection stability risky after mutation or reorder.
- No explicit risk for strict-concurrency or render-reentrancy issues when observation, model-context callbacks, async loading, and tick-based rendering all interact.
- No explicit risk for hot-spot files. `Primitives.swift` is already 2,229 lines, and the plan concentrates a large amount of change there and in `NotcursesRenderer.swift`.
- No explicit risk for CI and terminal divergence beyond basic Kitty versus Unicode fallback. Braille, spinner glyphs, and box-drawing output can still drift across fonts and environments.

### Missing Edge Cases

- Very narrow terminals, terminal resize during capture, and split-view collapse behavior.
- Empty tables, long cell content, truncation, numeric alignment, and horizontal overflow.
- Tree and edit state after insert, delete, or reorder.
- `SecureField` cursor movement, paste and backspace behavior, and masking through the native input path rather than only the final rendered node.
- `AsyncImage` loading failure, non-image responses, timeouts, offline mode, and repeated rerender behavior.
- Keyboard-only paths for tabs, trees, and edit actions on terminals without usable mouse input.
- Behavior when `OMNIUI_DEMO_ANIM=0` and when Kitty graphics support is unavailable.

### Definition Of Done Completeness

- Better than Gemini's DoD, but still incomplete for an attractor sprint.
- It should require deterministic scenario seeding in KitchenSink, targeted wave or case execution in `tui-test.sh`, and explicit artifact expectations per wave.
- It should require a final full-suite rerun plus documentation or parity updates for deferred items such as preference propagation or gesture non-goals.
- It should explicitly validate the non-Kitty fallback path, since that is one of the draft's core design decisions.
- The `main.swift unchanged` item should be dropped or softened; stable scenario seeding is more important than file purity.
- Because preference propagation is deferred, the DoD should also say which sections are allowed to remain approximate and how that deferral is recorded.

## `SPRINT-009-GEMINI-DRAFT.md`

### Strengths

- Clear, compact summary of the problem and easy to read end-to-end.
- Covers the major feature buckets from the intent doc instead of forgetting `@Observable`, SwiftData, gestures, or animation.
- The four-wave shape is understandable, and the draft keeps good pressure on not turning Sprint 009 into a full SwiftUI platform rewrite.
- Useful as an outline or executive summary for a merged sprint.

### Weaknesses

- Too abstract to execute as the primary sprint document. It does not name owned files per wave, concrete commands, interaction scripts, artifact paths, or measurable acceptance criteria.
- It leaves the hardest behavior questions unresolved: animation model, `.transition` semantics, `AsyncImage` scope, gesture subset, `@Query` semantics, and whether preference propagation is in or out.
- It is not grounded enough in the current repo seams. It omits `Runtime.swift`, `Environment.swift`, `SwiftDataCompat.swift`, `ObservableMacro.swift`, `Sources/KitchenSink/main.swift`, and the TUI harness scripts that would actually need changes.
- It also ignores where the repo already has partial behavior. `SwiftDataCompat.swift`, `AsyncImage`, `SecureField`, `NavigationSplitView`, and the lightweight transition modifier already exist, so the sprint needs to say what is being extended versus replaced.
- The DOT graph is illustrative, not attractor-ready. It lacks the prompt, goal-gate, retry, and human-interaction attributes that the existing `AttractorTaskExecutor` flow uses.
- Wave 4 is overloaded. Animation, transitions, progress, observation, SwiftData, and gestures all converge there even though they touch different layers and have different risk profiles.
- The security section is not fully grounded in current behavior. `AsyncImage` already uses `URLSession` today, so the draft should treat network behavior as an existing surface, not as a theoretical future add-on.

### Gaps In Risk Analysis

- No risk for baseline flakiness, scenario seeding, or approval-gate churn.
- No risk for state identity problems in tree, table, or edit flows.
- No risk for strict-concurrency or event-loop blocking when observation and render invalidation are bridged.
- No risk for `Primitives.swift` and `NotcursesRenderer.swift` concentration or regression surface.
- No risk for CI divergence across fonts, terminals, or Kitty and non-Kitty paths.
- No scope-creep risk despite the draft being intentionally high level.

### Missing Edge Cases

- Narrow terminals and runtime resize behavior.
- Empty and large datasets for tables and grids.
- Tree state after delete or reorder and selection persistence across rerenders.
- Drag versus scroll versus click conflicts if gestures land.
- `SecureField` native masking versus rendered masking.
- `AsyncImage` timeout, offline, and non-image-response handling.
- Animation-disabled baselines and deterministic tick control.
- Non-Kitty fallback rendering for shapes and other visual approximations.

### Definition Of Done Completeness

- The DoD is too thin to ship against. It does not require `swift build`, `swift test`, per-wave interaction scripts, Ghostty artifacts, or a final full TUI suite pass.
- "Distinct terminal output" is not measurable enough. A superficial visual change could satisfy it without making the feature meaningfully usable.
- There is no per-wave DoD, so the document does not control baseline churn or tell reviewers which artifacts belong to which change set.
- It does not require the attractor workflow itself to be executable; it only says artifacts should exist.
- It does not require documentation of explicit deferrals or parity gaps.

## Recommendation

- Claude's draft is the better primary base. It is far more actionable, makes needed product decisions, and has a much stronger verification story.
- Gemini's draft is useful as a concise overview, but not as the main sprint spec.
- Before finalizing Sprint 009, the merged draft should add deterministic KitchenSink scenario seeding.
- Before finalizing Sprint 009, the merged draft should add wave-scoped test selection and artifact expectations.
- Before finalizing Sprint 009, the merged draft should realign file ownership with current repo seams such as `ObservableMacro.swift`, `Runtime.swift`, and `SwiftDataCompat.swift`.
- Before finalizing Sprint 009, the merged draft should trim or explicitly time-box parity-stretch items such as richer gestures, `Grid/GridRow`, `LazyHGrid`, and real image rendering.
