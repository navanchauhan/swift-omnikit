# Sprint 009: KitchenSink Attractor Run - Making OmniUI TUI Features Real

## Overview

Sprint 009 should turn the current KitchenSink audit into an executable attractor program rather than a one-off cleanup list. The repo already has the core pieces: `KitchenSink` is the canonical demo, `NotcursesRenderer` already owns a real render loop with shape planes and native widgets, `AttractorTaskExecutor` already runs `plan -> implement -> review -> scenario -> judge`, and `scripts/tui-test.sh` already captures pixel baselines. The missing piece is a concrete wave system that binds feature scope, implementation prompts, validation commands, artifacts, and baseline promotion into one repeatable workflow.

The sprint should therefore introduce a versioned KitchenSink wave manifest and a dedicated attractor workflow template for TUI work. Each wave must target a bounded feature group, run the same validation ladder, and emit the same artifact set: generated `workflow.dot`, build logs, smoke logs, pixel diffs, Ghostty captures, and a short judge summary. Baseline updates are not a side effect of "the tests happened to change"; they are an explicit gate in the graph after targeted Kitty diffs are reviewed.

This draft assumes `AGENTS.md` is the effective repo convention source at the root. A repo-root `CLAUDE.md` was not present at planning time, so implementation should confirm there is no second convention file elsewhere before landing structural changes.

## Use Cases

1. **Wave-by-wave TUI implementation**: A maintainer runs `wave-01` and gets a bounded implementation pass that only touches visual shell features such as shapes, tabs, split views, and grouped forms, along with the exact baselines that must be updated.
2. **Stable baseline promotion**: A reviewer sees targeted Kitty diffs for a small wave, approves them through a human gate, and avoids large unreadable baseline churn across the whole KitchenSink.
3. **Worker-backed execution**: The same wave graph can run through `AttractorTaskExecutor` using the existing worker execution mode, so structured TUI work does not need an ad hoc runner.
4. **Local CLI execution**: A developer can run a single wave locally without the whole worker stack, using a thin runner that invokes the same workflow template and writes logs/artifacts to `.ai/attractor-runs/`.
5. **Deterministic validation**: Targeted TUI cases can start from stable KitchenSink scenarios instead of relying on long `Tab` chains, which makes pixel baselines and xdotool interactions materially less flaky.
6. **Scoped stretch handling**: High-risk items such as `AsyncImage`, preference propagation, and richer animation can be isolated into a final bounded wave without destabilizing earlier waves.

## Architecture

The implementation should add one small layer above the existing Attractor machinery instead of replacing it.

**Core pieces**

- `KitchenSinkWave` manifest: one source of truth for wave ID, feature scope, file ownership, KitchenSink scenario seed, target Kitty cases, interaction scripts, and baseline names.
- `KitchenSinkAttractorWorkflowTemplate`: emits a wave-specific DOT graph that extends the existing `AttractorWorkflowTemplate` pattern with explicit build, smoke, pixel, Ghostty, and baseline-approval stages.
- `KitchenSinkAttractorRunner`: a thin executable entrypoint that constructs a `TaskRecord`, applies the chosen wave manifest, and invokes `AttractorTaskExecutor`.
- `tui-test` wave support: `scripts/tui-test.sh` should accept explicit case selection (for example `TUI_TEST_CASES=wave01_shapes,wave01_tabs`) and write deterministic artifacts for the current wave.
- KitchenSink scenario seeding: `Sources/KitchenSink/main.swift` should accept a small set of env-driven seeds such as active tab, split visibility, fixed demo tick, and focused section so wave baselines do not depend on long focus traversal.

**Why this shape fits the current code**

- `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift` already persists `workflow.dot`, `pipeline-result.json`, stage artifacts, and progress summaries.
- `Sources/TheAgentWorker/Attractor/AttractorWorkflowTemplate.swift` already establishes the repo's preferred plan/implement/validate/judge pattern and optional human gates.
- `Sources/KitchenSink/main.swift` already centralizes all demo coverage in one file, so scenario seeding can happen without fragmenting the demo.
- `Sources/OmniUICore/Modifiers.swift` and `Sources/OmniUICore/Primitives.swift` reveal which features are true stubs versus coarse approximations.
- `Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift` already supports shape sprixels, focus overlays, readers, selectors, and event polling; the sprint is mostly about stabilizing and extending existing behavior, not inventing a renderer from scratch.

