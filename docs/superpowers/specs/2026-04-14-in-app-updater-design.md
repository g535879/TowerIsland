# In-App Updater Design

## Goal

Add an in-app update experience that lets users discover and install new Tower Island releases from Settings, while keeping the existing CLI-based upgrade path as the underlying install mechanism.

## Scope

This design covers:

- A new update section in Settings
- A lightweight "update available" signal outside Settings
- Manual update checks against GitHub Releases
- Confirmed install flow that closes and replaces the running app
- Reuse of shared upgrade logic so the app does not depend on the user's shell `PATH`

This design does not cover:

- Background auto-download
- Release notes viewer UI
- Silent updates
- Sparkle or another full updater framework

## Product Behavior

### Settings Entry Point

Add a dedicated update section in Preferences that shows:

- Current app version
- Latest known release version
- Last check time
- Current update state
- `Check for Updates` action
- `Update Now` action when a newer version exists

### External Signal

When a newer version is available:

- Show a lightweight visual indicator in the menu bar entry
- Show a small update marker near the Settings entry point

This signal should be informative, not interruptive. No startup modal is shown in the first version.

### Install Confirmation

When the user clicks `Update Now`, show a confirmation step explaining:

- The app will close during installation
- The app bundle in `/Applications/Tower Island.app` will be replaced
- Tower Island will relaunch after the update completes

Installation proceeds only after the user confirms.

### Failure Handling

If the update fails, the Settings UI should show a human-readable error state, such as:

- Network request failed
- Unable to read release metadata
- DMG mount failed
- Installed app could not be replaced
- Relaunch failed

## Technical Design

### `UpdateManager`

Add a new manager responsible for the user-facing update state.

Responsibilities:

- Fetch latest GitHub release metadata
- Compare current version with latest release version
- Track update states
- Expose state to Settings and menu bar UI
- Trigger install flow after user confirmation

Suggested state model:

- `idle`
- `checking`
- `upToDate`
- `updateAvailable(version)`
- `installing(stage)`
- `failed(message)`

### `AppUpdater`

Extract the actual install behavior into a shared updater component used by the app.

Responsibilities:

- Download the release DMG
- Mount the DMG
- Locate `Tower Island.app`
- Replace `/Applications/Tower Island.app`
- Clear quarantine
- Relaunch the app
- Return structured success/failure state

This logic should reuse the current CLI upgrade flow conceptually, but it should be callable directly from the app without requiring `tower-island` to exist in `PATH`.

### Shared Upgrade Core

To avoid duplicated behavior between the Settings updater and the CLI updater:

- Move the release-download and install steps behind a shared abstraction
- Keep the CLI as a thin wrapper over that shared logic where feasible

If full cross-target sharing becomes too invasive in the first pass, the acceptable fallback is:

- Define one canonical implementation in app code
- Keep CLI behavior aligned with targeted tests

The important constraint is that the app update button must not shell out to `tower-island upgrade`.

## UI Placement

### Preferences

Add an `Updates` area to `PreferencesView`, likely near the version/about section.

Recommended contents:

- Version row
- Status text
- `Check for Updates` button
- `Update Now` button when available
- Inline progress or activity text during install
- Inline error text on failure

### Menu Bar Signal

Reuse existing menu bar state with a subtle update badge or label such as:

- `Update Available`
- A dot indicator near the app icon

The menu bar should not own update logic. It only reflects `UpdateManager` state.

## Data Flow

1. User opens Settings or manually taps `Check for Updates`
2. `UpdateManager` requests latest GitHub release metadata
3. `UpdateManager` compares remote version to bundled version
4. UI updates to either `Up to date` or `Update available`
5. User taps `Update Now`
6. App shows confirmation
7. On confirm, `AppUpdater` runs install stages
8. App relaunches on success, or shows error on failure

## Version Source

Use bundled values from:

- `CFBundleShortVersionString`
- `CFBundleVersion`

Release version parsing should normalize tags like `v1.2.5` into `1.2.5` before comparison.

## Error Handling Principles

- Prefer explicit user-facing messages over generic "update failed"
- Keep internal stage information available for debugging
- Never leave the UI in a permanent spinner state
- Reset back to a retryable state after failure

## Testing

### Unit / Logic Tests

Add tests for:

- Version normalization and comparison
- Release metadata parsing
- `UpdateManager` state transitions
- Install confirmation gate
- Error mapping from low-level failures to user-facing messages

### Integration / Behavior Checks

Validate:

- Settings shows current version correctly
- Update available state appears when remote version is newer
- `Update Now` is hidden when already current
- Menu bar indicator mirrors availability state
- Successful install path triggers relaunch

## Rollout Strategy

### First Version

Ship:

- Settings update section
- Manual check flow
- Confirmed install flow
- Menu bar update indicator
- Clear error states

### Later Extensions

Possible follow-ups:

- Periodic background checks
- Release notes display
- Download progress UI
- More robust shared upgrade implementation between app and CLI

## Risks

- Replacing the running app bundle while the app is active can be fragile
- GitHub networking and DMG mount failures need clear recovery
- UI state can become confusing if install stages are not explicit
- Duplicating updater logic between app and CLI would create drift if not contained

## Recommendation

Implement the updater as an app-owned feature with a shared logical upgrade pipeline, expose it in Settings, and keep the menu bar signal as a thin state reflection. This gives users a visible and understandable update path without making the app depend on shell environment details.
