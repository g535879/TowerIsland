# Automated Regression Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local-first regression stack that catches UI/interaction and logic breakage before commits and before pushes.

**Architecture:** Keep the existing `swift test` and `Scripts/test.sh` strengths, then add deterministic app test mode, structured diagnostics, stable accessibility identifiers, and a package-native real-window UI driver. The repo stays shell-friendly and worktree-friendly by avoiding Xcode-only test infrastructure and using SwiftPM targets plus scripts as the execution boundary.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, XCTest, Swift Package Manager, shell scripts, macOS Accessibility APIs

---

## Planned File Structure

### Create

- `Sources/DynamicIsland/Testing/AppTestConfiguration.swift`
  Purpose: Parse launch arguments and environment variables, expose deterministic test-mode settings, and register test-safe defaults.
- `Sources/DynamicIsland/Testing/AppTestFixture.swift`
  Purpose: Define Codable fixture payloads for sessions, pending interactions, preferences, and updater state.
- `Sources/DynamicIsland/Testing/AppTestFixtureLoader.swift`
  Purpose: Load a named or file-backed fixture and seed `SessionManager` and `UpdateManager`.
- `Sources/DynamicIsland/Testing/AppDiagnosticsSnapshot.swift`
  Purpose: Define the structured state written for integration assertions.
- `Sources/DynamicIsland/Testing/AppDiagnosticsWriter.swift`
  Purpose: Persist structured snapshots in test mode after state-changing events.
- `Sources/DynamicIsland/Testing/TestAccessibility.swift`
  Purpose: Centralize accessibility identifiers used by smoke and full UI suites.
- `Sources/TowerIslandUITestDriver/main.swift`
  Purpose: Launch and drive the real app window through Accessibility APIs for smoke and full suites.
- `Sources/TowerIslandUITestDriver/AXUIHelpers.swift`
  Purpose: Wrap polling, element lookup, click, and text assertions.
- `Sources/TowerIslandUITestDriver/UITestScenarios.swift`
  Purpose: Define reusable scenarios such as `permission-smoke`, `question-smoke`, and `plan-smoke`.
- `Scripts/test-ui.sh`
  Purpose: Build the app, launch it in test mode with a named fixture, and run UI smoke or full scenarios.
- `Scripts/test-fast.sh`
  Purpose: Run the pre-commit gate: `swift test`, targeted integration modules, and the UI smoke suite.
- `Tests/TowerIslandTests/AppTestConfigurationTests.swift`
  Purpose: Lock test-mode parsing and default registration behavior.
- `Tests/TowerIslandTests/AppTestFixtureLoaderTests.swift`
  Purpose: Lock fixture decoding and seeding behavior.
- `Tests/TowerIslandTests/AppDiagnosticsSnapshotTests.swift`
  Purpose: Lock structured snapshot contents.
- `Tests/TowerIslandTests/SessionManagerInteractionTests.swift`
  Purpose: Expand regression coverage for pending interaction replacement and completion behavior.
- `Tests/TowerIslandTests/SessionVisibilityTests.swift`
  Purpose: Lock visible-session and linger behavior that drives rendering.
- `Tests/Fixtures/app/permission-smoke.json`
  Purpose: Open the app directly into a permission-review scenario.
- `Tests/Fixtures/app/question-smoke.json`
  Purpose: Open the app directly into a question-answering scenario.
- `Tests/Fixtures/app/plan-smoke.json`
  Purpose: Open the app directly into a plan-review scenario.
- `Tests/Fixtures/app/session-list.json`
  Purpose: Seed multiple active and completed sessions for list assertions.
- `Tests/Fixtures/app/update-available.json`
  Purpose: Seed Preferences into an update-available scenario.

### Modify

- `Package.swift`
  Purpose: Register new testing helper sources and the UI driver executable target.
- `Sources/DynamicIsland/AppDelegate.swift`
  Purpose: Activate test mode, optionally bypass single-instance lock, load fixtures, and wire diagnostics updates.
- `Sources/DynamicIsland/DynamicIslandApp.swift`
  Purpose: Keep app startup thin while ensuring test configuration is available early.
- `Sources/DynamicIsland/Managers/SessionManager.swift`
  Purpose: Trigger diagnostics refreshes and expose data needed by structured snapshots.
- `Sources/DynamicIsland/Managers/SocketServer.swift`
  Purpose: Refresh diagnostics after each incoming message in test mode.
- `Sources/DynamicIsland/Managers/UpdateManager.swift`
  Purpose: Support fixture seeding and diagnostics-friendly state export.
- `Sources/DynamicIsland/Views/NotchContentView.swift`
  Purpose: Add accessibility identifiers and respect deterministic test-mode behavior.
- `Sources/DynamicIsland/Views/CollapsedPillView.swift`
  Purpose: Add a stable accessibility identifier for the collapsed island.
- `Sources/DynamicIsland/Views/SessionListView.swift`
  Purpose: Tag the list container and each session card.
- `Sources/DynamicIsland/Views/PermissionApprovalView.swift`
  Purpose: Tag the container and action buttons.
- `Sources/DynamicIsland/Views/QuestionAnswerView.swift`
  Purpose: Tag the container and option buttons.
- `Sources/DynamicIsland/Views/PlanReviewView.swift`
  Purpose: Tag the container, feedback field, and action buttons.