**Wave contract**

Each wave should use the same graph shape and only vary the prompts, file scope, test cases, and baseline names:

```dot
digraph kitchensink_wave01 {
    graph [default_max_retry=1, retry_target="implement"]

    start         [shape=Mdiamond]
    plan          [shape=box, prompt="Read the KitchenSink wave-01 manifest. Restate scope, owned files, validation commands, and baseline names. Do not touch files outside the manifest."]
    implement     [shape=box, prompt="Implement only wave-01 visual shell work in the owned files. Keep KitchenSink as a single main.swift file. Run commands rather than guessing.", auto_status=true]
    build         [shape=box, prompt="Run swift build --product KitchenSink and targeted Swift tests for the wave. Return outcome fail if build or tests fail.", goal_gate=true, retry_target="implement"]
    smoke         [shape=box, prompt="Run OMNIUI_SMOKE_SECONDS=5 OMNIUI_DEMO_ANIM=0 swift run KitchenSink -- --notcurses or the equivalent built binary. Return fail if startup, signal handling, or shutdown is unstable.", goal_gate=true, retry_target="implement"]
    kitty         [shape=box, prompt="Run TUI_TEST_MODE=kitty TUI_TEST_CASES=wave01_shapes,wave01_tabs,wave01_split,wave01_form scripts/tui-test.sh. Capture diffs and summarize exactly which baselines need promotion.", goal_gate=true, retry_target="implement"]
    baseline_gate [shape=hexagon, prompt="Promote the wave-01 baseline updates?", human.default_choice="Promote", interaction_kind="approval", interaction_title="Wave 01 Baseline Review"]
    ghostty       [shape=box, prompt="Run the matching Ghostty lab capture for wave-01 and store PNG/GIF artifacts under Tests/tui/output/ghostty-lab/. Return fail if capture is missing or obviously blank.", goal_gate=true, retry_target="implement"]
    judge         [shape=box, prompt="Confirm the intended features are visually distinct, artifacts exist, and only the expected baselines changed. Return outcome fail if the wave is incomplete or noisy.", goal_gate=true, retry_target="plan"]
    done          [shape=Msquare]

    start -> plan -> implement -> build
    build -> smoke [condition="outcome=success"]
    build -> implement [condition="outcome=fail"]
    smoke -> kitty [condition="outcome=success"]
    smoke -> implement [condition="outcome=fail"]
    kitty -> baseline_gate [condition="outcome=success"]
    kitty -> implement [condition="outcome=fail"]
    baseline_gate -> ghostty [label="Promote"]
    baseline_gate -> implement [label="Reject"]
    ghostty -> judge
    judge -> done [condition="outcome=success"]
    judge -> plan [condition="outcome=fail"]
}
```

**Execution flow**

```text
KitchenSinkWave manifest
  -> KitchenSinkAttractorWorkflowTemplate
  -> AttractorTaskExecutor / KitchenSinkAttractorRunner
  -> build + smoke + kitty + ghostty artifacts
  -> human baseline gate
  -> judge
  -> next wave
```

**Recommended sequencing model**

Use one executable graph per wave, not a large nested super-graph, for Sprint 009. A shell wrapper or runner can sequence `wave-00` through `wave-04`, but the unit of approval, retry, and baseline promotion should stay wave-local. That keeps logs readable, retries bounded, and baseline churn understandable.

## Implementation

### Wave 0: Runner And Harness Substrate (~15% of effort)

**Goal**

Land the execution substrate before changing renderer behavior. The sprint should not start by editing shapes or tables without first making wave scope, artifact paths, and baseline case selection deterministic.

**Files**

- `Package.swift`
- `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift`
- `Sources/TheAgentWorker/Attractor/KitchenSinkWave.swift`
- `Sources/TheAgentWorker/Attractor/KitchenSinkAttractorWorkflowTemplate.swift`
- `Sources/KitchenSinkAttractorRunner/main.swift`
- `Sources/KitchenSink/main.swift`
- `scripts/tui-test.sh`
- `scripts/tui-test-wave.sh`
- `Tests/TheAgentWorkerTests/AttractorTaskExecutorTests.swift`
- `Tests/TheAgentWorkerTests/KitchenSinkAttractorWorkflowTemplateTests.swift`

