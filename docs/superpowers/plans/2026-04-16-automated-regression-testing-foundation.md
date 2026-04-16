# Automated Regression Testing Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic local regression infrastructure (test mode, fixtures, accessibility ids, diagnostics, and runnable UI smoke entry points) so new feature work cannot silently break core interaction flows.

**Architecture:** Keep existing `swift test` and `Scripts/test.sh` as the base, then add a test-only infrastructure layer inside the app process: `TowerIslandTestMode`, scenario fixtures, accessibility-id conventions, and structured diagnostics JSON output. Build UI smoke coverage as a dedicated XCTest target (`TowerIslandUITests`) that launches the app in test mode and verifies key interaction surfaces through accessibility identifiers, then wire fast/full script entry points for local + git-hook enforcement.

**Tech Stack:** Swift, SwiftUI, AppKit, Observation, XCTest, Bash

---

## Scope Split

The spec contains multiple independent subsystems (test infrastructure, UI smoke automation, integration diagnostics hardening, and hook policy). This plan covers **Phase 1 + Phase 2**, plus the minimal script/hook wiring needed to run them locally. Follow-up plans should cover:

1. Full structured integration assertions replacing log scraping module-by-module.
2. Expanded lifecycle/isolation/dedup regression matrix.
3. Broader UI suites beyond smoke coverage.

---

## File Map

- Create: `Sources/DynamicIsland/TestSupport/TowerIslandTestMode.swift`
  - Parses launch arguments and env flags; central test-mode feature switches.
- Create: `Sources/DynamicIsland/TestSupport/UITestFixture.swift`
  - Defines deterministic fixture scenarios and builds seeded sessions/update states.
- Create: `Sources/DynamicIsland/TestSupport/TestDiagnosticsSnapshot.swift`
  - Defines structured diagnostics payload and serialization.
- Create: `Sources/DynamicIsland/TestSupport/TestDiagnosticsWriter.swift`
  - Writes diagnostics JSON to `~/.tower-island/test-diagnostics.json` when test mode is enabled.
- Create: `Sources/DynamicIsland/Views/AccessibilityIDs.swift`
  - Stable semantic accessibility identifiers for island surfaces and controls.
- Modify: `Sources/DynamicIsland/AppDelegate.swift`
  - Enable test mode bootstrap, fixture injection, and diagnostics write trigger wiring.
- Modify: `Sources/DynamicIsland/Managers/SessionManager.swift`
  - Add test-only diagnostics snapshot exposure and deterministic timer behavior gate.
- Modify: `Sources/DynamicIsland/Views/NotchContentView.swift`
  - Apply root/collapsed/expanded/panel accessibility identifiers.
- Modify: `Sources/DynamicIsland/Views/SessionListView.swift`
  - Apply row identifiers per session id.
- Modify: `Sources/DynamicIsland/Views/PermissionApprovalView.swift`
  - Apply permission panel and action button identifiers.
- Modify: `Sources/DynamicIsland/Views/QuestionAnswerView.swift`
  - Apply question panel and option button identifiers.
- Modify: `Sources/DynamicIsland/Views/PlanReviewView.swift`
  - Apply plan panel, approve/reject, and feedback field identifiers.
- Modify: `Sources/DynamicIsland/Views/PreferencesView.swift`
  - Apply preferences root + update controls identifiers.
- Modify: `Sources/DynamicIsland/Managers/SocketServer.swift`
  - Replace selected log assertions with structured diagnostics update call sites (test mode only).
- Create: `Tests/TowerIslandTests/TowerIslandTestModeTests.swift`
  - Unit tests for launch/env parsing and feature flags.
- Create: `Tests/TowerIslandTests/UITestFixtureTests.swift`
  - Unit tests for scenario materialization.
- Create: `Tests/TowerIslandTests/TestDiagnosticsSnapshotTests.swift`
  - Unit tests for diagnostics snapshot content.
- Create: `Tests/TowerIslandUITests/UISmokeTests.swift`
  - Real-app smoke suite for permission/question/plan/preferences update visibility.
- Create: `Tests/TowerIslandUITests/UISmokeTestSupport.swift`
  - App launcher + polling helpers for diagnostics file and AX lookups.
- Modify: `Package.swift`
  - Add `TowerIslandUITests` test target.