- `Sources/DynamicIsland/Views/PreferencesView.swift`
  Purpose: Tag the root view, update controls, and about-pane signal.
- `Scripts/test-all.sh`
  Purpose: Orchestrate unit, integration, and full UI runs.
- `Scripts/test.sh`
  Purpose: Prefer structured diagnostics for state assertions while retaining low-level protocol log checks.
- `Scripts/install-git-hooks.sh`
  Purpose: Install both `pre-commit` and `pre-push` hooks without mutating git config beyond `core.hooksPath`.
- `.githooks/pre-commit`
  Purpose: Run the fast gate.
- `.githooks/pre-push`
  Purpose: Run the full gate.
- `README.md`
  Purpose: Document local testing commands and hook expectations.
- `README_zh.md`
  Purpose: Document the same workflow in Chinese.

---

### Task 1: Add Deterministic App Test Mode

**Files:**
- Create: `Sources/DynamicIsland/Testing/AppTestConfiguration.swift`
- Modify: `Sources/DynamicIsland/AppDelegate.swift`
- Modify: `Sources/DynamicIsland/DynamicIslandApp.swift`
- Modify: `Package.swift`
- Test: `Tests/TowerIslandTests/AppTestConfigurationTests.swift`

- [ ] **Step 1: Write the failing test for launch-argument parsing**

```swift
import XCTest
@testable import TowerIsland

final class AppTestConfigurationTests: XCTestCase {
    func testParsesUITestModeAndFixtureName() {
        let config = AppTestConfiguration.make(
            arguments: ["TowerIsland", "--ui-test-mode", "--fixture", "permission-smoke"],
            environment: ["TOWER_ISLAND_DISABLE_ANIMATIONS": "1"]
        )

        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.fixtureName, "permission-smoke")
        XCTAssertTrue(config.disableAnimations)
        XCTAssertTrue(config.allowsMultipleInstances)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AppTestConfigurationTests/testParsesUITestModeAndFixtureName`

Expected: FAIL with errors that `AppTestConfiguration` does not exist.

- [ ] **Step 3: Add the new test-mode model and register it in the package**

```swift
// Package.swift
.executableTarget(name: "TowerIsland", dependencies: ["DIShared"], path: "Sources/DynamicIsland"),

// Sources/DynamicIsland/Testing/AppTestConfiguration.swift
import Foundation

struct AppTestConfiguration: Equatable {
    let isEnabled: Bool
    let fixtureName: String?
    let fixturePath: String?
    let diagnosticsPath: String?
    let disableAnimations: Bool
    let allowsMultipleInstances: Bool

    static func make(arguments: [String], environment: [String: String]) -> Self {
        let isEnabled = arguments.contains("--ui-test-mode") || environment["TOWER_ISLAND_TEST_MODE"] == "1"
        let fixtureName = value(after: "--fixture", in: arguments) ?? environment["TOWER_ISLAND_TEST_FIXTURE"]
        let fixturePath = value(after: "--fixture-path", in: arguments) ?? environment["TOWER_ISLAND_TEST_FIXTURE_PATH"]
        let diagnosticsPath = environment["TOWER_ISLAND_TEST_DIAGNOSTICS_PATH"]
        let disableAnimations = environment["TOWER_ISLAND_DISABLE_ANIMATIONS"] == "1"

        return .init(
            isEnabled: isEnabled,
            fixtureName: fixtureName,
            fixturePath: fixturePath,
            diagnosticsPath: diagnosticsPath,
            disableAnimations: disableAnimations,
            allowsMultipleInstances: isEnabled
        )
    }

    static func current(processInfo: ProcessInfo = .processInfo) -> Self {
        make(arguments: processInfo.arguments, environment: processInfo.environment)
    }

    func applyDefaults(_ defaults: UserDefaults = .standard) {
        guard isEnabled else { return }
        defaults.set(true, forKey: "reduceMotion")
        defaults.set(false, forKey: "smartSuppression")
        defaults.set(false, forKey: "autoHideWhenNoActiveSessions")
        defaults.set(0.15, forKey: "autoCollapseDelay")
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
```

- [ ] **Step 4: Wire test mode into app startup**

```swift
// Sources/DynamicIsland/AppDelegate.swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let testConfiguration = AppTestConfiguration.current()

    func applicationWillFinishLaunching(_ notification: Notification) {
        if testConfiguration.allowsMultipleInstances {
            return
        }
        if !Self.acquireSingleInstanceLock() {
            Self.exitingAsDuplicateInstance = true
            Self.activateOtherInstancesOfThisApp()
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.exitingAsDuplicateInstance else { return }
        Self.shared = self
        testConfiguration.applyDefaults()
        NSApp.setActivationPolicy(.accessory)
        // existing startup continues here
    }
}
```

- [ ] **Step 5: Re-run the focused test**

Run: `swift test --filter AppTestConfigurationTests/testParsesUITestModeAndFixtureName`

Expected: PASS.

- [ ] **Step 6: Commit the deterministic test-mode foundation**

```bash
git add Package.swift Sources/DynamicIsland/Testing/AppTestConfiguration.swift Sources/DynamicIsland/AppDelegate.swift Tests/TowerIslandTests/AppTestConfigurationTests.swift
git commit -m "test: add deterministic app test mode"
```