**Tasks**

- Add a `KitchenSinkWave` manifest type with:
  - wave ID
  - feature list
  - owned files
  - KitchenSink scenario seed
  - targeted Kitty cases
  - Ghostty capture name
  - expected artifact names
- Add `KitchenSinkAttractorWorkflowTemplate` that generates a DOT graph per wave and includes explicit retry targets for all goal gates.
- Add `KitchenSinkAttractorRunner` so a developer can run `swift run KitchenSinkAttractorRunner wave-01` and get the same `AttractorTaskExecutor` artifact model as worker execution.
- Extend `scripts/tui-test.sh` with explicit case selection such as `TUI_TEST_CASES`, and add `scripts/tui-test-wave.sh` as a stable wrapper around wave manifests.
- Add env-driven KitchenSink scenario seeds, at minimum:
  - `OMNIUI_KITCHENSINK_SCENARIO`
  - `OMNIUI_KITCHENSINK_DEMO_TICK`
  - `OMNIUI_KITCHENSINK_ACTIVE_TAB`
  - `OMNIUI_KITCHENSINK_SPLIT_VISIBILITY`
- Keep KitchenSink in one `main.swift`; scenario seeding should be additive, not a structural split.

**Validation Gate**

- `swift test --filter AttractorTaskExecutorTests`
- `swift test --filter KitchenSinkAttractorWorkflowTemplateTests`
- `swift build --product KitchenSink`
- `TUI_TEST_MODE=kitty TUI_TEST_CASES=wave00_home scripts/tui-test.sh`

**Pixel Baseline Updates**

- Add `wave00_home_initial.png`
- Add `wave00_home_final.png`
- Do not touch later-wave baselines in this wave

### Wave 1: Visual Shells And Layout Fidelity (~25% of effort)

**Goal**

Fix the features that are already close but visually crude: shapes, tabs, split view sizing, grouped forms, and icon fallbacks. This wave should make the KitchenSink look intentionally composed before deeper collection behavior lands.

**Files**

- `Sources/KitchenSink/main.swift`
- `Sources/OmniUICore/Modifiers.swift`
- `Sources/OmniUICore/Primitives.swift`
- `Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift`
- `Sources/OmniUICore/BrailleRaster.swift`
- `Tests/tui/interactions/wave01_tabs.sh`
- `Tests/tui/interactions/wave01_split.sh`
- `Tests/tui/interactions/wave01_shapes.sh`

**Tasks**

- Stabilize shape rendering in `NotcursesRenderer`:
  - fix plane sizing/origin issues that produce tiny or misplaced Ghostty output
  - ensure fill/stroke behavior matches the existing `_ShapeNode` data
  - add a deterministic braille or cell fallback when Kitty pixels are unavailable or unreliable
- Improve `clipShape` from "accepted but visually vague" to a documented terminal approximation tied to shape kind.
- Replace `navigationSplitViewColumnWidth(min:ideal:max:)` coarse `ideal / 8` math with width allocation that respects explicit min/ideal/max intent within the current terminal width.
- Upgrade `TabView` from plain tab buttons + content to a terminal panel shell with visible active state and a content boundary.
- Upgrade grouped `Form` rendering from plain scroll content to inset group blocks with spacing and header separation.
- Add a small symbol fallback map for `Label(systemImage:)` so common KitchenSink icons read as intentional terminal glyphs instead of raw symbol names where practical.

**Validation Gate**

- `swift build --product KitchenSink`
- `TUI_TEST_MODE=kitty TUI_TEST_CASES=wave00_home,wave01_shapes,wave01_tabs,wave01_split,wave01_form scripts/tui-test.sh`
- `scripts/ghostty-lab.sh record-gif Tests/tui/output/ghostty-lab/wave01-visual-shells.gif`
- Full smoke rerun after targeted cases

**Pixel Baseline Updates**

- Add `wave01_shapes_initial.png`
- Add `wave01_shapes_final.png`
- Add `wave01_tabs_final.png`
- Add `wave01_split_final.png`
- Add `wave01_form_final.png`

### Wave 2: Collections, Editing, And Data Layouts (~25% of effort)

**Goal**

Make collection-heavy KitchenSink sections real rather than "list-shaped approximations". This is the wave for tree lists, table columns, edit mode affordances, and grid layout quality.

**Files**

