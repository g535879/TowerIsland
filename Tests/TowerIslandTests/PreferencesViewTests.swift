import XCTest
@testable import TowerIsland

final class PreferencesViewTests: XCTestCase {
    func testInstallButtonHiddenWhenReleaseIsNotNewer() {
        XCTAssertFalse(
            PreferencesView.shouldShowInstallButton(
                state: .upToDate,
                latestRelease: release(version: "1.2.3")
            )
        )
    }

    func testInstallButtonShownWhenNewerReleaseIsAvailable() {
        XCTAssertTrue(
            PreferencesView.shouldShowInstallButton(
                state: .updateAvailable(version: "1.2.4"),
                latestRelease: release(version: "1.2.4")
            )
        )
    }

    private func release(version: String) -> UpdateManager.ReleaseInfo {
        UpdateManager.ReleaseInfo(
            tagName: "v\(version)",
            htmlURL: URL(string: "https://example.com/release")!,
            publishedAt: ISO8601DateFormatter().date(from: "2026-04-15T00:00:00Z")!,
            assets: [
                .init(
                    name: "TowerIsland-\(version).dmg",
                    browserDownloadURL: URL(string: "https://example.com/TowerIsland-\(version).dmg")!
                )
            ]
        )
    }
}