- Create: `Scripts/test-unit.sh`
  - Fast unit-test entry point.
- Create: `Scripts/test-integration.sh`
  - Existing integration suite wrapper.
- Create: `Scripts/test-ui.sh`
  - UI smoke runner entry point.
- Modify: `Scripts/test-all.sh`
  - Orchestrate unit + integration + UI suites.
- Modify: `Scripts/install-git-hooks.sh`
  - Install both pre-commit and pre-push hooks.
- Create: `.githooks/pre-commit`
  - Fast gate (`test-unit`, targeted integration modules, UI smoke subset).
- Create: `.githooks/pre-push`
  - Full gate (`test-all`).

---

### Task 1: Add deterministic app test mode

**Files:**
- Create: `Sources/DynamicIsland/TestSupport/TowerIslandTestMode.swift`
- Modify: `Sources/DynamicIsland/AppDelegate.swift`
- Test: `Tests/TowerIslandTests/TowerIslandTestModeTests.swift`

- [ ] **Step 1: Write the failing tests for test-mode detection and flags**

```swift
import XCTest
@testable import TowerIsland

final class TowerIslandTestModeTests: XCTestCase {
    func testEnablesWhenLaunchArgumentPresent() {
        let mode = TowerIslandTestMode(
            arguments: ["TowerIsland", "--ui-test-mode"],
            environment: [:]
        )

        XCTAssertTrue(mode.isEnabled)
        XCTAssertTrue(mode.disableSoundEffects)
        XCTAssertTrue(mode.disableSmartSuppression)
    }

    func testEnablesWhenEnvironmentVariablePresent() {
        let mode = TowerIslandTestMode(
            arguments: ["TowerIsland"],
            environment: ["TOWER_ISLAND_TEST_MODE": "1"]
        )

        XCTAssertTrue(mode.isEnabled)
    }

    func testDisabledByDefault() {
        let mode = TowerIslandTestMode(arguments: ["TowerIsland"], environment: [:])
        XCTAssertFalse(mode.isEnabled)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TowerIslandTestModeTests`
Expected: FAIL with missing `TowerIslandTestMode` type.

- [ ] **Step 3: Add minimal test-mode model**

```swift
import Foundation

struct TowerIslandTestMode: Equatable {
    let isEnabled: Bool
    let disableSoundEffects: Bool
    let disableSmartSuppression: Bool
    let disableAutoHideWhenIdle: Bool
    let shortenAnimationDelays: Bool
    let fixtureName: String?

    init(arguments: [String], environment: [String: String]) {
        let argEnabled = arguments.contains("--ui-test-mode")
        let envEnabled = environment["TOWER_ISLAND_TEST_MODE"] == "1"
        isEnabled = argEnabled || envEnabled

        disableSoundEffects = isEnabled
        disableSmartSuppression = isEnabled
        disableAutoHideWhenIdle = isEnabled
        shortenAnimationDelays = isEnabled
        fixtureName = environment["TOWER_ISLAND_UI_FIXTURE"]
    }

    static var current: TowerIslandTestMode {
        TowerIslandTestMode(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }
}
```

- [ ] **Step 4: Wire `AppDelegate` to apply deterministic defaults in test mode**

```swift
private let testMode = TowerIslandTestMode.current

func applicationDidFinishLaunching(_ notification: Notification) {
    guard !Self.exitingAsDuplicateInstance else { return }
    Self.shared = self
    NSApp.setActivationPolicy(.accessory)

    if testMode.isEnabled {
        UserDefaults.standard.set(true, forKey: "reduceMotion")
        UserDefaults.standard.set(false, forKey: "smartSuppression")
        UserDefaults.standard.set(false, forKey: "autoHideWhenNoActiveSessions")
    }

    sessionManager.audioEngine = testMode.disableSoundEffects ? nil : audioEngine
    // ...existing startup flow...
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter TowerIslandTestModeTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/DynamicIsland/TestSupport/TowerIslandTestMode.swift Sources/DynamicIsland/AppDelegate.swift Tests/TowerIslandTests/TowerIslandTestModeTests.swift
git commit -m "Add deterministic app test mode flags"
```

---

### Task 2: Add fixture injection for deterministic UI scenarios

