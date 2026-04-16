# Automated Regression Testing Design

## Goal

Build a local-first automated regression testing system for Tower Island that prevents feature work from silently breaking existing UI, interactions, or core session logic.

This design must protect two outcomes:

- UI and interaction behavior stays correct
- Functional logic stays correct

## Background

Tower Island already has meaningful automated coverage, but it is uneven.

Current strengths:

- `swift test` covers several pure-logic areas such as `SessionManager`, update flows, notch sizing, geometry, and auto-collapse policy
- `Scripts/test.sh` exercises bridge-to-app integration by sending hook payloads through `di-bridge` and asserting behavior through the app debug log
- `Scripts/test-all.sh` already acts as a local gate and is compatible with git hooks

Current gaps:

- SwiftUI views that users directly interact with have little or no automated verification
- The current integration suite proves that messages were routed, but often does not prove that the correct UI was shown or that the right control was clickable
- Cross-feature regressions are most likely in shared state orchestration such as `SessionManager`, interaction routing, collapse timing, and session visibility rules
- The app does not yet expose a stable test mode for deterministic UI automation
- Critical controls do not yet have a complete accessibility identifier strategy

The result is predictable: logic evolves, a nearby feature changes shared state or timing, and an already-built capability breaks again.

## Scope

This design covers:

- Test architecture for local development and git-hook enforcement
- UI automation for real app windows on macOS
- Expanded unit and integration coverage for session lifecycle and interaction flows
- Test-only infrastructure needed to make UI tests deterministic
- Execution strategy for fast local feedback plus reliable regression coverage

This design does not cover:

- Cloud CI execution
- Screenshot snapshot approval workflows
- Visual diff tooling
- Fuzzing or load testing

## Current Repository Baseline

### Existing Logic Tests

The repository already includes focused unit tests under `Tests/TowerIslandTests/`, including:

- `SessionManagerStatusTests.swift`
- `UpdateManagerTests.swift`
- `PreferencesViewTests.swift`
- `NotchWindowTests.swift`
- `ExpandedAutoCollapsePolicyTests.swift`
- `DIBridgeQuestionResponseTests.swift`
- `ZeroConfigManagerTests.swift`

These tests are useful and should remain the foundation for fast logic validation.

### Existing Integration Tests

`Scripts/test.sh` already contains a broad bash-driven integration suite with modules such as:

- M1 message encoding
- M2 session lifecycle
- M3 agent identity isolation
- M4 permission flow
- M5 question flow
- M6 plan review flow
- M15 multi-session support
- M17 completion sound dedup
- M18 configurable linger duration

This suite is valuable because it exercises the real bridge protocol and the running app.

### Main Weakness in the Current Stack

The current stack is strong at verifying protocol and state transitions, but weak at verifying what the user actually sees and can do.

For example, the current tests do not robustly prove that:

- the correct interaction panel is visible
- the expected controls exist on screen
- keyboard shortcuts or buttons trigger the right action
- the panel resizes and collapses correctly across real interaction flows
- nearby UI changes have not broken permission, question, or plan-review affordances

## Recommendation

Adopt a three-layer regression strategy.

1. Logic unit tests for deterministic business rules and state machines
2. App integration tests for bridge, socket, message routing, and session orchestration
3. Real-window UI automation for visible behavior and user interactions

This is the right fit for Tower Island because the project is centered around shared session state and highly interactive panels. A single testing style is not enough:

- unit tests alone will miss UI regressions
- bash integration alone will miss rendering and interaction regressions
- UI automation alone will be too slow and fragile if it carries all logic coverage

## Test Architecture

### Layer 1: Logic Unit Tests

Purpose:

- Validate deterministic logic with fast feedback
- Catch regressions in state transitions before the app is launched

Continue using `swift test` as the primary entry point for this layer.

Primary targets:

- `SessionManager`
- `UpdateManager`
- `AppUpdater`
- `ExpandedAutoCollapsePolicy`
- `NotchShapeGeometry`
- `ZeroConfigManager`
- `DIBridge`

Recommended test groupings:

- `SessionManagerLifecycleTests.swift`
- `SessionManagerInteractionTests.swift`
- `SessionVisibilityTests.swift`
- `InteractionDedupTests.swift`
- `PreferencesUpdateRenderingTests.swift`

This layer should own all state-machine and policy assertions, especially where multiple UI surfaces share one manager.

### Layer 2: App Integration Tests

Purpose:

- Verify the real application pipeline from hook payload to app state
- Keep protocol compatibility and multi-agent routing safe during feature work

Retain `Scripts/test.sh`, but tighten its role.

It should explicitly own:

- `di-bridge` payload decoding
- Unix socket delivery to the running app
- session creation and routing by agent and session id
- permission/question/plan interaction registration
- multi-session coexistence
- cross-agent isolation

This layer should remain app-driven rather than mocked, but it should stop relying only on free-form debug log strings where possible.

Recommended evolution:

- Keep the current module-based script structure
- Add a test-only structured app state probe for assertions that are currently inferred indirectly from logs
- Preserve debug log assertions only for low-level protocol checks that are easiest to express there

The probe can be implemented as a lightweight local-only diagnostic interface in test mode, for example:

- a test-only local socket command
- a JSON state dump file
- a small CLI command that asks the app for current state

The important constraint is that integration assertions should move from string-matching side effects to stable structured state.

### Layer 3: Real UI Automation

Purpose:

- Verify visible UI and real interactions in a running macOS app window
- Prevent regressions where state is technically correct but the user experience is broken

Add a dedicated UI test target, for example `TowerIslandUITests`, that launches the real app with testing arguments and exercises the real window.

This layer should cover:

- collapsed and expanded island states
- interaction-specific panels
- buttons and keyboard shortcuts
- preferences and update UI
- session list rendering
- visible state recovery after completing actions

This is the primary answer to the user's concern about repeated regression of already-built capabilities.

## Coverage Matrix

### UI and Interaction Correctness

The following user-facing flows must be protected by UI automation.

#### 1. Island State Transitions

Protect:

- collapsed pill appears on launch
- hover expands the island
- permission/question/plan events auto-expand to the correct panel
- interaction completion collapses or returns to the correct state
- empty or inactive state respects auto-hide and collapse policy in test-safe conditions

Why this matters:

- many features share one island container and one state enum in `NotchContentView`
- regressions here can break every capability at once

#### 2. Session List Rendering

Protect:

- multiple sessions render simultaneously
- latest active or visible session is surfaced correctly
- completed sessions remain visible during linger and disappear after expiry
- agent icon, title, subtitle, and status affordances render correctly

Why this matters:

- changes to session filtering or ordering often look harmless in logic but directly break the user's mental model

#### 3. Permission Approval

Protect:

- `PermissionApprovalView` appears when a permission event arrives
- `Deny` and `Allow Once` actions are both reachable and functional
- command description, file path, and diff branches render correctly
- completing the action clears the panel and returns the app to the correct state

Why this matters:

- approval UX is one of the most visible product promises and is easy to break with unrelated interaction changes

#### 4. Question Answering

Protect:

- `QuestionAnswerView` appears with the right prompt text and options
- option list renders correctly across different option counts
- selecting an option shows the correct selected state
- answering dismisses the interaction correctly
- duplicate question events do not produce duplicated visible prompts or duplicate submissions

Why this matters:

- question flows are sensitive to event timing and snapshot behavior
- this is exactly the kind of regression that tends to reappear after unrelated work

#### 5. Plan Review

Protect:

- `PlanReviewView` renders markdown content
- feedback toggle reveals the input field
- `Approve` and `Reject` both work
- feedback-empty and feedback-present paths both complete correctly

Why this matters:

- this flow mixes text rendering, branching UI, and response handling in one surface

#### 6. Preferences and Updates

Protect:

- preferences window opens predictably in test mode
- update/install controls appear or hide correctly across states
- installing progress labels are correct
- stale install controls do not remain visible in up-to-date state

Why this matters:

- update UI already has regression history in recent commits

### Functional Logic Correctness

The following non-visual rules should be protected mainly by unit and integration tests.