### Task 2: Add Fixture Loading and Structured Diagnostics

**Files:**
- Create: `Sources/DynamicIsland/Testing/AppTestFixture.swift`
- Create: `Sources/DynamicIsland/Testing/AppTestFixtureLoader.swift`
- Create: `Sources/DynamicIsland/Testing/AppDiagnosticsSnapshot.swift`
- Create: `Sources/DynamicIsland/Testing/AppDiagnosticsWriter.swift`
- Modify: `Sources/DynamicIsland/AppDelegate.swift`
- Modify: `Sources/DynamicIsland/Managers/SessionManager.swift`
- Modify: `Sources/DynamicIsland/Managers/SocketServer.swift`
- Modify: `Sources/DynamicIsland/Managers/UpdateManager.swift`
- Create: `Tests/Fixtures/app/permission-smoke.json`
- Create: `Tests/Fixtures/app/question-smoke.json`
- Create: `Tests/Fixtures/app/plan-smoke.json`
- Create: `Tests/Fixtures/app/session-list.json`
- Create: `Tests/Fixtures/app/update-available.json`
- Test: `Tests/TowerIslandTests/AppTestFixtureLoaderTests.swift`
- Test: `Tests/TowerIslandTests/AppDiagnosticsSnapshotTests.swift`

- [ ] **Step 1: Write the failing fixture-loader and diagnostics tests**

```swift
import XCTest
@testable import TowerIsland

@MainActor
final class AppTestFixtureLoaderTests: XCTestCase {
    func testSeedsPermissionFixtureIntoSessionManager() throws {
        let fixtureURL = URL(fileURLWithPath: "Tests/Fixtures/app/permission-smoke.json")
        let sessionManager = SessionManager()
        let updateManager = UpdateManager()

        try AppTestFixtureLoader.load(from: fixtureURL, into: sessionManager, updateManager: updateManager)

        XCTAssertEqual(sessionManager.sessions.count, 1)
        XCTAssertEqual(sessionManager.sessions[0].status, .waitingPermission)
        XCTAssertEqual(sessionManager.sessions[0].pendingPermission?.tool, "Bash")
    }
}

@MainActor
final class AppDiagnosticsSnapshotTests: XCTestCase {
    func testSnapshotIncludesSelectedSessionAndInteractionType() {
        let manager = SessionManager()
        let updateManager = UpdateManager()
        let session = AgentSession(id: "fixture-session", agentType: .claudeCode, workingDirectory: "/tmp/demo", prompt: "Ship it")
        session.status = .waitingAnswer
        manager.sessions = [session]
        manager.selectedSessionId = session.id

        let snapshot = AppDiagnosticsSnapshot.make(sessionManager: manager, updateManager: updateManager, islandState: "question")

        XCTAssertEqual(snapshot.selectedSessionId, "fixture-session")
        XCTAssertEqual(snapshot.pendingInteraction, "question")
        XCTAssertEqual(snapshot.visibleSessions.first?.id, "fixture-session")
    }
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `swift test --filter AppTestFixtureLoaderTests && swift test --filter AppDiagnosticsSnapshotTests`

Expected: FAIL because the loader, snapshot, and fixture types do not exist.

- [ ] **Step 3: Add the fixture model, loader, and fixture files**

```swift
// Sources/DynamicIsland/Testing/AppTestFixture.swift
import Foundation

struct AppTestFixture: Decodable {
    struct SessionFixture: Decodable {
        let id: String
        let agentType: String
        let prompt: String
        let workingDirectory: String
        let status: String
        let permission: PermissionFixture?
        let question: QuestionFixture?
        let planReview: PlanFixture?
    }

    struct PermissionFixture: Decodable {
        let tool: String
        let description: String
        let filePath: String?
        let diff: String?
    }

    struct QuestionFixture: Decodable {
        let text: String
        let options: [String]
    }

    struct PlanFixture: Decodable {
        let markdown: String
    }

    struct UpdateFixture: Decodable {
        let state: String
        let latestVersion: String?
    }

    let islandState: String?
    let selectedSessionId: String?
    let sessions: [SessionFixture]
    let update: UpdateFixture?
}

// Sources/DynamicIsland/Testing/AppTestFixtureLoader.swift
import Foundation

enum AppTestFixtureLoader {
    static func load(from url: URL, into sessionManager: SessionManager, updateManager: UpdateManager) throws {
        let data = try Data(contentsOf: url)
        let fixture = try JSONDecoder().decode(AppTestFixture.self, from: data)
        sessionManager.sessions = fixture.sessions.map(makeSession)
        sessionManager.selectedSessionId = fixture.selectedSessionId
        updateManager.applyFixture(fixture.update)
    }