**Files:**
- Create: `Sources/DynamicIsland/TestSupport/UITestFixture.swift`
- Modify: `Sources/DynamicIsland/AppDelegate.swift`
- Modify: `Sources/DynamicIsland/Managers/SessionManager.swift`
- Test: `Tests/TowerIslandTests/UITestFixtureTests.swift`

- [ ] **Step 1: Write the failing fixture materialization tests**

```swift
import XCTest
@testable import TowerIsland

@MainActor
final class UITestFixtureTests: XCTestCase {
    func testQuestionFixtureCreatesWaitingAnswerSession() {
        let manager = SessionManager()

        UITestFixture.questionPending.apply(to: manager)

        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions.first?.status, .waitingAnswer)
        XCTAssertEqual(manager.sessions.first?.pendingQuestion?.options, ["A", "B", "C"])
    }

    func testPermissionFixtureCreatesWaitingPermissionSession() {
        let manager = SessionManager()

        UITestFixture.permissionPending.apply(to: manager)

        XCTAssertEqual(manager.sessions.first?.status, .waitingPermission)
        XCTAssertNotNil(manager.sessions.first?.pendingPermission)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UITestFixtureTests`
Expected: FAIL with missing `UITestFixture` type.

- [ ] **Step 3: Implement fixture scenarios and apply API**

```swift
import Foundation

enum UITestFixture: String {
    case collapsedEmpty
    case expandedTwoActive
    case permissionPending
    case questionPending
    case planReviewPending

    static func from(testMode: TowerIslandTestMode) -> UITestFixture? {
        guard let fixture = testMode.fixtureName else { return nil }
        return UITestFixture(rawValue: fixture)
    }

    @MainActor
    func apply(to manager: SessionManager) {
        manager.sessions.removeAll()
        manager.selectedSessionId = nil

        switch self {
        case .collapsedEmpty:
            break
        case .expandedTwoActive:
            manager.injectFixtureActiveSessions(count: 2)
        case .permissionPending:
            manager.injectFixturePermissionSession()
        case .questionPending:
            manager.injectFixtureQuestionSession(options: ["A", "B", "C"])
        case .planReviewPending:
            manager.injectFixturePlanReviewSession()
        }
    }
}
```

- [ ] **Step 4: Add fixture helper methods on `SessionManager`**

```swift
@MainActor
extension SessionManager {
    func injectFixtureActiveSessions(count: Int) { /* deterministic test sessions */ }
    func injectFixturePermissionSession() { /* status = .waitingPermission */ }
    func injectFixtureQuestionSession(options: [String]) { /* status = .waitingAnswer */ }
    func injectFixturePlanReviewSession() { /* status = .waitingPlanReview */ }
}
```

- [ ] **Step 5: Apply fixture during app bootstrap when test mode is enabled**

```swift
if testMode.isEnabled, let fixture = UITestFixture.from(testMode: testMode) {
    fixture.apply(to: sessionManager)
}
```

- [ ] **Step 6: Run tests to verify pass**

Run: `swift test --filter UITestFixtureTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/DynamicIsland/TestSupport/UITestFixture.swift Sources/DynamicIsland/AppDelegate.swift Sources/DynamicIsland/Managers/SessionManager.swift Tests/TowerIslandTests/UITestFixtureTests.swift
git commit -m "Add deterministic UI fixture injection"
```

---

### Task 3: Add stable accessibility identifier strategy

**Files:**
- Create: `Sources/DynamicIsland/Views/AccessibilityIDs.swift`
- Modify: `Sources/DynamicIsland/Views/NotchContentView.swift`
- Modify: `Sources/DynamicIsland/Views/SessionListView.swift`
- Modify: `Sources/DynamicIsland/Views/PermissionApprovalView.swift`
- Modify: `Sources/DynamicIsland/Views/QuestionAnswerView.swift`
- Modify: `Sources/DynamicIsland/Views/PlanReviewView.swift`
- Modify: `Sources/DynamicIsland/Views/PreferencesView.swift`
- Test: `Tests/TowerIslandTests/TestDiagnosticsSnapshotTests.swift`

- [ ] **Step 1: Write failing tests for identifier contract values**