- `Sources/KitchenSink/main.swift`
- `Sources/OmniUICore/Primitives.swift`
- `Sources/OmniUICore/Runtime.swift`
- `Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift`
- `Tests/tui/interactions/wave02_tree.sh`
- `Tests/tui/interactions/wave02_editing.sh`
- `Tests/tui/interactions/wave02_table.sh`
- `Tests/tui/interactions/wave02_grid.sh`

**Tasks**

- Replace `List(children:)` always-expanded indentation with explicit expand/collapse state owned by runtime path keys.
- Make `EditButton` and `.onDelete` visibly actionable in terminal terms:
  - clear edit mode indicator
  - obvious delete affordance
  - predictable focus behavior while editing
- Replace `Table`'s current `List` fallback with a real multi-column layout:
  - stable column width calculation
  - row separators
  - clipped or padded cell content
  - clear focus/selection treatment
- Improve `LazyVGrid` column calculation so adaptive layout is based on usable content width and consistent spacing rather than a rough one-pass division.
- If `Grid`/`GridRow` and `LazyHGrid` are included in this sprint, implement only the subset needed to avoid future layout dead ends; do not let them derail the wave if KitchenSink does not yet exercise them.

**Validation Gate**

- `swift build --product KitchenSink`
- `TUI_TEST_MODE=kitty TUI_TEST_CASES=wave02_tree,wave02_editing,wave02_table,wave02_grid scripts/tui-test.sh`
- `scripts/ghostty-lab.sh record-gif Tests/tui/output/ghostty-lab/wave02-collections.gif`
- `TUI_TEST_MODE=all scripts/tui-test.sh` after targeted cases are green

**Pixel Baseline Updates**

- Add `wave02_tree_initial.png`
- Add `wave02_tree_final.png`
- Add `wave02_editing_initial.png`
- Add `wave02_editing_final.png`
- Add `wave02_table_final.png`
- Add `wave02_grid_final.png`

### Wave 3: Motion, Progress, And Text Input Polish (~20% of effort)

**Goal**

Make temporal and input-driven sections deterministic, meaningful, and testable. This wave should convert several current approximations into consistent terminal-native behavior.

**Files**

- `Sources/KitchenSink/main.swift`
- `Sources/OmniUICore/Modifiers.swift`
- `Sources/OmniUICore/Primitives.swift`
- `Sources/OmniUICore/Runtime.swift`
- `Sources/SwiftUI/Animation.swift`
- `Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift`
- `Tests/tui/interactions/wave03_progress.sh`
- `Tests/tui/interactions/wave03_secure.sh`
- `Tests/tui/interactions/wave03_motion.sh`

**Tasks**

- Move spinner/progress animation off wall-clock `Date()` rendering and onto a deterministic runtime tick or KitchenSink-provided demo tick so screenshots do not drift between runs.
- Replace `scaleEffect` bold/no-op behavior with a terminal-specific emphasis model that can visibly distinguish enlarged content without breaking layout.
- Make `.animation(value:)` and `withAnimation` meaningful for the limited TUI cases KitchenSink actually demonstrates:
  - progress/spinner transitions
  - pulse label updates
  - simple tab or selection emphasis
- Verify `SecureField` masking end-to-end through the native reader path, not just the final rendered node.
- Add scenario seeds or command-line hooks required to start text-input and progress sections in stable states for xdotool scripts.

**Validation Gate**

- `swift build --product KitchenSink`
- `TUI_TEST_MODE=kitty TUI_TEST_CASES=wave03_progress,wave03_secure,wave03_motion scripts/tui-test.sh`
- `scripts/ghostty-lab.sh record-gif Tests/tui/output/ghostty-lab/wave03-motion-input.gif`
- Full smoke rerun with `OMNIUI_DEMO_ANIM=0` and targeted rerun with animation enabled where needed

**Pixel Baseline Updates**

- Add `wave03_progress_initial.png`
- Add `wave03_progress_final.png`
- Add `wave03_secure_final.png`
- Add `wave03_motion_final.png`

### Wave 4: High-Risk Closers And Explicit Non-Goals (~15% of effort)

**Goal**

Time-box the risky items so Sprint 009 finishes with a clear shipped result rather than expanding indefinitely. This wave should either land bounded terminal-native implementations or explicitly update parity docs with a stable limitation.

**Files**

