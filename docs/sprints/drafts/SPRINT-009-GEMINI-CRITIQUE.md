# SPRINT-009 Draft Critique

## Executive Summary

The two drafts approach Sprint 009 from distinct but complementary angles. 
- The **Claude Draft** provides a deep, UI-centric implementation plan. It clearly defines the mechanics of the SwiftUI primitives, rendering strategies, and animation loops.
- The **Codex Draft** focuses on the execution substrate and test determinism. It correctly identifies that running a TUI Attractor workflow requires new tooling (wave manifests, scenario seeding) to avoid massive baseline flakiness and approval bottlenecks.

The ideal final sprint plan should merge the tooling and execution substrate from the Codex draft with the specific UI implementation details and architectural clarity from the Claude draft.

## Claude Draft Critique

### Strengths
- **Implementation Depth:** Extremely detailed breakdown of how UI features will actually work (e.g., `@Observable` wiring, tick-based `withAnimation`, `clipShape` border fallbacks).
- **Clear Architectural Boundaries:** Defines the exact files (`Primitives.swift`, `Modifiers.swift`, `NotcursesRenderer.swift`) and how the render pipeline handles new operations.
- **Security:** Excellent security constraints defined for `AsyncImage` (timeouts, size caps, no credentials) and `SecureField` (separated display/value buffers).

### Weaknesses
- **Naivety on Test Execution:** Assumes a single, massive DOT graph and manual execution of interactions, ignoring the reality of TUI test flakiness. 
- **Missing Substrate:** Doesn't address how to actually run this as an Attractor workflow seamlessly without manual intervention for every wave setup.

### Gaps in Risk Analysis
- Fails to identify the high risk of flaky pixel baselines caused by long interaction chains (e.g., navigating to a specific view using keyboard tabs before capturing).
- Misses the risk of terminal resizing mid-animation or mid-render loop.

### Missing Edge Cases
- State leakage between KitchenSink sections if not properly isolated.
- Terminal capability detection failing or misreporting, leading to broken Unicode blocks instead of safe ASCII fallbacks.

### Definition of Done Completeness
- **Strengths:** Very clear visual and functional completion criteria (e.g., "no blank sections", "spinner cycles").
- **Weaknesses:** Lacks programmatic verification of the Attractor artifacts themselves.

## Codex Draft Critique

### Strengths
- **Execution Substrate:** Introduces the brilliant concept of `KitchenSinkWave` manifests and scenario seeding (`OMNIUI_KITCHENSINK_SCENARIO`). This is critical for deterministic TUI testing.
- **Workflow Automation:** Integrates the sprint cleanly into the existing `AttractorTaskExecutor` with targeted DOT generation and human-in-the-loop baseline gates.
- **Pragmatic Scope:** Explicitly calls out deferring out-of-scope SwiftUI parity work to keep the sprint bounded.

### Weaknesses
- **Light on UI Implementation:** Hand-waves over the actual implementation details of complex features like Grid, `@Observable`, and transition animations.
- **Broad Wave Definitions:** Waves are grouped by vague themes ("Visual Shells", "Collections") rather than strict, testable component boundaries.

### Gaps in Risk Analysis
- Lacks a deep security analysis of `AsyncImage` (missing bounds on network fetches).
- Does not address the risk of event loop blocking when bridging `@Observable` state changes to the Notcurses render tick.

### Missing Edge Cases
- SecureField implementation edge cases (e.g., backspacing masked characters, cursor positioning).
- Gesture mapping overlaps (e.g., distinguishing a drag from a click in the terminal).

### Definition of Done Completeness
- **Strengths:** Strong emphasis on CI/CD and tooling completeness (manifests exist, artifacts emitted, subset testing works).
- **Weaknesses:** Lacks explicit visual quality checks beyond "renders meaningfully".

## Synthesis & Recommendations

To create the final `SPRINT-009.md`, the following merge strategy is recommended:

1. **Adopt Codex's Architecture for Execution:** Use the `KitchenSinkWave` manifest, `KitchenSinkAttractorWorkflowTemplate`, and crucially, **Scenario Seeding**. Scenario seeding is mandatory to prevent baseline flakiness.
2. **Adopt Claude's UI Implementation Details:** Bring in the specific strategies for tick-driven animations, SwiftData `@Query` wiring, Unicode shape fallbacks, and the SF Symbol map.
3. **Merge the Wave Structure:**
   - **Wave 0 (from Codex):** Runner and Harness Substrate (Scenario Seeding).
   - **Wave 1 (from Claude):** Shapes, Visual Modifiers, ProgressView.
   - **Wave 2 (from Claude/Codex):** Layout, Chrome, and Collections (Table, Grid, Tree).
   - **Wave 3 (from Claude):** Interaction, Data Observation (`@Observable`), and Input.
   - **Wave 4 (from Claude/Codex):** Animation, AsyncImage (with Claude's security bounds), and Parity Documentation.
4. **Combine the DoDs:** Ensure the final DoD requires both the visual/functional completeness from Claude and the artifact/tooling completeness from Codex.