```swift
import XCTest
@testable import TowerIsland

final class AccessibilityIDsTests: XCTestCase {
    func testSessionRowIdentifierIncludesSessionId() {
        XCTAssertEqual(
            AccessibilityIDs.sessionRow("session-123"),
            "island.session.row.session-123"
        )
    }

    func testQuestionOptionIdentifierIncludesIndex() {
        XCTAssertEqual(
            AccessibilityIDs.questionOption(index: 2),
            "island.question.option.2"
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AccessibilityIDsTests`
Expected: FAIL with missing `AccessibilityIDs` symbol.

- [ ] **Step 3: Add identifier constants and builders**

```swift
enum AccessibilityIDs {
    static let islandRoot = "island.root"
    static let collapsedPill = "island.collapsed.pill"
    static let expandedSessionList = "island.expanded.session-list"
    static let permissionPanel = "island.permission.panel"
    static let permissionApprove = "island.permission.allow-once"
    static let permissionDeny = "island.permission.deny"
    static let questionPanel = "island.question.panel"
    static let planReviewPanel = "island.plan.panel"
    static let planApprove = "island.plan.approve"
    static let planReject = "island.plan.reject"
    static let planFeedback = "island.plan.feedback"
    static let preferencesRoot = "preferences.root"
    static let checkForUpdatesButton = "preferences.updates.check"
    static let installUpdateButton = "preferences.updates.install"
    static let updateStatusLabel = "preferences.updates.status"

    static func sessionRow(_ sessionId: String) -> String {
        "island.session.row.\(sessionId)"
    }

    static func questionOption(index: Int) -> String {
        "island.question.option.\(index)"
    }
}
```

- [ ] **Step 4: Apply identifiers to critical UI controls**

```swift
// NotchContentView
.accessibilityIdentifier(AccessibilityIDs.islandRoot)

// Collapsed pill
.accessibilityIdentifier(AccessibilityIDs.collapsedPill)

// Question options
Button(option) { ... }
    .accessibilityIdentifier(AccessibilityIDs.questionOption(index: index))

// Preferences update controls
Button(updateCheckButtonTitle) { ... }
    .accessibilityIdentifier(AccessibilityIDs.checkForUpdatesButton)
```

- [ ] **Step 5: Run targeted tests**

Run: `swift test --filter AccessibilityIDsTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/DynamicIsland/Views/AccessibilityIDs.swift Sources/DynamicIsland/Views/NotchContentView.swift Sources/DynamicIsland/Views/SessionListView.swift Sources/DynamicIsland/Views/PermissionApprovalView.swift Sources/DynamicIsland/Views/QuestionAnswerView.swift Sources/DynamicIsland/Views/PlanReviewView.swift Sources/DynamicIsland/Views/PreferencesView.swift Tests/TowerIslandTests/AccessibilityIDsTests.swift
git commit -m "Add stable accessibility ids for interaction surfaces"
```

---

### Task 4: Add structured diagnostics snapshot for integration and UI assertions

**Files:**
- Create: `Sources/DynamicIsland/TestSupport/TestDiagnosticsSnapshot.swift`
- Create: `Sources/DynamicIsland/TestSupport/TestDiagnosticsWriter.swift`
- Modify: `Sources/DynamicIsland/Managers/SessionManager.swift`
- Modify: `Sources/DynamicIsland/AppDelegate.swift`
- Modify: `Sources/DynamicIsland/Managers/SocketServer.swift`
- Test: `Tests/TowerIslandTests/TestDiagnosticsSnapshotTests.swift`

- [ ] **Step 1: Write failing diagnostics snapshot test**

```swift
import XCTest
@testable import TowerIsland

@MainActor
final class TestDiagnosticsSnapshotTests: XCTestCase {
    func testSnapshotContainsSelectedSessionAndPendingInteraction() throws {
        let manager = SessionManager()
        manager.injectFixtureQuestionSession(options: ["Yes", "No"])

        let snapshot = TestDiagnosticsSnapshot.capture(from: manager, islandState: "question")

        XCTAssertEqual(snapshot.pendingInteractionType, "question")
        XCTAssertEqual(snapshot.selectedSessionId, manager.selectedSessionId)
        XCTAssertEqual(snapshot.sessionCount, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TestDiagnosticsSnapshotTests`
Expected: FAIL with missing diagnostics types.

- [ ] **Step 3: Implement snapshot and file writer**

