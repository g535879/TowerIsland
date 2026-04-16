import XCTest
@testable import DIBridge

final class DIBridgeQuestionResponseTests: XCTestCase {
    func testQuestionsArrayResponseIncludesAllAnswerFields() throws {
        let stdin: [String: Any] = [
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [
                    [
                        "question": "How to proceed?",
                        "options": [
                            ["label": "Refactor"],
                            ["label": "Test"]
                        ]
                    ]
                ]
            ]
        ]

        let json = DIBridge.buildClaudeCodeQuestionResponse(answer: "Refactor", stdinData: stdin)
        let decoded = try decodeJSON(json)
        let output = try hookOutput(from: decoded)
        let updated = try updatedInput(from: output)

        XCTAssertEqual(output["permissionDecision"] as? String, "allow")
        XCTAssertEqual(updated["answer"] as? String, "Refactor")

        let answers = try XCTUnwrap(updated["answers"] as? [String: String])
        XCTAssertEqual(answers["How to proceed?"], "Refactor")

        let questions = try XCTUnwrap(updated["questions"] as? [[String: Any]])
        XCTAssertEqual(questions.first?["answer"] as? String, "Refactor")
        let perQuestionAnswers = try XCTUnwrap(questions.first?["answers"] as? [String])
        XCTAssertEqual(perQuestionAnswers.first, "Refactor")
    }

    func testSingleQuestionResponseIncludesAnswerAndAnswerMap() throws {
        let stdin: [String: Any] = [
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "question": "Continue?",
                "options": ["yes", "no"]
            ]
        ]

        let json = DIBridge.buildClaudeCodeQuestionResponse(answer: "yes", stdinData: stdin)
        let decoded = try decodeJSON(json)
        let output = try hookOutput(from: decoded)
        let updated = try updatedInput(from: output)

        XCTAssertEqual(updated["answer"] as? String, "yes")
        let answers = try XCTUnwrap(updated["answers"] as? [String: String])
        XCTAssertEqual(answers["Continue?"], "yes")
    }

    func testClaudePermissionResponseStdoutUsesDecisionBehavior() throws {
        let allowJson = DIBridge.buildClaudeCodePermissionResponse(approved: true)
        let denyJson = DIBridge.buildClaudeCodePermissionResponse(approved: false)

        let allowRoot = try decodeJSON(allowJson)
        let denyRoot = try decodeJSON(denyJson)
        let allowOut = try hookOutput(from: allowRoot)
        let denyOut = try hookOutput(from: denyRoot)

        XCTAssertEqual(allowOut["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual(denyOut["hookEventName"] as? String, "PermissionRequest")

        let allowDecision = try XCTUnwrap(allowOut["decision"] as? [String: Any])
        let denyDecision = try XCTUnwrap(denyOut["decision"] as? [String: Any])
        XCTAssertEqual(allowDecision["behavior"] as? String, "allow")
        XCTAssertEqual(denyDecision["behavior"] as? String, "deny")
    }

    func testPermissionHookUsesPermissionRequestEventName() throws {
        let stdin: [String: Any] = [
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "question": "Continue?",
                "options": ["yes", "no"]
            ]
        ]

        let json = DIBridge.buildClaudeCodeQuestionResponse(
            answer: "yes",
            stdinData: stdin,
            hookType: "PermissionRequest"
        )
        let decoded = try decodeJSON(json)
        let output = try hookOutput(from: decoded)

        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
    }

    private func decodeJSON(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func hookOutput(from root: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
    }

    private func updatedInput(from hookOutput: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(hookOutput["updatedInput"] as? [String: Any])
    }
}
