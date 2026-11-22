import Foundation
import XCTest
@testable import Grav

final class EventClassifierTests: XCTestCase {
    private var tempSessionDir: URL!
    private var session: ConversationSession!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempSessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grav-classifier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempSessionDir.appendingPathComponent(".system_generated/steps/12", isDirectory: true),
            withIntermediateDirectories: true
        )
        session = ConversationSession(id: "conv-1234", directoryURL: tempSessionDir)
    }

    override func tearDownWithError() throws {
        if let tempSessionDir {
            try? FileManager.default.removeItem(at: tempSessionDir)
        }
        try super.tearDownWithError()
    }

    func testClassifiesPlannerThinkingTokensAndModel() throws {
        let jsonLine = """
        {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-22T17:07:16Z","model":"gemini-4-neon-high","input_tokens":17869,"cache_read_tokens":4200,"output_tokens":612,"thinking":"Analyzing NotchKit layout geometry."}
        """
        let step = try JSONDecoder().decode(TranscriptStep.self, from: Data(jsonLine.utf8))
        var classifier = EventClassifier()

        let out = classifier.process(step: step, session: session)
        XCTAssertEqual(out.activeModel, "gemini-4-neon-high")
        XCTAssertEqual(out.tokenMetrics.inputTokens, 17869)
        XCTAssertEqual(out.tokenMetrics.cacheReadTokens, 4200)
        XCTAssertEqual(out.tokenMetrics.outputTokens, 612)
        XCTAssertEqual(out.thinkingSnapshot?.text, "Analyzing NotchKit layout geometry.")
        XCTAssertTrue(out.peekEvents.contains(.thinkingStarted))

        // Re-processing same step_index does not double-count tokens
        let duplicate = classifier.process(step: step, session: session)
        XCTAssertEqual(duplicate.tokenMetrics.inputTokens, 17869)
    }

    func testClassifiesEditCreateOverwriteAndDeleteFileTools() {
        var classifier = EventClassifier()

        let editStep = TranscriptStep(
            stepIndex: 2,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-22T17:08:00Z",
            toolCalls: [
                ToolCall(
                    name: "edit_file",
                    args: [
                        "Path": .string("\"/Users/wica/Grav/Auth.swift\""),
                        "Target": .string("\"let a = 1\\nlet b = 2\""),
                        "Replacement": .string("\"let a = 1\\nlet b = 20\\nlet c = 30\""),
                    ]
                ),
                ToolCall(
                    name: "write_file",
                    args: [
                        "Path": .string("\"/Users/wica/Grav/NewFile.swift\""),
                        "Content": .string("\"line1\\nline2\""),
                        "Overwrite": .string("false"),
                    ]
                ),
                ToolCall(
                    name: "write_file",
                    args: [
                        "Path": .string("\"/Users/wica/Grav/Replaced.swift\""),
                        "Content": .string("\"only one line\""),
                        "Overwrite": .string("true"),
                    ]
                ),
                ToolCall(
                    name: "delete_file",
                    args: [
                        "Path": .string("\"/Users/wica/Grav/Legacy.swift\""),
                    ]
                ),
            ]
        )

        let out = classifier.process(step: editStep, session: session)
        XCTAssertEqual(out.fileChanges.count, 4)

        XCTAssertEqual(out.fileChanges[0].kind, .edit)
        XCTAssertEqual(out.fileChanges[0].basename, "Auth.swift")
        XCTAssertEqual(out.fileChanges[0].addedLines, 2)
        XCTAssertEqual(out.fileChanges[0].removedLines, 1)

        XCTAssertEqual(out.fileChanges[1].kind, .create)
        XCTAssertEqual(out.fileChanges[1].addedLines, 2)

        XCTAssertEqual(out.fileChanges[2].kind, .overwrite)
        XCTAssertEqual(out.fileChanges[2].addedLines, 1)

        XCTAssertEqual(out.fileChanges[3].kind, .delete)
        XCTAssertEqual(out.fileChanges[3].basename, "Legacy.swift")
        XCTAssertTrue(out.peekEvents.contains(.fileDeleted("Legacy.swift")))
    }

    func testClassifiesRunCommandDestructiveRmAndCorrelatesExitCodeAndStepOutput() throws {
        var classifier = EventClassifier()

        let commandStep = TranscriptStep(
            stepIndex: 11,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-22T17:09:00Z",
            toolCalls: [
                ToolCall(
                    name: "run_command",
                    args: [
                        "CommandLine": .string("\"rm -f /Users/wica/Grav/Stale.swift && swift test\""),
                        "toolSummary": .string("\"Clean stale file and run tests\""),
                    ]
                ),
            ]
        )

        let startOut = classifier.process(step: commandStep, session: session)
        XCTAssertEqual(startOut.startedCommands.count, 1)
        XCTAssertEqual(startOut.startedCommands[0].status, .running)
        XCTAssertEqual(startOut.startedCommands[0].summary, "Clean stale file and run tests")
        XCTAssertEqual(startOut.fileChanges.count, 1)
        XCTAssertEqual(startOut.fileChanges[0].kind, .delete)
        XCTAssertEqual(startOut.fileChanges[0].basename, "Stale.swift")

        // Write real step output file with ANSI codes
        let outputFile = tempSessionDir
            .appendingPathComponent(".system_generated/steps/12/output.txt")
        try "\u{1B}[31mTest Suite Failed\u{1B}[0m\nCommand exited with code 1.".write(
            to: outputFile,
            atomically: true,
            encoding: .utf8
        )

        let resultStep = TranscriptStep(
            stepIndex: 12,
            source: "MODEL",
            type: "GENERIC",
            status: "DONE",
            createdAt: "2026-11-22T17:09:05Z",
            content: "Command exited with code 1.\n\nCommand output:\n\u{1B}[31mTest Suite Failed\u{1B}[0m"
        )

        let finishOut = classifier.process(step: resultStep, session: session)
        XCTAssertEqual(finishOut.updatedCommands.count, 1)
        let finished = finishOut.updatedCommands[0]
        XCTAssertEqual(finished.status, .failed)
        XCTAssertEqual(finished.exitCode, 1)
        XCTAssertTrue(finished.logOutput.contains("Test Suite Failed"))
        XCTAssertFalse(finished.logOutput.contains("\u{1B}["))
        XCTAssertTrue(finishOut.peekEvents.contains(.commandFailed("Clean stale file and run tests", 1)))
    }
}