- `Sources/KitchenSink/main.swift`
- `Sources/OmniUICore/Primitives.swift`
- `Sources/OmniUICore/Modifiers.swift`
- `Sources/OmniUICore/Runtime.swift`
- `docs/swiftui-non-renderer-parity.md`
- `docs/swiftui-non-renderer-symbol-diff.md`
- `Tests/tui/interactions/wave04_asyncimage.sh`

**Tasks**

- Decide `AsyncImage` scope:
  - minimum acceptable: deterministic empty/success/failure terminal states with no blank output
  - optional richer path: Kitty-backed image rendering behind a capability check
- Decide whether any preference propagation work is required to eliminate remaining blank or mis-sized KitchenSink sections.
- Re-audit `@Observable`, `@Bindable`, and in-memory `@Query` behavior against actual KitchenSink expectations before committing to deeper runtime work; only implement more if the demo still exhibits real gaps after Waves 0-3.
- Update parity docs for any intentionally deferred items such as advanced gestures, advanced SwiftData semantics, or complex transitions.

**Validation Gate**

- `scripts/run_swiftui_parity_gates.sh`
- `swift build --product KitchenSink`
- `TUI_TEST_MODE=kitty TUI_TEST_CASES=wave04_asyncimage,wave00_home scripts/tui-test.sh`
- Final full `TUI_TEST_MODE=all scripts/tui-test.sh`

**Pixel Baseline Updates**

- Add `wave04_asyncimage_final.png` if `AsyncImage` lands visually
- Otherwise do not invent a placeholder baseline solely to satisfy the wave; document the deferral in parity docs

## Files Summary

| File | Action | Purpose |
|------|--------|---------|
| `Package.swift` | Modify | Add the KitchenSink attractor runner target if needed |
| `Sources/TheAgentWorker/Attractor/KitchenSinkWave.swift` | Create | Source-of-truth wave manifest for attractor execution and validation |
| `Sources/TheAgentWorker/Attractor/KitchenSinkAttractorWorkflowTemplate.swift` | Create | Emit wave-specific DOT workflows with build, smoke, pixel, and approval gates |
| `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift` | Modify | Preserve wave metadata/artifacts cleanly during execution |
| `Sources/KitchenSinkAttractorRunner/main.swift` | Create | Local executable entrypoint for per-wave attractor runs |
| `Sources/KitchenSink/main.swift` | Modify | Add deterministic scenario seeding and any stable anchors needed by tests while keeping one-file demo structure |
| `Sources/OmniUICore/Modifiers.swift` | Modify | Improve split view sizing, clip behavior, and scale semantics |
| `Sources/OmniUICore/Primitives.swift` | Modify | Improve forms, tabs, lists, grids, tables, progress, text inputs, and optional async image behavior |
| `Sources/OmniUICore/Runtime.swift` | Modify | Add runtime state needed for deterministic waves, tree expansion, animation ticks, and collection behavior |
| `Sources/OmniUICore/BrailleRaster.swift` | Modify | Provide stable non-pixel fallback for filled shapes if needed |
| `Sources/SwiftUI/Animation.swift` | Modify | Replace compile-only animation stubs with bounded TUI semantics |
| `Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift` | Modify | Stabilize shapes, native input behavior, focus/render timing, and any wave-specific renderer fixes |
| `scripts/tui-test.sh` | Modify | Add explicit wave/case selection and cleaner wave artifact handling |
| `scripts/tui-test-wave.sh` | Create | One-command wrapper around wave manifests and target case lists |
| `Tests/TheAgentWorkerTests/KitchenSinkAttractorWorkflowTemplateTests.swift` | Create | Validate generated DOT graphs and expected artifact contracts |
| `Tests/TheAgentWorkerTests/AttractorTaskExecutorTests.swift` | Modify | Cover wave-specific execution metadata and artifact collection |
| `Tests/tui/interactions/wave01_*.sh` | Create | Targeted visual-shell interaction scripts |
| `Tests/tui/interactions/wave02_*.sh` | Create | Targeted collection/editing interaction scripts |
| `Tests/tui/interactions/wave03_*.sh` | Create | Targeted motion/input interaction scripts |
| `Tests/tui/interactions/wave04_asyncimage.sh` | Create | Targeted async-image interaction script if that feature lands |
| `Tests/tui/baselines/*.png` | Update | Add or refresh named per-wave pixel baselines |
| `docs/swiftui-non-renderer-parity.md` | Modify | Record accepted terminal approximations and deferred work |
| `docs/swiftui-non-renderer-symbol-diff.md` | Modify | Keep parity reporting aligned with sprint decisions |