    private static func makeSession(_ fixture: AppTestFixture.SessionFixture) -> AgentSession {
        let agentType = AgentType.from(fixture.agentType) ?? .claudeCode
        let session = AgentSession(id: fixture.id, agentType: agentType, workingDirectory: fixture.workingDirectory, prompt: fixture.prompt)
        session.status = SessionStatus(rawValue: fixture.status) ?? .active
        if let permission = fixture.permission {
            session.pendingPermission = PendingPermission(
                requestingAgent: agentType,
                tool: permission.tool,
                description: permission.description,
                diff: permission.diff,
                filePath: permission.filePath,
                respond: { _ in }
            )
        }
        if let question = fixture.question {
            session.pendingQuestion = PendingQuestion(
                requestingAgent: agentType,
                text: question.text,
                options: question.options,
                respond: { _ in },
                cancel: nil
            )
        }
        if let plan = fixture.planReview {
            session.pendingPlanReview = PendingPlanReview(
                requestingAgent: agentType,
                markdown: plan.markdown,
                respond: { _, _ in }
            )
        }
        return session
    }
}

// Sources/DynamicIsland/Managers/UpdateManager.swift
extension UpdateManager {
    func applyFixture(_ fixture: AppTestFixture.UpdateFixture?) {
        guard let fixture else {
            latestRelease = nil
            state = .idle
            lastCheckedAt = nil
            return
        }

        if let version = fixture.latestVersion {
            latestRelease = ReleaseInfo(
                tagName: "v\(version)",
                htmlURL: URL(string: "https://example.com/releases/v\(version)")!,
                publishedAt: Date(),
                assets: [
                    .init(
                        name: "TowerIsland-\(version).dmg",
                        browserDownloadURL: URL(string: "https://example.com/TowerIsland-\(version).dmg")!
                    )
                ]
            )
        } else {
            latestRelease = nil
        }

        lastCheckedAt = Date()
        switch fixture.state {
        case "upToDate":
            state = .upToDate
        case "updateAvailable":
            state = .updateAvailable(version: fixture.latestVersion ?? currentVersion)
        case "checking":
            state = .checking
        case "installing":
            state = .installing(stage: "downloading")
        case "failed":
            state = .failed(message: "Fixture requested failure state")
        default:
            state = .idle
        }
    }
}
```

```json
// Tests/Fixtures/app/permission-smoke.json
{
  "islandState": "permission",
  "selectedSessionId": "permission-session",
  "sessions": [
    {
      "id": "permission-session",
      "agentType": "claude_code",
      "prompt": "Delete temp file",
      "workingDirectory": "/tmp/tower-island",
      "status": "waitingPermission",
      "permission": {
        "tool": "Bash",
        "description": "rm -rf /tmp/does-not-exist",
        "filePath": "/tmp/does-not-exist",
        "diff": null
      }
    }
  ],
  "update": null
}
```

- [ ] **Step 4: Add diagnostics snapshot writing and refresh hooks**

```swift
// Sources/DynamicIsland/Testing/AppDiagnosticsSnapshot.swift
import Foundation

extension SessionStatus {
    var pendingInteractionName: String? {
        switch self {
        case .waitingPermission:
            return "waitingPermission"
        case .waitingAnswer:
            return "waitingAnswer"
        case .waitingPlanReview:
            return "waitingPlanReview"
        default:
            return nil
        }
    }
}

extension UpdateManager.State {
    var debugName: String {
        switch self {
        case .idle:
            return "idle"
        case .checking:
            return "checking"
        case .upToDate:
            return "upToDate"
        case .updateAvailable:
            return "updateAvailable"
        case .installing:
            return "installing"
        case .failed:
            return "failed"
        }
    }
}

struct AppDiagnosticsSnapshot: Codable {
    struct SessionSummary: Codable {
        let id: String
        let status: String
        let title: String
    }

    let selectedSessionId: String?
    let pendingInteraction: String?
    let islandState: String
    let visibleSessions: [SessionSummary]
    let updateState: String

    static func make(sessionManager: SessionManager, updateManager: UpdateManager, islandState: String) -> Self {
        .init(
            selectedSessionId: sessionManager.selectedSessionId,
            pendingInteraction: sessionManager.selectedSession?.status.pendingInteractionName,
            islandState: islandState,
            visibleSessions: sessionManager.visibleSessions.map {
                SessionSummary(id: $0.id, status: $0.status.rawValue, title: $0.displayTitle)
            },
            updateState: updateManager.state.debugName
        )
    }
}

// Sources/DynamicIsland/Testing/AppDiagnosticsWriter.swift
import Foundation

@MainActor
final class AppDiagnosticsWriter {
    private let outputURL: URL

    init?(configuration: AppTestConfiguration) {
        guard configuration.isEnabled, let path = configuration.diagnosticsPath else { return nil }
        self.outputURL = URL(fileURLWithPath: path)
    }

    func write(sessionManager: SessionManager, updateManager: UpdateManager, islandState: String) {
        let snapshot = AppDiagnosticsSnapshot.make(sessionManager: sessionManager, updateManager: updateManager, islandState: islandState)
        let data = try? JSONEncoder().encode(snapshot)
        try? data?.write(to: outputURL)
    }
}

