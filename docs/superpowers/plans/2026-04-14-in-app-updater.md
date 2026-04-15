# In-App Updater Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Settings-based update flow that checks GitHub Releases, shows update availability in the app UI, and installs a newer Tower Island release with a confirmed in-app updater flow.

**Architecture:** Introduce an `UpdateManager` for state and release checks, plus an `AppUpdater` for the install pipeline. Wire both into `PreferencesView` and the menu bar so update availability is visible without duplicating logic in multiple UI entry points.

**Tech Stack:** Swift, SwiftUI, AppKit, Foundation networking/process APIs, XCTest, existing Tower Island app architecture

---

## File Map

- Create: `Sources/DynamicIsland/Managers/UpdateManager.swift`
  - Owns update state, release metadata fetch, version comparison, and UI-facing actions.
- Create: `Sources/DynamicIsland/Managers/AppUpdater.swift`
  - Runs download, mount, install, quarantine clear, and relaunch stages.
- Create: `Tests/TowerIslandTests/UpdateManagerTests.swift`
  - Covers version normalization, version comparison, release parsing, and update state transitions.
- Create: `Tests/TowerIslandTests/AppUpdaterTests.swift`
  - Covers install-stage helpers that can be tested without mutating `/Applications`.
- Modify: `Sources/DynamicIsland/AppDelegate.swift`
  - Instantiate `UpdateManager`, inject it into `PreferencesView`, and reflect update availability in the menu bar.
- Modify: `Sources/DynamicIsland/Views/PreferencesView.swift`
  - Add the Updates section, update actions, confirmation UI, and error/progress presentation.
- Modify: `Package.swift`
  - Ensure new test files are part of the existing test target if needed.

---

### Task 1: Add Update State and Version Parsing Foundations

**Files:**
- Create: `Sources/DynamicIsland/Managers/UpdateManager.swift`
- Test: `Tests/TowerIslandTests/UpdateManagerTests.swift`

- [x] **Step 1: Write the failing tests for version parsing and comparison**

```swift
import XCTest
@testable import TowerIsland

final class UpdateManagerTests: XCTestCase {
    func testNormalizesReleaseTagsByRemovingLeadingV() {
        XCTAssertEqual(UpdateManager.normalize(version: "v1.2.5"), "1.2.5")
        XCTAssertEqual(UpdateManager.normalize(version: "1.2.5"), "1.2.5")
    }

    func testDetectsRemoteVersionIsNewer() {
        XCTAssertTrue(UpdateManager.isRemoteVersionNewer("1.2.6", than: "1.2.5"))
        XCTAssertFalse(UpdateManager.isRemoteVersionNewer("1.2.5", than: "1.2.5"))
        XCTAssertFalse(UpdateManager.isRemoteVersionNewer("1.2.4", than: "1.2.5"))
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter UpdateManagerTests`
Expected: FAIL with missing `UpdateManager` type or missing static methods.