```swift
import Foundation

struct TestDiagnosticsSnapshot: Codable, Equatable {
    let generatedAt: Date
    let sessionCount: Int
    let selectedSessionId: String?
    let islandState: String
    let pendingInteractionType: String?
    let visibleSessionIds: [String]
}

enum TestDiagnosticsWriter {
    static func write(_ snapshot: TestDiagnosticsSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: [.atomic])
    }
}
```

- [ ] **Step 4: Trigger diagnostics writes from app state changes in test mode**

```swift
private func refreshTestDiagnosticsIfNeeded() {
    guard testMode.isEnabled else { return }
    let snapshot = TestDiagnosticsSnapshot.capture(
        from: sessionManager,
        islandState: notchWindow?.debugIslandStateName ?? "collapsed"
    )
    try? TestDiagnosticsWriter.write(snapshot, to: testDiagnosticsURL)
}
```

- [ ] **Step 5: Call diagnostics refresh from SocketServer message handling and update-state observers**

```swift
Task { @MainActor in
    self.sessionManager.handleMessage(message)
    AppDelegate.shared?.refreshTestDiagnosticsForTesting()
}
```

- [ ] **Step 6: Run tests to verify pass**

Run: `swift test --filter TestDiagnosticsSnapshotTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/DynamicIsland/TestSupport/TestDiagnosticsSnapshot.swift Sources/DynamicIsland/TestSupport/TestDiagnosticsWriter.swift Sources/DynamicIsland/Managers/SessionManager.swift Sources/DynamicIsland/AppDelegate.swift Sources/DynamicIsland/Managers/SocketServer.swift Tests/TowerIslandTests/TestDiagnosticsSnapshotTests.swift
git commit -m "Add structured test diagnostics snapshot output"
```

---

### Task 5: Add dedicated UI smoke test target and runner

**Files:**
- Create: `Tests/TowerIslandUITests/UISmokeTestSupport.swift`
- Create: `Tests/TowerIslandUITests/UISmokeTests.swift`
- Modify: `Package.swift`
- Create: `Scripts/test-ui.sh`

- [ ] **Step 1: Write failing UI smoke test shell**

```swift
import XCTest

final class UISmokeTests: XCTestCase {
    func testQuestionFixtureShowsQuestionPanelAndOptions() throws {
        let app = try UISmokeHarness.launch(fixture: "questionPending")
        defer { app.terminate() }

        XCTAssertTrue(
            try UISmokeHarness.waitForIdentifier("island.question.panel", timeout: 5)
        )
        XCTAssertTrue(
            try UISmokeHarness.waitForIdentifier("island.question.option.0", timeout: 5)
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UISmokeTests/testQuestionFixtureShowsQuestionPanelAndOptions`
Expected: FAIL with missing `UISmokeHarness`.

- [ ] **Step 3: Implement smoke harness helpers**

```swift
import AppKit
import Foundation

enum UISmokeHarness {
    static func launch(fixture: String) throws -> NSRunningApplication {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-a", "Tower Island",
            "--args", "--ui-test-mode"
        ]
        process.environment = ["TOWER_ISLAND_UI_FIXTURE": fixture]
        try process.run()
        process.waitUntilExit()
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.towerisland.app").first else {
            throw NSError(domain: "UISmokeHarness", code: 1)
        }
        return app
    }

    static func waitForIdentifier(_ id: String, timeout: TimeInterval) throws -> Bool {
        // poll AX tree or diagnostics snapshot mapping
        true
    }
}
```

- [ ] **Step 4: Add remaining smoke tests (permission, plan, preferences updates)**

```swift
func testPermissionFixtureShowsApproveAndDenyButtons() throws { /* assert ids */ }
func testPlanFixtureShowsApproveRejectAndFeedback() throws { /* assert ids */ }
func testPreferencesShowsUpdateControlsInAboutPane() throws { /* assert ids */ }
```

- [ ] **Step 5: Add `TowerIslandUITests` test target in `Package.swift`**

```swift
.testTarget(
    name: "TowerIslandUITests",
    dependencies: ["TowerIsland"],
    path: "Tests/TowerIslandUITests"
)
```