// Sources/DynamicIsland/AppDelegate.swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var diagnosticsWriter: AppDiagnosticsWriter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.exitingAsDuplicateInstance else { return }
        Self.shared = self
        testConfiguration.applyDefaults()
        diagnosticsWriter = AppDiagnosticsWriter(configuration: testConfiguration)
        if let fixtureURL = testFixtureURL() {
            try? AppTestFixtureLoader.load(from: fixtureURL, into: sessionManager, updateManager: updateManager)
        }
        refreshDiagnostics(islandState: "launch")
        NSApp.setActivationPolicy(.accessory)
        // existing startup continues here
    }

    func refreshDiagnostics(islandState: String) {
        diagnosticsWriter?.write(
            sessionManager: sessionManager,
            updateManager: updateManager,
            islandState: islandState
        )
    }

    private func testFixtureURL() -> URL? {
        if let explicitPath = testConfiguration.fixturePath {
            return URL(fileURLWithPath: explicitPath)
        }
        guard let fixtureName = testConfiguration.fixtureName else { return nil }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures/app/\(fixtureName).json")
    }
}
```

```swift
// Sources/DynamicIsland/Managers/SocketServer.swift
Task { @MainActor in
    self.sessionManager.handleMessage(message)
    AppDelegate.shared?.refreshDiagnostics(islandState: "message")
    diLog("[SocketServer] Sessions count: \(self.sessionManager.sessions.count)")
}
```

- [ ] **Step 5: Re-run the focused tests**

Run: `swift test --filter AppTestFixtureLoaderTests && swift test --filter AppDiagnosticsSnapshotTests`

Expected: PASS.

- [ ] **Step 6: Commit the fixture and diagnostics foundation**

```bash
git add Sources/DynamicIsland/Testing Sources/DynamicIsland/AppDelegate.swift Sources/DynamicIsland/Managers/SessionManager.swift Sources/DynamicIsland/Managers/SocketServer.swift Sources/DynamicIsland/Managers/UpdateManager.swift Tests/TowerIslandTests/AppTestFixtureLoaderTests.swift Tests/TowerIslandTests/AppDiagnosticsSnapshotTests.swift Tests/Fixtures/app
git commit -m "test: add app fixtures and structured diagnostics"
```

### Task 3: Add Stable Accessibility Identifiers to Critical UI

**Files:**
- Create: `Sources/DynamicIsland/Testing/TestAccessibility.swift`
- Modify: `Sources/DynamicIsland/Views/CollapsedPillView.swift`
- Modify: `Sources/DynamicIsland/Views/NotchContentView.swift`
- Modify: `Sources/DynamicIsland/Views/SessionListView.swift`
- Modify: `Sources/DynamicIsland/Views/PermissionApprovalView.swift`
- Modify: `Sources/DynamicIsland/Views/QuestionAnswerView.swift`
- Modify: `Sources/DynamicIsland/Views/PlanReviewView.swift`
- Modify: `Sources/DynamicIsland/Views/PreferencesView.swift`
- Test: `Tests/TowerIslandTests/PreferencesViewTests.swift`

- [ ] **Step 1: Extend an existing test so it will fail until the update controls expose stable identifiers**

```swift
import XCTest
@testable import TowerIsland