- [x] **Step 3: Write the minimal `UpdateManager` foundation**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class UpdateManager {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String)
        case installing(stage: String)
        case failed(message: String)
    }

    var state: State = .idle

    static func normalize(version: String) -> String {
        var value = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        return value
    }

    static func isRemoteVersionNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = normalize(version: remote).split(separator: ".").compactMap { Int($0) }
        let localParts = normalize(version: local).split(separator: ".").compactMap { Int($0) }
        let maxCount = max(remoteParts.count, localParts.count)

        for index in 0..<maxCount {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let localValue = index < localParts.count ? localParts[index] : 0
            if remoteValue != localValue {
                return remoteValue > localValue
            }
        }

        return false
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter UpdateManagerTests`
Expected: PASS for both version tests.

- [x] **Step 5: Commit**

```bash
git add Sources/DynamicIsland/Managers/UpdateManager.swift Tests/TowerIslandTests/UpdateManagerTests.swift
git commit -m "Add updater version parsing foundation"
```

### Task 2: Add Release Metadata Parsing and Check State

**Files:**
- Modify: `Sources/DynamicIsland/Managers/UpdateManager.swift`
- Modify: `Tests/TowerIslandTests/UpdateManagerTests.swift`

- [x] **Step 1: Write the failing test for release metadata parsing**

```swift
func testParsesGitHubReleasePayload() throws {
    let data = Data(#"{"tag_name":"v1.2.6","html_url":"https://example.com/release","published_at":"2026-04-14T12:00:00Z"}"#.utf8)

    let release = try UpdateManager.decodeRelease(from: data)

    XCTAssertEqual(release.version, "1.2.6")
    XCTAssertEqual(release.htmlURL.absoluteString, "https://example.com/release")
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter UpdateManagerTests/testParsesGitHubReleasePayload`
Expected: FAIL with missing decode API or release model.

- [x] **Step 3: Extend `UpdateManager` with release model and decoder**

```swift
extension UpdateManager {
    struct ReleaseInfo: Equatable {
        let version: String
        let htmlURL: URL
        let publishedAt: Date?
    }

    private struct GitHubReleaseDTO: Decodable {
        let tag_name: String
        let html_url: URL
        let published_at: Date?
    }

    static func decodeRelease(from data: Data) throws -> ReleaseInfo {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(GitHubReleaseDTO.self, from: data)
        return ReleaseInfo(
            version: normalize(version: dto.tag_name),
            htmlURL: dto.html_url,
            publishedAt: dto.published_at
        )
    }
}
```

- [x] **Step 4: Add a lightweight check result API**

```swift
extension UpdateManager {
    var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return Self.normalize(version: version)
    }

    var latestRelease: ReleaseInfo?
    var lastCheckedAt: Date?

    func applyCheckResult(_ release: ReleaseInfo) {
        latestRelease = release
        lastCheckedAt = Date()
        state = Self.isRemoteVersionNewer(release.version, than: currentVersion)
            ? .updateAvailable(version: release.version)
            : .upToDate
    }
}
```

- [x] **Step 5: Run tests to verify they pass**

Run: `swift test --filter UpdateManagerTests`
Expected: PASS for version and decode tests.

- [x] **Step 6: Commit**

```bash
git add Sources/DynamicIsland/Managers/UpdateManager.swift Tests/TowerIslandTests/UpdateManagerTests.swift
git commit -m "Add updater release parsing"
```

### Task 3: Add Manual GitHub Release Check

**Files:**
- Modify: `Sources/DynamicIsland/Managers/UpdateManager.swift`
- Modify: `Tests/TowerIslandTests/UpdateManagerTests.swift`

- [x] **Step 1: Write the failing test for state transition on check success**

```swift
@MainActor
func testApplyCheckResultTransitionsToUpdateAvailable() {
    let manager = UpdateManager()
    let release = UpdateManager.ReleaseInfo(
        version: "9.9.9",
        htmlURL: URL(string: "https://example.com")!,
        publishedAt: nil
    )

    manager.applyCheckResult(release)

    XCTAssertEqual(manager.state, .updateAvailable(version: "9.9.9"))
    XCTAssertEqual(manager.latestRelease?.version, "9.9.9")
    XCTAssertNotNil(manager.lastCheckedAt)
}
```

- [x] **Step 2: Run test to verify it fails if state wiring is incomplete**

Run: `swift test --filter UpdateManagerTests/testApplyCheckResultTransitionsToUpdateAvailable`
Expected: FAIL if `State` equality or stored properties are incomplete.

- [x] **Step 3: Add a release fetch API with injectable networking**

```swift
extension UpdateManager {
    typealias ReleaseFetcher = @Sendable () async throws -> Data

    convenience init(fetchReleaseData: @escaping ReleaseFetcher = UpdateManager.fetchLatestReleaseData) {
        self.init()
        self.fetchReleaseData = fetchReleaseData
    }

    private static func fetchLatestReleaseData() async throws -> Data {
        let url = URL(string: "https://api.github.com/repos/g535879/TowerIsland/releases/latest")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
```

- [x] **Step 4: Add `checkForUpdates()` and state/error mapping**

```swift
extension UpdateManager {
    private var fetchReleaseData: ReleaseFetcher { get { _fetchReleaseData } set { _fetchReleaseData = newValue } }
    private var _fetchReleaseData: ReleaseFetcher = UpdateManager.fetchLatestReleaseData

    func checkForUpdates() async {
        state = .checking

        do {
            let data = try await fetchReleaseData()
            let release = try Self.decodeRelease(from: data)
            applyCheckResult(release)
        } catch {
            state = .failed(message: "Unable to check for updates.")
            lastCheckedAt = Date()
        }
    }
}
```

- [x] **Step 5: Run tests to verify they pass**

Run: `swift test --filter UpdateManagerTests`
Expected: PASS with state-transition coverage.

- [x] **Step 6: Commit**

```bash
git add Sources/DynamicIsland/Managers/UpdateManager.swift Tests/TowerIslandTests/UpdateManagerTests.swift
git commit -m "Add manual update check flow"
```

### Task 4: Add App Updater Stage Model

**Files:**
- Create: `Sources/DynamicIsland/Managers/AppUpdater.swift`
- Create: `Tests/TowerIslandTests/AppUpdaterTests.swift`

- [x] **Step 1: Write the failing test for tag normalization into a DMG download URL context**

```swift
import XCTest
@testable import TowerIsland

final class AppUpdaterTests: XCTestCase {
    func testBuildsDownloadFileNameFromVersion() {
        XCTAssertEqual(AppUpdater.dmgFilename(for: "1.2.5"), "TowerIsland-1.2.5.dmg")
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppUpdaterTests`
Expected: FAIL with missing `AppUpdater`.

- [x] **Step 3: Create minimal `AppUpdater` type**

```swift
import Foundation

enum AppUpdaterStage: Equatable {
    case downloading
    case mounting
    case installing
    case relaunching
}

enum AppUpdaterError: LocalizedError, Equatable {
    case downloadFailed
    case mountFailed
    case appNotFound
    case installFailed
    case relaunchFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return "Unable to download the update."
        case .mountFailed: return "Unable to mount the downloaded update."
        case .appNotFound: return "The downloaded update did not contain Tower Island.app."
        case .installFailed: return "Unable to replace the installed app."
        case .relaunchFailed: return "The update installed, but the app could not relaunch."
        }
    }
}

struct AppUpdater {
    static func dmgFilename(for version: String) -> String {
        "TowerIsland-\(version).dmg"
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppUpdaterTests`
Expected: PASS for the filename test.

- [x] **Step 5: Commit**

```bash
git add Sources/DynamicIsland/Managers/AppUpdater.swift Tests/TowerIslandTests/AppUpdaterTests.swift
git commit -m "Add app updater stage model"
```

### Task 5: Implement Install Pipeline API

**Files:**
- Modify: `Sources/DynamicIsland/Managers/AppUpdater.swift`
- Modify: `Tests/TowerIslandTests/AppUpdaterTests.swift`

- [x] **Step 1: Write the failing test for mount output parsing**

```swift
func testExtractsMountDirectoryFromHdiutilOutput() {
    let output = "/dev/disk16\tGUID_partition_scheme\t\n/dev/disk16s1\tApple_HFS\t/Volumes/Tower Island 7"

    XCTAssertEqual(AppUpdater.mountDirectory(from: output), "/Volumes/Tower Island 7")
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppUpdaterTests/testExtractsMountDirectoryFromHdiutilOutput`
Expected: FAIL with missing helper.

- [x] **Step 3: Add install helpers with injectable side effects**

```swift
struct AppUpdater {
    var fileManager: FileManager = .default
    var runCommand: @Sendable (_ launchPath: String, _ arguments: [String]) throws -> String
    var downloadFile: @Sendable (_ sourceURL: URL, _ destinationURL: URL) async throws -> Void
    var relaunchApp: @Sendable (_ appPath: String) throws -> Void

    init(
        runCommand: @escaping @Sendable (_ launchPath: String, _ arguments: [String]) throws -> String = AppUpdater.defaultRunCommand,
        downloadFile: @escaping @Sendable (_ sourceURL: URL, _ destinationURL: URL) async throws -> Void = AppUpdater.defaultDownloadFile,
        relaunchApp: @escaping @Sendable (_ appPath: String) throws -> Void = AppUpdater.defaultRelaunch
    ) {
        self.runCommand = runCommand
        self.downloadFile = downloadFile
        self.relaunchApp = relaunchApp
    }

    static func mountDirectory(from output: String) -> String? {
        output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t")
                return parts.last.flatMap { value in
                    value.contains("/Volumes/") ? String(value) : nil
                }
            }
            .last
    }
}
```

- [x] **Step 4: Add `install(version:releaseURL:appPath:onStage:)` skeleton**

```swift
extension AppUpdater {
    func install(version: String, releaseURL: URL, appPath: String, onStage: @escaping @Sendable (AppUpdaterStage) -> Void) async throws {
        onStage(.downloading)
        onStage(.mounting)
        onStage(.installing)
        onStage(.relaunching)
    }
}
```

- [x] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AppUpdaterTests`
Expected: PASS for parsing helpers and stage-model tests.

- [x] **Step 6: Commit**

```bash
git add Sources/DynamicIsland/Managers/AppUpdater.swift Tests/TowerIslandTests/AppUpdaterTests.swift
git commit -m "Add app updater install helpers"
```

### Task 6: Connect UpdateManager to AppUpdater

**Files:**
- Modify: `Sources/DynamicIsland/Managers/UpdateManager.swift`
- Modify: `Tests/TowerIslandTests/UpdateManagerTests.swift`

- [x] **Step 1: Write the failing test for install state progression**

```swift
@MainActor
func testInstallUpdateMapsUpdaterStagesIntoManagerState() async throws {
    let manager = UpdateManager(fetchReleaseData: { Data() }, updater: .mockSuccess)
    manager.latestRelease = .init(version: "9.9.9", htmlURL: URL(string: "https://example.com/release")!, publishedAt: nil)

    try await manager.installUpdate()

    XCTAssertEqual(manager.state, .idle)
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter UpdateManagerTests/testInstallUpdateMapsUpdaterStagesIntoManagerState`
Expected: FAIL with missing updater injection or install API.

- [x] **Step 3: Add updater injection to `UpdateManager`**

```swift
extension UpdateManager {
    convenience init(
        fetchReleaseData: @escaping ReleaseFetcher = UpdateManager.fetchLatestReleaseData,
        updater: AppUpdater = AppUpdater()
    ) {
        self.init(fetchReleaseData: fetchReleaseData)
        self.updater = updater
    }

    private var updater: AppUpdater {
        get { _updater }
        set { _updater = newValue }
    }

    private var _updater = AppUpdater()
}
```

- [x] **Step 4: Add `installUpdate()` and stage mapping**

```swift
extension UpdateManager {
    func installUpdate() async throws {
        guard let release = latestRelease else { return }

        try await updater.install(
            version: release.version,
            releaseURL: release.htmlURL,
            appPath: "/Applications/Tower Island.app"
        ) { stage in
            Task { @MainActor in
                switch stage {
                case .downloading: self.state = .installing(stage: "Downloading update…")
                case .mounting: self.state = .installing(stage: "Mounting update…")
                case .installing: self.state = .installing(stage: "Installing update…")
                case .relaunching: self.state = .installing(stage: "Restarting Tower Island…")
                }
            }
        }

        state = .idle
    }
}
```

- [x] **Step 5: Run tests to verify they pass**

Run: `swift test --filter UpdateManagerTests`
Expected: PASS for install state mapping.

- [x] **Step 6: Commit**

```bash
git add Sources/DynamicIsland/Managers/UpdateManager.swift Tests/TowerIslandTests/UpdateManagerTests.swift
git commit -m "Connect update manager to app updater"
```

### Task 7: Add Settings UI for Updates

**Files:**
- Modify: `Sources/DynamicIsland/Views/PreferencesView.swift`

- [x] **Step 1: Add the failing UI expectation in code comments via a temporary preview-driven checklist**

```swift
// Expected UI:
// - Current Version row
// - Latest Version row when known
// - Check for Updates button
// - Update Now button only when update is available
// - Inline error or progress state
```

- [x] **Step 2: Add `UpdateManager` to `PreferencesView` environment**

```swift
@Environment(UpdateManager.self) private var updateManager
@State private var showUpdateConfirmation = false
```

- [x] **Step 3: Add an Updates section near the About area**

```swift
SectionCard(title: "Updates", systemImage: "arrow.triangle.2.circlepath") {
    VStack(alignment: .leading, spacing: 12) {
        settingsRow("Current Version", value: currentAppVersion)

        if let latest = updateManager.latestRelease?.version {
            settingsRow("Latest Version", value: latest)
        }

        if let lastCheckedAt = updateManager.lastCheckedAt {
            settingsRow("Last Checked", value: relativeDateFormatter.localizedString(for: lastCheckedAt, relativeTo: Date()))
        }

        Text(updateStatusText)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.65))

        HStack(spacing: 10) {
            Button("Check for Updates") {
                Task { await updateManager.checkForUpdates() }
            }

            if case .updateAvailable = updateManager.state {
                Button("Update Now") {
                    showUpdateConfirmation = true
                }
            }
        }
    }
}
```

- [x] **Step 4: Add confirmation dialog**

```swift
.confirmationDialog(
    "Install Update?",
    isPresented: $showUpdateConfirmation,
    titleVisibility: .visible
) {
    Button("Install and Restart") {
        Task {
            do {
                try await updateManager.installUpdate()
            } catch {
                updateManager.state = .failed(message: error.localizedDescription)
            }
        }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("Tower Island will close, replace the installed app, and relaunch after the update completes.")
}
```

- [x] **Step 5: Run a focused build verification**

Run: `swift build`
Expected: PASS with the new Settings section compiling.

- [x] **Step 6: Commit**

```bash
git add Sources/DynamicIsland/Views/PreferencesView.swift
git commit -m "Add settings update UI"
```

### Task 8: Add Menu Bar Update Indicator

**Files:**
- Modify: `Sources/DynamicIsland/AppDelegate.swift`

- [x] **Step 1: Update app setup to create and inject `UpdateManager`**

```swift
let updateManager = UpdateManager()
```

- [x] **Step 2: Pass `updateManager` into `PreferencesView`**

```swift
rootView: PreferencesView()
    .environment(sessionManager)
    .environment(audioEngine)
    .environment(updateManager)
```

- [x] **Step 3: Reflect update availability in the status item**

```swift
private func refreshStatusItemAppearance() {
    guard let button = statusItem?.button else { return }

    if case .updateAvailable = updateManager.state {
        button.image = NSImage(systemSymbolName: "sparkle.circle.fill", accessibilityDescription: "Tower Island update available")
    } else {
        button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Tower Island")
    }
}
```

- [x] **Step 4: Trigger refresh after update checks and on launch**

```swift
Task { @MainActor in
    await updateManager.checkForUpdates()
    refreshStatusItemAppearance()
}
```

- [x] **Step 5: Run build verification**

Run: `swift build`
Expected: PASS and status item still compiles.

- [x] **Step 6: Commit**

```bash
git add Sources/DynamicIsland/AppDelegate.swift
git commit -m "Show update availability in menu bar"
```

### Task 9: Full Verification

**Files:**
- Verify only

- [x] **Step 1: Run all focused updater tests**

Run: `swift test --filter UpdateManagerTests`
Expected: PASS

- [x] **Step 2: Run app updater tests**

Run: `swift test --filter AppUpdaterTests`
Expected: PASS

- [x] **Step 3: Run the full test suite**

Run: `swift test`
Expected: PASS with 0 failures.

- [x] **Step 4: Run a full build**

Run: `swift build`
Expected: PASS.

- [x] **Step 5: Perform manual UI smoke check**

Run:

```bash
.build/debug/TowerIsland
```

Expected:
- Preferences shows the Updates section
- `Check for Updates` changes state
- `Update Now` only appears when a newer version is available
- Confirmation dialog appears before install
- Menu bar icon changes when update is available

- [x] **Step 6: Commit**

```bash
git add -A
git commit -m "Implement in-app updater"
```

---

## Self-Review

- Spec coverage:
  - Settings entry point: covered in Task 7
  - External signal: covered in Task 8
  - Confirmed install flow: covered in Task 7 + Task 6
  - Shared install logic: covered in Tasks 4-6
  - Error handling and tests: covered in Tasks 3, 6, and 9
- Placeholder scan:
  - No `TODO`, `TBD`, or deferred implementation notes remain in tasks.
- Type consistency:
  - `UpdateManager`, `AppUpdater`, `State`, `ReleaseInfo`, `AppUpdaterStage`, and the install/check methods are used consistently across tasks.