## Definition of Done

- [ ] Each wave has a concrete manifest with owned files, cases, and baseline names.
- [ ] Each wave has a valid DOT workflow that passes template tests and Attractor validation.
- [ ] Each wave emits `workflow.dot`, `pipeline-result.json`, and stage response artifacts under `.ai/attractor-runs/`.
- [ ] `scripts/tui-test.sh` can run targeted wave cases without executing the full suite.
- [ ] `KitchenSink` can start in deterministic scenario states needed for the wave tests.
- [ ] Every in-scope KitchenSink section renders meaningfully in notcurses with no blank or invisible sections.
- [ ] Per-wave Kitty baselines are updated only after the wave-specific approval gate.
- [ ] Ghostty PNG/GIF captures exist for every landed wave.
- [ ] `swift build --product KitchenSink` passes after every wave.
- [ ] Final `TUI_TEST_MODE=all scripts/tui-test.sh` passes at the end of the sprint.
- [ ] Final parity docs describe any intentionally deferred items.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Ghostty/Kitty shape rendering differs across terminals and causes baseline churn | Medium | High | Make shapes deterministic first, add non-pixel fallback, and require Ghostty capture before baseline promotion |
| Pixel baselines remain flaky because animation and cursor state are time-based | High | High | Add scenario seeding and runtime-driven fixed ticks in Wave 0/Wave 3 before broad baseline expansion |
| `Primitives.swift` is already monolithic and easy to regress | Medium | Medium | Keep wave manifests explicit about owned symbols and require targeted TUI cases per modified surface |
| Wave scope expands into full SwiftUI parity work | High | High | Keep Wave 4 time-boxed and update parity docs for anything not needed by KitchenSink |
| Baseline approval becomes a bottleneck | Medium | Medium | Use small wave-local diffs and a single approval gate per wave instead of one giant end-of-sprint review |
| Adding a new attractor runner duplicates CLI behavior | Low | Medium | Keep the runner thin and reuse `AttractorTaskExecutor`; do not add a second workflow engine |
| KitchenSink scenario seeding could diverge from the real default app path | Medium | Medium | Always rerun `wave00_home` and a normal smoke launch after targeted scenario tests |

## Security

- Do not use real credentials in `SecureField` tests; all interaction scripts must type deterministic dummy tokens.
- Avoid leaking typed secrets into logs, screenshots, Ghostty captures, or baseline filenames.
- If `AsyncImage` is implemented beyond placeholder states, prefer local fixtures or controlled URLs for tests; do not add unbounded network fetches to CI.
- Keep attractor prompts scoped to repo-owned files and explicit commands so wave execution cannot wander outside the workspace by default.
- Baseline promotion should remain a human approval step because screenshots are durable artifacts and may capture more than intended if the terminal state is wrong.

## Dependencies

- Existing Attractor infrastructure in `Sources/TheAgentWorker/Attractor/`
- `AttractorCLI` and `OmniAIAttractor` graph validation/runtime
- Existing `KitchenSink` demo and notcurses renderer
- Existing TUI harness: Kitty, Xvfb, xdotool, odiff/ImageMagick, VHS
- Ghostty lab scripts for manual/visual proof
- No new third-party Swift framework dependencies

## Open Questions

1. Should the wave runner be a new executable target, or is extending `AttractorCLI` with a KitchenSink mode preferable?
2. Is a human approval gate required for every wave's baseline promotion, or only for waves that materially change pixel-heavy output such as shapes and `AsyncImage`?
3. Should shape fallback in non-Kitty environments use existing braille rasterization, half-block fills, or both depending on terminal capabilities?
4. Is `AsyncImage` success state expected to render actual image content in Sprint 009, or is a deterministic placeholder/success badge sufficient if the section is no longer blank?
5. Does the project want `Grid`/`GridRow` and `LazyHGrid` pulled into this sprint if KitchenSink does not yet exercise them?
6. Should deeper `@Observable` and SwiftData work remain out of scope if KitchenSink already behaves acceptably after scenario seeding and runtime dirty-marking?
