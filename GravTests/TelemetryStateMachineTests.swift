import Foundation
import XCTest
@testable import Grav

final class TelemetryStateMachineTests: XCTestCase {
    func testStateTransitionsIdleThinkingEditingRunningCommandIdle() {
        var classifier = EventClassifier()
        XCTAssertEqual(classifier.state, .idle)

        // 1. Thinking begins
        let thinkStep = TranscriptStep(
            stepIndex: 1,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "RUNNING",
            createdAt: "2026-11-22T17:10:00Z",
            thinking: "Planning edits..."
        )
        let thinkOut = classifier.process(step: thinkStep)
        XCTAssertEqual(thinkOut.state, .thinking)
        XCTAssertTrue(thinkOut.peekEvents.contains(.thinkingStarted))

        // 2. File edit transitions state to .editing
        let editStep = TranscriptStep(
            stepIndex: 2,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-22T17:10:02Z",
            toolCalls: [
                ToolCall(
                    name: "edit_file",
                    args: [
                        "Path": .string("\"/Users/wica/Grav/Model.swift\""),
                        "Target": .string("\"var x = 1\""),
                        "Replacement": .string("\"var x = 2\""),
                    ]
                ),
            ]
        )
        let editOut = classifier.process(step: editStep)
        if case let .editing(event) = editOut.state {
            XCTAssertEqual(event.basename, "Model.swift")
        } else {
            XCTFail("Expected .editing state, got \(editOut.state)")
        }

        // 3. Running command transitions state to .runningCommand
        let cmdStep = TranscriptStep(
            stepIndex: 3,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-22T17:10:04Z",
            toolCalls: [
                ToolCall(
                    name: "run_command",
                    args: [
                        "CommandLine": .string("\"swift build\""),
                        "toolSummary": .string("\"Build project\""),
                    ]
                ),
            ]
        )
        let cmdStart = classifier.process(step: cmdStep)
        if case let .runningCommand(event) = cmdStart.state {
            XCTAssertEqual(event.summary, "Build project")
        } else {
            XCTFail("Expected .runningCommand state, got \(cmdStart.state)")
        }

        // 4. Command succeeds -> returns cleanly to idle via final response / idle mark
        let cmdFinish = TranscriptStep(
            stepIndex: 4,
            source: "MODEL",
            type: "GENERIC",
            status: "DONE",
            createdAt: "2026-11-22T17:10:09Z",
            content: "Command exited with code 0.\n\nCommand output:\nBuild complete!"
        )
        let finishOut = classifier.process(step: cmdFinish)
        XCTAssertEqual(finishOut.updatedCommands.first?.status, .succeeded)
        XCTAssertTrue(finishOut.peekEvents.contains(.commandCompleted("Build project", 0)))

        classifier.markIdle()
        XCTAssertEqual(classifier.state, .idle)
    }

    @MainActor
    func testStoreEndToEndIngestionAndPauseResume() async throws {
        let rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grav-store-\(UUID().uuidString)", isDirectory: true)
        let convDir = rootDir.appendingPathComponent("52834bd5-test-conv", isDirectory: true)
        let logsDir = convDir.appendingPathComponent(".system_generated/logs", isDirectory: true)
        let tasksDir = convDir.appendingPathComponent(".system_generated/tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let transcriptURL = logsDir.appendingPathComponent("transcript.jsonl")
        let fullTranscriptURL = logsDir.appendingPathComponent("transcript_full.jsonl")
        let taskLogURL = tasksDir.appendingPathComponent("task-5.log")

        let transcript =
            #"{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-11-22T17:10:00Z","content":"<USER_REQUEST>\nVerify Grav Telemetry\n</USER_REQUEST>"}"# + "\n" +
            #"{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-22T17:10:01Z","model":"gemini-4-neon-high","input_tokens":500,"output_tokens":120,"thinking":"Short preview...","truncated_fields":["thinking"],"tool_calls":[{"name":"run_command","args":{"CommandLine":"\"xcodebuild test\"","toolSummary":"\"Run test suite\""}}]}"# + "\n"
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let fullTranscript =
            #"{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-22T17:10:01Z","thinking":"Full expanded chain-of-thought loaded on demand from transcript_full.jsonl."}"# + "\n"
        try fullTranscript.write(to: fullTranscriptURL, atomically: true, encoding: .utf8)
        try "\u{1B}[36mRunning XCTest...\u{1B}[0m\n".write(to: taskLogURL, atomically: true, encoding: .utf8)

        let detector = AntigravityAppDetector(brainDirectoryURL: rootDir)
        let store = AntigravityTelemetryStore(appDetector: detector, idleDecaySeconds: 30)

        let discovered = ConversationDiscovery.scanSessions(in: rootDir)
        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(discovered[0].id, "52834bd5-test-conv")

        store.selectSession(discovered[0])
        let steps = await TranscriptTailer(transcriptURL: transcriptURL).readNewSteps()
        store.ingestSteps(steps, emitPeeks: false)

        XCTAssertEqual(store.activeModel, "gemini-4-neon-high")
        XCTAssertEqual(store.tokenMetrics.inputTokens, 500)
        XCTAssertEqual(store.commands.count, 1)
        XCTAssertEqual(store.commands[0].status, .running)

        // Load untruncated thinking on demand from transcript_full.jsonl
        let loaded = await store.loadFullStep(stepIndex: 1)
        XCTAssertEqual(
            loaded?.thinking,
            "Full expanded chain-of-thought loaded on demand from transcript_full.jsonl."
        )
        XCTAssertEqual(
            store.currentThinking?.text,
            "Full expanded chain-of-thought loaded on demand from transcript_full.jsonl."
        )
        XCTAssertEqual(store.currentThinking?.isFullTextLoaded, true)

        // Pause prevents additional live ingestion until resumed
        store.setPaused(true)
        XCTAssertTrue(store.isPaused)
        store.setPaused(false)
        XCTAssertFalse(store.isPaused)
        store.stop()
    }
}