#### 1. Session Lifecycle

Protect:

- `sessionStart -> toolStart -> toolComplete -> sessionEnd`
- idle timeout completion
- desktop app termination completion
- CLI process death completion
- selected session fallback behavior

#### 2. Interaction State Machine

Protect:

- permission, question, and plan-review states are set correctly
- newer events supersede stale interaction handlers safely
- tool activity clears stale interaction state when a new active tool event supersedes a waiting permission, question, or plan-review interaction
- answers and approvals return the session to the correct state

#### 3. Multi-Agent and Multi-Session Isolation

Protect:

- mirrored Cursor and Claude session dedupe behavior
- same-agent multi-session coexistence
- same-workspace different-agent isolation
- cross-session interaction routing safety

#### 4. Deduplication and Timing

Protect:

- duplicate question auto-reply window
- completion sound dedup
- hover/collapse timing behavior
- content visibility timing that should not produce state corruption

#### 5. Visibility and Layout Rules

Protect:

- `visibleSessions`
- completed linger duration behavior
- session visibility expiry refresh
- height and size calculations that drive container layout

#### 6. Updater Logic

Protect:

- release decoding
- version normalization and comparison
- invalid tag handling
- install stage transitions
- missing release and missing DMG failure paths

#### 7. Bridge Protocol Compatibility

Protect:

- hook payload decoding by agent and hook type
- `AskUserQuestion` input variants
- permission description extraction
- stdout response format for approvals and answers

#### 8. Agent Configuration Safety

Protect:

- config rewriting for supported agents
- removal of legacy hook state
- idempotent rewrites
- preservation of unrelated config content

## Required Test Infrastructure

### 1. App Test Mode

Add a dedicated app test mode enabled by launch argument or environment variable.

Example intent:

- `--ui-test-mode`
- `TOWER_ISLAND_TEST_MODE=1`

Responsibilities of test mode:

- disable sound effects
- disable or shorten non-essential animation delays where needed for determinism
- disable smart suppression behaviors that depend on active desktop focus unless specifically under test
- disable auto-hide features not under test
- allow loading fixed interaction fixtures at launch
- enable test-only diagnostics used by integration tests

This is necessary because UI automation will be unstable if it must race normal animation, focus, and timer behavior.

### 2. Fixture Injection

UI tests should not depend on real external agents.

Add a test fixture mechanism that can preload app state into known scenarios, such as:

- collapsed with no sessions
- expanded with two active sessions
- one permission request pending
- one question pending with multiple options
- one plan review pending
- update available in preferences

Preferred rule:

- fixtures describe product scenarios, not implementation details

That keeps tests readable and resilient to internal refactors.

### 3. Accessibility Identifier Strategy

Add explicit accessibility identifiers to critical UI controls and containers.

Minimum required coverage:

- island root container
- collapsed pill
- expanded session list
- session card row by session id
- permission panel
- permission approve and deny buttons
- question panel
- question option buttons by option index or label
- plan review panel
- plan approve and reject buttons
- plan feedback field
- preferences root
- check-for-updates button
- install-update button
- update status label

Identifiers must be stable and semantic. Tests should never depend on rendered copy when an identifier can express intent.

### 4. Structured Test Diagnostics

Add a test-only structured diagnostics surface for integration tests.

Recommended responsibilities:

- expose current session count
- expose selected session id
- expose current island state
- expose pending interaction type
- expose visible session ids and statuses

This is not a production feature. It exists to replace brittle log scraping with durable assertions.

## Test Suite Layout

### Swift Test Targets

Keep logic tests in:

- `Tests/TowerIslandTests/`

Add UI tests in:

- `Tests/TowerIslandUITests/`

The UI suite should be focused on key product flows, not exhaustive pixel-level rendering.

### Script Entry Points

Recommended local commands:

- `bash Scripts/test-unit.sh`
- `bash Scripts/test-integration.sh`
- `bash Scripts/test-ui.sh`
- `bash Scripts/test-all.sh`