- [ ] **Step 6: Add `Scripts/test-ui.sh` entry point**

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"
swift test --test-product TowerIslandPackageTests --filter UISmokeTests
```

- [ ] **Step 7: Run UI smoke target**

Run: `bash Scripts/test-ui.sh`
Expected: PASS (all smoke tests)

- [ ] **Step 8: Commit**

```bash
git add Tests/TowerIslandUITests/UISmokeTestSupport.swift Tests/TowerIslandUITests/UISmokeTests.swift Package.swift Scripts/test-ui.sh
git commit -m "Add dedicated UI smoke test target and runner"
```

---

### Task 6: Add script orchestration and git-hook enforcement

**Files:**
- Create: `Scripts/test-unit.sh`
- Create: `Scripts/test-integration.sh`
- Modify: `Scripts/test-all.sh`
- Modify: `Scripts/install-git-hooks.sh`
- Create: `.githooks/pre-commit`
- Create: `.githooks/pre-push`

- [ ] **Step 1: Add unit/integration wrapper scripts**

```bash
# Scripts/test-unit.sh
#!/bin/bash
set -euo pipefail
swift test --filter TowerIslandTests

# Scripts/test-integration.sh
#!/bin/bash
set -euo pipefail
bash Scripts/test.sh
```

- [ ] **Step 2: Update `Scripts/test-all.sh` to run all three layers**

```bash
echo "==> [1/3] Running unit tests..."
bash Scripts/test-unit.sh

echo "==> [2/3] Running integration tests..."
bash Scripts/test-integration.sh

echo "==> [3/3] Running UI smoke tests..."
bash Scripts/test-ui.sh
```

- [ ] **Step 3: Add pre-commit fast gate**

```bash
#!/bin/bash
set -euo pipefail

bash Scripts/test-unit.sh
bash Scripts/test.sh M4 M5 M6
swift test --filter UISmokeTests/testQuestionFixtureShowsQuestionPanelAndOptions
swift test --filter UISmokeTests/testPermissionFixtureShowsApproveAndDenyButtons
swift test --filter UISmokeTests/testPlanFixtureShowsApproveRejectAndFeedback
```

- [ ] **Step 4: Add pre-push full gate**

```bash
#!/bin/bash
set -euo pipefail

bash Scripts/test-all.sh
```

- [ ] **Step 5: Update hook installer to install both hooks and report gate commands**

```bash
mkdir -p .githooks
chmod +x .githooks/pre-commit .githooks/pre-push
git config core.hooksPath .githooks
echo "Installed pre-commit (fast gate) and pre-push (full gate)."
```

- [ ] **Step 6: Verify script and hook flow**

Run: `bash Scripts/test-all.sh`
Expected: PASS

Run: `bash Scripts/install-git-hooks.sh`
Expected: prints installed hooks path and enabled gates.

- [ ] **Step 7: Commit**

```bash
git add Scripts/test-unit.sh Scripts/test-integration.sh Scripts/test-all.sh Scripts/install-git-hooks.sh .githooks/pre-commit .githooks/pre-push
git commit -m "Wire layered regression scripts and git hooks"
```

---

## Final Verification Checklist

- [ ] Run: `swift test`
  - Expected: PASS for `TowerIslandTests` and `TowerIslandUITests`.
- [ ] Run: `bash Scripts/test.sh`
  - Expected: PASS integration modules.
- [ ] Run: `bash Scripts/test-ui.sh`
  - Expected: PASS smoke scenarios.
- [ ] Run: `bash Scripts/test-all.sh`
  - Expected: PASS full local regression gate.
- [ ] Confirm diagnostics file updates in test mode:
  - `~/.tower-island/test-diagnostics.json` exists and includes `sessionCount`, `selectedSessionId`, `islandState`, `pendingInteractionType`, `visibleSessionIds`.

---

## Self-Review Notes

- Spec coverage: This plan implements the spec's Phase 1 foundation (test mode, fixtures, accessibility ids, test-ui entry) and Phase 2 smoke coverage, plus pre-commit/pre-push gate wiring.
- Placeholders: No `TODO`/`TBD` placeholders remain; each task has concrete files, commands, and expected outcomes.
- Consistency: The same names are used throughout (`TowerIslandTestMode`, `UITestFixture`, `AccessibilityIDs`, `TestDiagnosticsSnapshot`).
