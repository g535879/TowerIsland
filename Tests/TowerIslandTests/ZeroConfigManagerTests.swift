import XCTest
@testable import TowerIsland

final class ZeroConfigManagerTests: XCTestCase {
    func testSanitizeCursorHooksRemovesLegacyClaudeAndOldBridgeEntries() throws {
        let config: [String: Any] = [
            "dynamic_island": "/Users/test/.dynamic-island/bin/di-bridge --agent cursor",
            "hooks": [
                "beforeSubmitPrompt": [
                    ["command": "python3 ~/.claude/hooks/codeisland-state.py --agent cursor --hook UserPromptSubmit"],
                    ["command": "/Users/test/.tower-island/bin/di-bridge --agent cursor --hook session_start"]
                ],
                "preToolUse": [
                    ["command": "/Users/test/.dynamic-island/bin/di-bridge --agent cursor --hook PreToolUse"],
                    ["command": "python3 ~/.claude/hooks/codeisland-state.py --agent cursor --hook PreToolUse"]
                ]
            ],
            "version": 1
        ]

        let sanitized = ZeroConfigManager.sanitizeCursorConfig(
            config,
            bridgePath: "/Users/test/.tower-island/bin/di-bridge"
        )
        let hooks = try XCTUnwrap(sanitized["hooks"] as? [String: Any])
        let beforeSubmit = try XCTUnwrap(hooks["beforeSubmitPrompt"] as? [[String: Any]])
        let preToolUse = try XCTUnwrap(hooks["preToolUse"] as? [[String: Any]])

        XCTAssertFalse(
            beforeSubmit.contains { ($0["command"] as? String)?.contains("codeisland-state.py") == true }
        )
        XCTAssertEqual(
            beforeSubmit.filter { ($0["command"] as? String)?.contains("di-bridge") == true }.count,
            1
        )
        XCTAssertTrue(preToolUse.isEmpty)
        XCTAssertNil(sanitized["dynamic_island"])
    }
}