If introducing separate scripts feels like unnecessary churn, the acceptable fallback is to keep `Scripts/test.sh` as the integration entry point and add only `Scripts/test-ui.sh`, while making `Scripts/test-all.sh` orchestrate both.

The important outcome is separation by responsibility, not script count.

## Git Hook Strategy

The user explicitly wants local execution plus git-hook enforcement.

### Recommended Hook Model

Use two local gates:

- `pre-commit` for fast, high-signal protection
- `pre-push` for the full regression suite

This is preferred over putting the entire UI suite on every single commit because real-window UI automation is slower and more timing-sensitive than unit tests.

### `pre-commit` Gate

Run:

- `swift test`
- targeted integration regression modules for shared interaction flows
- a small UI smoke suite covering one path each for permission, question, plan review, and preferences update state

Purpose:

- catch the most common cross-feature breakages before a commit lands
- keep local feedback fast enough that developers do not bypass the hook

### `pre-push` Gate

Run:

- full `swift test`
- full integration suite
- full UI regression suite

Purpose:

- provide strong local-only protection in the absence of CI
- catch slower or broader regressions before branch sharing

### Fallback If Only One Hook Is Desired

If the team insists on a single hook only, use `pre-commit` but keep the UI suite intentionally scoped to smoke coverage and require `bash Scripts/test-all.sh` before release work.

That is less safe than a two-hook model, but still better than the current state.

## What Must Block a Commit

The following should be mandatory in the fast gate because they represent the most common sources of repeated regressions:

- `SessionManager` logic tests
- updater logic tests
- bridge protocol tests
- integration tests for permission, question, and plan-review registration
- UI smoke tests for permission/question/plan/preferences update visibility and action buttons

These are the shared surfaces most likely to be broken by capability iteration.

## What Can Stay Out of the Fast Gate

The following can run in the full suite instead of every commit:

- exhaustive multi-agent matrix coverage
- long-running linger timing cases
- broader session-list permutation coverage
- slower UI cases involving multiple sequential interactions in one app run

This keeps the developer loop practical without giving up meaningful protection.

## Design Principles

### Protect Product Capabilities, Not Just Files

Tests should be organized around user-visible capabilities such as permission approval, question answering, plan review, and session visibility. This creates a more stable regression net than matching the current file layout.

### Keep Shared Logic Below the UI

Wherever possible, state transitions should remain testable without launching the app. UI automation should prove behavior, not carry all business logic validation.

### Prefer Deterministic Fixtures Over Live Setup

If a test can open the app directly into a permission scenario, that is better than replaying many setup steps through the live UI.

### Use UI Automation Sparingly but Decisively

UI tests should cover key user journeys and fragile interaction surfaces, not every text variation or every internal branch.

### Make Regressions Easy to Localize

When a test fails, it should be obvious whether the problem is:

- state-machine logic
- bridge/integration routing
- visible UI rendering or interaction

That is a major reason to keep the three layers separate.

## Rollout Strategy

### Phase 1

Build the testing foundation:

- app test mode
- fixture injection
- accessibility identifiers for high-value controls
- `test-ui` entry point

### Phase 2

Add smoke UI coverage for the three interaction panels and preferences update controls.

### Phase 3

Expand logic and integration suites around session lifecycle, visibility, deduplication, and multi-session isolation.

### Phase 4

Promote the fast suite into `pre-commit` and the full suite into `pre-push`, then document the workflow in the repository README or contributor docs.

## Risks

- macOS UI tests can become flaky if app timing is not normalized in test mode
- overly broad UI coverage in `pre-commit` will encourage developers to skip or disable hooks
- diagnostics interfaces can become production baggage if they are not kept behind explicit test-only flags
- poor accessibility identifier discipline will make UI tests fragile and expensive to maintain

## Recommendation

Implement a local-first three-layer regression system that preserves the existing strengths of `swift test` and `Scripts/test.sh`, adds deterministic app test infrastructure, and introduces a targeted real-window UI suite for the capability surfaces users care about most.

This design directly addresses the current failure mode: already-built abilities are being broken by nearby changes because the repository verifies protocol and some logic, but does not yet verify enough of the real interaction experience.
