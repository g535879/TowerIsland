# About Update Install Button Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide the `Install <version>` action in About/Preferences when the checked release is not newer than the current app version.

**Architecture:** Keep the change in the existing `PreferencesView` update section. Tighten the install-button visibility rule so the button appears only when `UpdateManager` indicates a newer release is available, while preserving the existing `Check for Updates` action and install flow for real updates.

**Tech Stack:** Swift, SwiftUI, XCTest

---

### Task 1: Restrict install button visibility to newer releases

**Files:**
- Modify: `Sources/DynamicIsland/Views/PreferencesView.swift`
- Test: `Tests/TowerIslandTests/PreferencesViewTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
func testInstallButtonVisibilityRequiresNewerRelease() throws {
    let manager = UpdateManager()
    let currentVersion = manager.currentVersion
    let sameRelease = UpdateManager.ReleaseInfo(
        tagName: "v\(currentVersion)",
        htmlURL: URL(string: "https://example.com/release")!,
        publishedAt: ISO8601DateFormatter().date(from: "2026-04-15T00:00:00Z")!,
        assets: [
            .init(
                name: "TowerIsland-\(currentVersion).dmg",
                browserDownloadURL: URL(string: "https://example.com/TowerIsland-\(currentVersion).dmg")!
            )
        ]
    )
    manager.latestRelease = sameRelease
    manager.state = .upToDate

    let view = PreferencesView().environmentObject(manager)

    XCTAssertFalse(view.inspectableCanInstallUpdate)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PreferencesViewTests/testInstallButtonVisibilityRequiresNewerRelease`
Expected: FAIL because the current visibility helper still returns `true` for any DMG-backed release.

- [ ] **Step 3: Write minimal implementation**

```swift
private var canInstallUpdate: Bool {
    hasUpdateAvailable && updateManager.latestRelease?.dmgURL != nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PreferencesViewTests/testInstallButtonVisibilityRequiresNewerRelease`
Expected: PASS

- [ ] **Step 5: Run focused regression coverage**

Run: `swift test --filter UpdateManagerTests`
Expected: PASS