final class PreferencesViewTests: XCTestCase {
    func testUpdateAccessibilityIdentifiersStayStable() {
        XCTAssertEqual(TestAccessibility.preferencesRoot, "preferences.root")
        XCTAssertEqual(TestAccessibility.updateCheckButton, "preferences.updates.check")
        XCTAssertEqual(TestAccessibility.updateInstallButton, "preferences.updates.install")
    }
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter PreferencesViewTests/testUpdateAccessibilityIdentifiersStayStable`

Expected: FAIL because `TestAccessibility` does not exist.

- [ ] **Step 3: Add the shared identifier constants and attach them to the key views**

```swift
// Sources/DynamicIsland/Testing/TestAccessibility.swift
enum TestAccessibility {
    static let collapsedPill = "island.collapsed-pill"
    static let islandRoot = "island.root"
    static let sessionList = "island.session-list"
    static func sessionCard(_ id: String) -> String { "island.session-card.\(id)" }
    static let permissionPanel = "island.permission.panel"
    static let permissionApproveButton = "island.permission.approve"
    static let permissionDenyButton = "island.permission.deny"
    static let questionPanel = "island.question.panel"
    static func questionOption(_ index: Int) -> String { "island.question.option.\(index)" }
    static let planPanel = "island.plan.panel"
    static let planApproveButton = "island.plan.approve"
    static let planRejectButton = "island.plan.reject"
    static let planFeedbackField = "island.plan.feedback"
    static let preferencesRoot = "preferences.root"
    static let updateCheckButton = "preferences.updates.check"
    static let updateInstallButton = "preferences.updates.install"
    static let updateStatusLabel = "preferences.updates.status"
}
```

```swift
// Sources/DynamicIsland/Views/PermissionApprovalView.swift
VStack(alignment: .leading, spacing: 0) {
    header
    Divider().background(.white.opacity(0.08))
    // existing body
}
.accessibilityIdentifier(TestAccessibility.permissionPanel)

Button { /* existing action */ } label: { Text("Deny") }
    .accessibilityIdentifier(TestAccessibility.permissionDenyButton)

Button { /* existing action */ } label: { Text("Allow Once") }
    .accessibilityIdentifier(TestAccessibility.permissionApproveButton)
```

```swift
// Sources/DynamicIsland/Views/QuestionAnswerView.swift
VStack(alignment: .leading, spacing: 0) { ... }
    .accessibilityIdentifier(TestAccessibility.questionPanel)

ForEach(Array(q.options.enumerated()), id: \.offset) { index, option in
    Button { ... } label: { ... }
        .accessibilityIdentifier(TestAccessibility.questionOption(index))
}
```

```swift
// Sources/DynamicIsland/Views/PreferencesView.swift
VStack(spacing: 0) { ... }
    .accessibilityIdentifier(TestAccessibility.preferencesRoot)

Button(updateCheckButtonTitle) { ... }
    .accessibilityIdentifier(TestAccessibility.updateCheckButton)

Button(updateInstallButtonTitle) { ... }
    .accessibilityIdentifier(TestAccessibility.updateInstallButton)

Text(updateStatusText)
    .accessibilityIdentifier(TestAccessibility.updateStatusLabel)
```

- [ ] **Step 4: Re-run the focused identifier test and the existing update visibility tests**

Run: `swift test --filter PreferencesViewTests`

Expected: PASS for the existing install-button assertions and the new identifier assertion.

- [ ] **Step 5: Commit the accessibility identifier work**

```bash
git add Sources/DynamicIsland/Testing/TestAccessibility.swift Sources/DynamicIsland/Views/CollapsedPillView.swift Sources/DynamicIsland/Views/NotchContentView.swift Sources/DynamicIsland/Views/SessionListView.swift Sources/DynamicIsland/Views/PermissionApprovalView.swift Sources/DynamicIsland/Views/QuestionAnswerView.swift Sources/DynamicIsland/Views/PlanReviewView.swift Sources/DynamicIsland/Views/PreferencesView.swift Tests/TowerIslandTests/PreferencesViewTests.swift
git commit -m "test: add stable accessibility identifiers"
```

### Task 4: Build the Real-Window UI Driver and Smoke Suite

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TowerIslandUITestDriver/main.swift`
- Create: `Sources/TowerIslandUITestDriver/AXUIHelpers.swift`
- Create: `Sources/TowerIslandUITestDriver/UITestScenarios.swift`
- Create: `Scripts/test-ui.sh`
- Modify: `Scripts/build.sh`

- [ ] **Step 1: Add the package-native UI driver target and write the smoke scenario table**

```swift
// Package.swift
.executableTarget(
    name: "TowerIslandUITestDriver",
    path: "Sources/TowerIslandUITestDriver"
),
```

```swift
// Sources/TowerIslandUITestDriver/UITestScenarios.swift
enum UITestScenario: String {
    case permissionSmoke = "permission-smoke"
    case questionSmoke = "question-smoke"
    case planSmoke = "plan-smoke"
    case preferencesUpdate = "preferences-update"
    case sessionList = "session-list"

    var fixtureName: String {
        switch self {
        case .permissionSmoke: return "permission-smoke"
        case .questionSmoke: return "question-smoke"
        case .planSmoke: return "plan-smoke"
        case .preferencesUpdate: return "update-available"
        case .sessionList: return "session-list"
        }
    }
}
```

- [ ] **Step 2: Run the driver target build to verify it fails before implementation**

Run: `swift build --product TowerIslandUITestDriver`

Expected: FAIL because the source files for the target do not exist yet.

- [ ] **Step 3: Implement the AX helpers and smoke driver main entry point**

```swift
// Sources/TowerIslandUITestDriver/AXUIHelpers.swift
import AppKit
import ApplicationServices

enum AXUIHelpers {
    static func waitForRunningApp(bundleIdentifier: String, timeout: TimeInterval = 10) throws -> NSRunningApplication {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                return app
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        throw NSError(domain: "TowerIslandUITestDriver", code: 2, userInfo: [NSLocalizedDescriptionKey: "App with bundle id \(bundleIdentifier) did not launch"])
    }

    static func waitForElement(app: AXUIElement, identifier: String, timeout: TimeInterval = 5) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = findElement(app: app, identifier: identifier) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        throw NSError(domain: "TowerIslandUITestDriver", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing AX element \(identifier)"])
    }

    static func click(_ element: AXUIElement) throws {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard error == .success else {
            throw NSError(domain: "TowerIslandUITestDriver", code: Int(error.rawValue), userInfo: nil)
        }
    }

    static func findElement(app: AXUIElement, identifier: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return nil
        }

        for window in windows {
            if let match = search(element: window, identifier: identifier) {
                return match
            }
        }
        return nil
    }

    private static func search(element: AXUIElement, identifier: String) -> AXUIElement? {
        var identifierValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue) == .success,
           let current = identifierValue as? String,
           current == identifier {
            return element
        }

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let match = search(element: child, identifier: identifier) {
                    return match
                }
            }
        }
        return nil
    }
}

// Sources/TowerIslandUITestDriver/main.swift
import AppKit

@main
struct TowerIslandUITestDriver {
    static func main() throws {
        let scenario = try parseScenario()
        let appURL = URL(fileURLWithPath: ".build/Tower Island.app")
        let diagnosticsPath = FileManager.default.temporaryDirectory.appendingPathComponent("tower-island-ui-diagnostics.json")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-n", appURL.path,
            "--args",
            "--ui-test-mode",
            "--fixture", scenario.fixtureName
        ]
        process.environment = [
            "TOWER_ISLAND_TEST_MODE": "1",
            "TOWER_ISLAND_TEST_DIAGNOSTICS_PATH": diagnosticsPath.path,
            "TOWER_ISLAND_DISABLE_ANIMATIONS": "1"
        ]
        try process.run()

        let runningApp = try AXUIHelpers.waitForRunningApp(bundleIdentifier: "dev.towerisland.app")
        let axApp = AXUIElementCreateApplication(runningApp.processIdentifier)
        try runScenario(scenario, axApp: axApp)
    }

    private static func parseScenario() throws -> UITestScenario {
        guard CommandLine.arguments.count >= 2,
              let scenario = UITestScenario(rawValue: CommandLine.arguments[1]) else {
            throw NSError(domain: "TowerIslandUITestDriver", code: 3, userInfo: [NSLocalizedDescriptionKey: "Pass a scenario name"])
        }
        return scenario
    }

    private static func runScenario(_ scenario: UITestScenario, axApp: AXUIElement) throws {
        switch scenario {
        case .permissionSmoke:
            _ = try AXUIHelpers.waitForElement(app: axApp, identifier: TestAccessibility.permissionPanel)
            let allow = try AXUIHelpers.waitForElement(app: axApp, identifier: TestAccessibility.permissionApproveButton)
            try AXUIHelpers.click(allow)
        case .questionSmoke:
            _ = try AXUIHelpers.waitForElement(app: axApp, identifier: TestAccessibility.questionPanel)
            let option = try AXUIHelpers.waitForElement(app: axApp, identifier: TestAccessibility.questionOption(0))
            try AXUIHelpers.click(option)
        case .planSmoke:
            _ = try AXUIHelpers.waitForElement(app: axApp, identifier: TestAccessibility.planPanel)
            let approve = try AXUIHelpers.waitForElement(app: axApp, identifier: TestAccessibility.planApproveButton)
            try AXUIHelpers.click(approve)
        case .preferencesUpdate:
            let prefs = try AXUIHelpers.waitForElement(app: axApp, identifier: TestAccessibility.preferencesRoot)
            _ = prefs
            _ = try AXUIHelpers.waitForElement(app: axApp, identifier: TestAccessibility.updateInstallButton)
        case .sessionList:
            _ = try AXUIHelpers.waitForElement(app: axApp, identifier: TestAccessibility.sessionList)
        }
    }
}
```

- [ ] **Step 4: Add the shell wrapper for smoke and full UI runs**

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODE="${1:-smoke}"

cd "$PROJECT_DIR"
bash Scripts/build.sh >/dev/null
swift build --product TowerIslandUITestDriver >/dev/null

if [[ "$MODE" == "smoke" ]]; then
  swift run TowerIslandUITestDriver permission-smoke
  swift run TowerIslandUITestDriver question-smoke
  swift run TowerIslandUITestDriver plan-smoke
  swift run TowerIslandUITestDriver preferences-update
else
  swift run TowerIslandUITestDriver permission-smoke
  swift run TowerIslandUITestDriver question-smoke
  swift run TowerIslandUITestDriver plan-smoke
  swift run TowerIslandUITestDriver preferences-update
  swift run TowerIslandUITestDriver session-list
fi
```

- [ ] **Step 5: Run the smoke suite**

Run: `bash Scripts/test-ui.sh smoke`

Expected: PASS with four completed scenarios and no AX lookup failures.

- [ ] **Step 6: Commit the UI driver and smoke suite**

```bash
git add Package.swift Sources/TowerIslandUITestDriver Scripts/test-ui.sh Scripts/build.sh
git commit -m "test: add real-window UI smoke coverage"
```

### Task 5: Expand Logic and Integration Coverage for Shared State

**Files:**
- Create: `Tests/TowerIslandTests/SessionManagerInteractionTests.swift`
- Create: `Tests/TowerIslandTests/SessionVisibilityTests.swift`
- Modify: `Tests/TowerIslandTests/SessionManagerStatusTests.swift`
- Modify: `Scripts/test.sh`

- [ ] **Step 1: Write the failing logic tests for stale interaction replacement and visible-session expiry**

```swift
import XCTest
import DIShared
@testable import TowerIsland

@MainActor
final class SessionManagerInteractionTests: XCTestCase {
    func testSecondQuestionCancelsSupersededPendingQuestion() {
        let manager = SessionManager()
        var cancelCount = 0

        var first = DIMessage(type: .question, sessionId: "question-session")
        first.agentType = AgentType.claudeCode.rawValue
        first.questionText = "First?"
        first.options = ["A", "B"]
        manager.handleQuestionRequest(first, respond: { _ in }, cancel: { cancelCount += 1 })

        var second = DIMessage(type: .question, sessionId: "question-session")
        second.agentType = AgentType.claudeCode.rawValue
        second.questionText = "Second?"
        second.options = ["C", "D"]
        manager.handleQuestionRequest(second, respond: { _ in })

        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(manager.sessions.first?.pendingQuestion?.text, "Second?")
    }
}

@MainActor
final class SessionVisibilityTests: XCTestCase {
    func testCompletedSessionFallsOutOfVisibleSessionsAfterLinger() {
        let manager = SessionManager()
        let session = AgentSession(id: "completed", agentType: .codex)
        session.status = .completed
        session.completedAt = Date().addingTimeInterval(-180)
        manager.sessions = [session]
        UserDefaults.standard.set(10.0, forKey: "completedLingerDuration")

        XCTAssertTrue(manager.visibleSessions.isEmpty)
    }
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `swift test --filter SessionManagerInteractionTests && swift test --filter SessionVisibilityTests`

Expected: FAIL because the new test files do not exist.

- [ ] **Step 3: Add the tests and update the integration script to use structured diagnostics where state is shared**

```bash
# Scripts/test.sh
diagnostics_path() {
    printf '%s/.tower-island/test-diagnostics.json' "$HOME"
}

assert_diagnostics_field() {
    local key="$1"
    local expected="$2"
    local actual
    actual=$(/usr/bin/plutil -extract "$key" raw -o - "$(diagnostics_path)")
    if [[ "$actual" == "$expected" ]]; then
        pass "diagnostics $key == $expected"
    else
        fail "diagnostics $key expected $expected got $actual"
    fi
}

test_m4() {
    section "M4: Permission Request Flow"
    mark_log
    echo '{"tool_name":"Write","description":"Write to config.json","file_path":"/tmp/config.json"}' | \
        "$BRIDGE" --agent claude_code --hook permission &
    PERM_PID=$!
    sleep 0.5
    assert_diagnostics_field "pendingInteraction" "waitingPermission"
    kill "$PERM_PID" 2>/dev/null || true
    wait "$PERM_PID" 2>/dev/null || true
}
```

- [ ] **Step 4: Run the unit suite and the targeted integration modules**

Run: `swift test --filter SessionManager && bash Scripts/test.sh M4 M5 M6 M15 M18`

Expected: PASS with the new unit tests and targeted integration modules succeeding.

- [ ] **Step 5: Commit the shared-state regression coverage**

```bash
git add Tests/TowerIslandTests/SessionManagerInteractionTests.swift Tests/TowerIslandTests/SessionVisibilityTests.swift Tests/TowerIslandTests/SessionManagerStatusTests.swift Scripts/test.sh
git commit -m "test: cover shared interaction and visibility regressions"
```

### Task 6: Wire Fast and Full Gates Into Local Hooks and Docs

**Files:**
- Create: `Scripts/test-fast.sh`
- Modify: `Scripts/test-all.sh`
- Modify: `Scripts/install-git-hooks.sh`
- Modify: `.githooks/pre-commit`
- Create: `.githooks/pre-push`
- Modify: `README.md`
- Modify: `README_zh.md`

- [ ] **Step 1: Add the fast-gate script**

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "==> [1/3] Swift unit tests"
swift test

echo "==> [2/3] Targeted integration tests"
bash Scripts/test.sh M4 M5 M6 M15 M18

echo "==> [3/3] UI smoke tests"
bash Scripts/test-ui.sh smoke
```

- [ ] **Step 2: Update the full suite and both git hooks**

```bash
#!/bin/bash
set -euo pipefail

# Scripts/test-all.sh
echo "==> [1/3] Running Swift unit tests..."
swift test
echo "==> [2/3] Running integration tests..."
bash Scripts/test.sh
echo "==> [3/3] Running UI regression tests..."
bash Scripts/test-ui.sh full
```

```bash
#!/bin/bash
set -euo pipefail

# .githooks/pre-commit
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
echo "[pre-commit] Running fast regression gate..."
bash Scripts/test-fast.sh
```

```bash
#!/bin/bash
set -euo pipefail

# .githooks/pre-push
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
echo "[pre-push] Running full regression gate..."
bash Scripts/test-all.sh
```

- [ ] **Step 3: Update hook installation and contributor docs**

```bash
# Scripts/install-git-hooks.sh
mkdir -p .githooks
chmod +x .githooks/pre-commit .githooks/pre-push
git config core.hooksPath .githooks
echo "Git hooks installed."
echo "pre-commit runs: bash Scripts/test-fast.sh"
echo "pre-push runs:   bash Scripts/test-all.sh"
```

```md
## Testing

Fast local gate:

```bash
bash Scripts/test-fast.sh
```

Full regression suite:

```bash
bash Scripts/test-all.sh
```

Install git hooks:

```bash
bash Scripts/install-git-hooks.sh
```
```

- [ ] **Step 4: Run the fast gate, then the full gate**

Run: `bash Scripts/test-fast.sh && bash Scripts/test-all.sh`

Expected: PASS. The fast gate should finish materially faster than the full gate, and both hooks should be installable afterward with `bash Scripts/install-git-hooks.sh`.

- [ ] **Step 5: Commit the execution workflow**

```bash
git add Scripts/test-fast.sh Scripts/test-all.sh Scripts/install-git-hooks.sh .githooks/pre-commit .githooks/pre-push README.md README_zh.md
git commit -m "test: enforce fast and full local regression gates"
```

## Self-Review Checklist

- Spec coverage:
  - deterministic test mode: Task 1
  - fixture injection: Task 2
  - structured diagnostics for integration: Task 2 and Task 5
  - accessibility identifiers: Task 3
  - real-window UI automation: Task 4
  - expanded logic and integration coverage: Task 5
  - pre-commit and pre-push local gates: Task 6
- Placeholder scan:
  - No `TODO`, `TBD`, or “similar to previous task” language remains.
- Type consistency:
  - Uses `AppTestConfiguration`, `AppTestFixture`, `AppDiagnosticsSnapshot`, `TestAccessibility`, and `TowerIslandUITestDriver` consistently across tasks.
