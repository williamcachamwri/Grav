import Foundation
import SQLite3
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

        let discovered = await ConversationDiscovery(brainDirectoryURL: rootDir).scanConversations()
        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(discovered[0].id, "52834bd5-test-conv")

        store.selectSession(discovered[0])
        let steps = await TranscriptTailer(transcriptURL: transcriptURL).readNewSteps()
        store.ingestSteps(steps, isInitialHydration: false)

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

    func testTruncatedStepOutputAndBackgroundTaskIdCorrelation() throws {
        let rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grav-trunc-\(UUID().uuidString)", isDirectory: true)
        let convDir = rootDir.appendingPathComponent("conv-1", isDirectory: true)
        let stepDir = convDir.appendingPathComponent(".system_generated/steps/11", isDirectory: true)
        try FileManager.default.createDirectory(at: stepDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let outputFile = stepDir.appendingPathComponent("output.txt")
        try "Command exited with code 0.\n\nCommand output:\nAll 42 checks passed\n".write(
            to: outputFile,
            atomically: true,
            encoding: .utf8
        )

        let session = ConversationSession(
            id: "conv-1",
            directoryURL: convDir,
            title: "Truncated Log Test",
            lastModified: Date()
        )

        var classifier = EventClassifier()
        let callStep = TranscriptStep(
            stepIndex: 10,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-22T18:00:00Z",
            toolCalls: [
                ToolCall(
                    name: "run_command",
                    args: [
                        "CommandLine": .string("git push origin main"),
                        "toolSummary": .string("Push commits"),
                    ]
                ),
            ]
        )
        let startOut = classifier.process(step: callStep, session: session)
        XCTAssertEqual(startOut.startedCommands.first?.taskLogURL?.lastPathComponent, "task-11.log")

        // Truncated GENERIC tool response where inline exit code was omitted and redirected to output.txt
        let truncatedResult = TranscriptStep(
            stepIndex: 11,
            source: "MODEL",
            type: "GENERIC",
            status: "DONE",
            createdAt: "2026-11-22T18:00:05Z",
            content: "Created At: 2026-11-22T18:00:00Z\nCompleted At: 2026-11-22T18:00:05Z\nThe tool's output was truncated due to being too long. You can find the full output in a file at file://\(outputFile.path)",
            truncatedFields: ["content"]
        )
        let resultOut = classifier.process(step: truncatedResult, session: session)
        XCTAssertEqual(resultOut.updatedCommands.first?.status, .succeeded)
        XCTAssertEqual(resultOut.updatedCommands.first?.stepOutputURL, outputFile)
        XCTAssertEqual(resultOut.state, .idle)

        // Verify background task ID without `.log` suffix resolves to `tasks/task-561.log`
        let parsedTaskURL = EventClassifier.extractTaskLogURL(
            from: #"[Message] sender=conv-1/task-561 content=Task id "conv-1/task-561" finished"#,
            session: session
        )
        XCTAssertEqual(parsedTaskURL?.lastPathComponent, "task-561.log")
    }

    func testFinalPlannerResponseSettlesStalePendingCommandToIdle() {
        var classifier = EventClassifier()
        let cmdStart = TranscriptStep(
            stepIndex: 20,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-22T18:10:00Z",
            toolCalls: [
                ToolCall(name: "run_command", args: ["CommandLine": .string("swift build"), "toolSummary": .string("Build")]),
            ]
        )
        _ = classifier.process(step: cmdStart)
        if case .runningCommand = classifier.state {
            // expected
        } else {
            XCTFail("Expected .runningCommand after run_command")
        }

        // Antigravity finishes its final answer to the user (no tool calls, not an immediate background wait ack)
        let finalReply = TranscriptStep(
            stepIndex: 22,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-22T18:10:12Z",
            content: "All done!"
        )
        let finalOut = classifier.process(step: finalReply)
        XCTAssertEqual(finalOut.state, .idle)
        XCTAssertTrue(classifier.pendingCommands.isEmpty)
        XCTAssertEqual(finalOut.responseSnapshot?.text, "All done!")
        XCTAssertEqual(finalOut.responseSnapshot?.isStreaming, false)
    }

    func testCorrelateAuthoritativeEditFileDiffCountsOnTruncatedToolCalls() {
        var classifier = EventClassifier()

        // Truncated `edit_file` calls in compact `transcript.jsonl` (only first 2 lines survived)
        let plannerStep = TranscriptStep(
            stepIndex: 691,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T02:24:11+07:00",
            toolCalls: [
                ToolCall(
                    name: "edit_file",
                    args: [
                        "Path": .string("/Users/wica/Grav/Grav/Features/Onboarding/OnboardingWindowController.swift"),
                        "Target": .string("line1\nline2"),
                        "Replacement": .string("new1\nnew2"),
                    ]
                ),
                ToolCall(
                    name: "edit_file",
                    args: [
                        "Path": .string("/Users/wica/Grav/Grav/Features/Onboarding/OnboardingWindowController.swift"),
                        "Target": .string("old1\nold2"),
                        "Replacement": .string("rep1\nrep2"),
                    ]
                ),
            ],
            truncatedFields: ["tool_calls"]
        )

        let callOut = classifier.process(step: plannerStep)
        XCTAssertEqual(callOut.fileChanges.count, 2)
        XCTAssertEqual(callOut.truncatedFileChangeStepIndices, [691])

        // First GENERIC edit result: +2/-2
        let gen1 = TranscriptStep(
            stepIndex: 693,
            source: "MODEL",
            type: "GENERIC",
            status: "DONE",
            createdAt: "2026-11-23T02:24:23+07:00",
            content: "Created At: 2026-11-23T02:24:12+07:00\nCompleted At: 2026-11-23T02:24:23+07:00\nMade 1 replacement in /Users/wica/Grav/Grav/Features/Onboarding/OnboardingWindowController.swift starting at line 554 (+2/-2 lines)."
        )
        let out1 = classifier.process(step: gen1)
        XCTAssertEqual(out1.fileChanges.first?.addedLines, 2)
        XCTAssertEqual(out1.fileChanges.first?.removedLines, 2)

        // Second GENERIC edit result on same file: +32/-32 (replaces truncated +2/-2!)
        let gen2 = TranscriptStep(
            stepIndex: 694,
            source: "MODEL",
            type: "GENERIC",
            status: "DONE",
            createdAt: "2026-11-23T02:24:24+07:00",
            content: "Created At: 2026-11-23T02:24:20+07:00\nCompleted At: 2026-11-23T02:24:24+07:00\nMade 1 replacement in /Users/wica/Grav/Grav/Features/Onboarding/OnboardingWindowController.swift starting at line 697 (+32/-32 lines)."
        )
        let out2 = classifier.process(step: gen2)
        XCTAssertEqual(out2.fileChanges.first?.id, callOut.fileChanges[1].id)
        XCTAssertEqual(out2.fileChanges.first?.addedLines, 32)
        XCTAssertEqual(out2.fileChanges.first?.removedLines, 32)
    }

    func testFileInspectionCompactionAndWorkingTransitions() {
        var classifier = EventClassifier()

        // 1. User prompt immediately transitions to .working
        let userStep = TranscriptStep(
            stepIndex: 1,
            source: "USER_EXPLICIT",
            type: "USER_INPUT",
            status: "DONE",
            createdAt: "2026-11-23T02:45:00Z",
            content: "<USER_REQUEST>\nAnalyze GravOnboardingMockScenes.swift\n</USER_REQUEST>"
        )
        let userOut = classifier.process(step: userStep)
        if case .working = userOut.state {
            // expected
        } else {
            XCTFail("Expected .working after USER_INPUT, got \(userOut.state)")
        }

        // 2. Context compaction CHECKPOINT transitions to .compacting
        let compactStep = TranscriptStep(
            stepIndex: 2,
            source: "SYSTEM",
            type: "CHECKPOINT",
            status: "RUNNING",
            createdAt: "2026-11-23T02:45:02Z",
            content: "# Resuming from a compaction"
        )
        let compactOut = classifier.process(step: compactStep)
        if case let .compacting(event) = compactOut.state {
            XCTAssertEqual(event.stepIndex, 2)
            XCTAssertTrue(event.isActive)
        } else {
            XCTFail("Expected .compacting after CHECKPOINT, got \(compactOut.state)")
        }

        // 3. read_file with StartLine/EndLine transitions to .inspecting with #L480-810
        let inspectStep = TranscriptStep(
            stepIndex: 3,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T02:45:05Z",
            thinking: "Reading mock scenes...",
            toolCalls: [
                ToolCall(
                    name: "read_file",
                    args: [
                        "Path": .string("/Users/wica/Grav/Grav/Features/Onboarding/GravOnboardingMockScenes.swift"),
                        "StartLine": .number(480),
                        "EndLine": .number(810),
                    ]
                ),
            ]
        )
        let inspectOut = classifier.process(step: inspectStep)
        XCTAssertEqual(inspectOut.fileInspections.count, 1)
        XCTAssertEqual(inspectOut.fileInspections[0].basename, "GravOnboardingMockScenes.swift")
        XCTAssertEqual(inspectOut.fileInspections[0].lineRangeLabel, "#L480-810")
        if case let .inspecting(event) = inspectOut.state {
            XCTAssertEqual(event.lineRangeLabel, "#L480-810")
        } else {
            XCTFail("Expected .inspecting after read_file, got \(inspectOut.state)")
        }

        // 4. Instant GENERIC DONE for read_file preserves .inspecting so Notch shows `Analyzed File #L...`
        let toolDone = TranscriptStep(
            stepIndex: 4,
            source: "MODEL",
            type: "GENERIC",
            status: "DONE",
            createdAt: "2026-11-23T02:45:06Z",
            content: "Showing lines 480-810"
        )
        let preservedOut = classifier.process(step: toolDone)
        if case let .inspecting(event) = preservedOut.state {
            XCTAssertEqual(event.basename, "GravOnboardingMockScenes.swift")
        } else {
            XCTFail("Expected .inspecting to be preserved after immediate read_file GENERIC DONE, got \(preservedOut.state)")
        }

        // 5. Final PLANNER_RESPONSE settles cleanly to .idle
        let doneReply = TranscriptStep(
            stepIndex: 5,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T02:45:10Z",
            content: "Done analyzing."
        )
        let doneOut = classifier.process(step: doneReply)
        XCTAssertEqual(doneOut.state, .idle)
    }

    func testConfirmedBackgroundTaskSurvivesFinalPlannerAckAndSettlesOnSystemMessage() {
        var classifier = EventClassifier()

        let callStep = TranscriptStep(
            stepIndex: 100,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T03:00:00Z",
            toolCalls: [
                ToolCall(
                    name: "run_command",
                    args: [
                        "CommandLine": .string("xcodebuild test"),
                        "toolSummary": .string("Run XCTest suite"),
                    ]
                ),
            ]
        )
        _ = classifier.process(step: callStep)

        // Background task notice (e.g. step 101)
        let bgNotice = TranscriptStep(
            stepIndex: 101,
            source: "MODEL",
            type: "GENERIC",
            status: "RUNNING",
            createdAt: "2026-11-23T03:00:08Z",
            content: "Tool is running as a background task with task id: conv/task-101"
        )
        _ = classifier.process(step: bgNotice)

        // Even if another step intervened before the planner's waiting message (step 103)
        let ackReply = TranscriptStep(
            stepIndex: 103,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T03:00:10Z",
            content: "Tests running in background..."
        )
        let ackOut = classifier.process(step: ackReply)
        if case .runningCommand = ackOut.state {
            // expected: confirmed background task MUST remain active
        } else {
            XCTFail("Expected confirmed background task to stay .runningCommand, got \(ackOut.state)")
        }
        XCTAssertEqual(classifier.pendingCommands.count, 1)

        // System message arrives when background task finishes
        let doneMsg = TranscriptStep(
            stepIndex: 104,
            source: "SYSTEM",
            type: "SYSTEM_MESSAGE",
            status: "DONE",
            createdAt: "2026-11-23T03:00:35Z",
            content: "Task id \"conv/task-101\" finished with result:\nCommand exited with code 0.\n\nCommand output:\nTEST SUCCEEDED"
        )
        let doneOut = classifier.process(step: doneMsg)
        XCTAssertEqual(doneOut.updatedCommands.first?.status, .succeeded)
        XCTAssertTrue(classifier.pendingCommands.isEmpty)
    }

    func testSwarmAndSubagentSnapshotParsing() throws {
        let rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grav-swarm-\(UUID().uuidString)", isDirectory: true)
        let convDir = rootDir.appendingPathComponent("coord-1", isDirectory: true)
        let swarmDir = convDir.appendingPathComponent(".system_generated/swarm", isDirectory: true)
        let subagentsDir = convDir.appendingPathComponent(".system_generated/subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: swarmDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subagentsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        try #"{"version":1,"swarm_id":"coord-1","created_at":"2026-11-23T03:00:00Z"}"#
            .write(to: swarmDir.appendingPathComponent("swarm.json"), atomically: true, encoding: .utf8)

        let membersJSON = """
        {
          "title": "Build Grav Swarm",
          "members": {
            "coordinator": { "conversation_id": "coord-1", "role": "coordinator", "phase": "RUNNING", "killed": false, "model": "gemini-4-argon-high" },
            "notch-hud": { "conversation_id": "worker-1", "role": "worker", "phase": "RUNNING", "wake_mode": "working", "killed": false, "model": "gemini-4-neon-high" },
            "telemetry": { "conversation_id": "worker-2", "role": "worker", "phase": "WAITING", "wake_mode": "waiting", "killed": false, "model": "gemini-4-neon-high" },
            "docs": { "conversation_id": "worker-3", "role": "worker", "phase": "KILLED", "killed": true, "model": "gemini-4-neon-high" }
          }
        }
        """
        try membersJSON.write(to: swarmDir.appendingPathComponent("members.json"), atomically: true, encoding: .utf8)

        let planJSON = """
        {
          "goal": { "title": "Ship Swarm HUD", "line": "Parallel workers & live board." },
          "tasks": { "notch-hud": "Build collapsed summary and Swarm tab" }
        }
        """
        try planJSON.write(to: swarmDir.appendingPathComponent("plan.json"), atomically: true, encoding: .utf8)

        let boardJSONL = """
        {"seq":1,"agent":"coordinator","text":"@notch-hud Please build Swarm tab","time":"2026-11-23 03:01:00"}
        {"seq":2,"agent":"notch-hud","text":"@coordinator Working on SwarmTelemetryTabView","time":"2026-11-23 03:02:00"}
        """
        try boardJSONL.write(to: swarmDir.appendingPathComponent("board.jsonl"), atomically: true, encoding: .utf8)

        // One swarm worker subagent + one standalone research subagent
        let workerSubagent = #"{"conversationId":"worker-1","subagentDescriptor":{"typeName":"worker","role":"Swarm Worker (notch-hud)"},"state":"SUBAGENT_STATE_RUNNING","spawnStepIndex":10}"#
        let researchSubagent = #"{"conversationId":"sub-research-1","subagentDescriptor":{"typeName":"research","role":"Codebase Researcher"},"state":"SUBAGENT_STATE_RUNNING","spawnStepIndex":12}"#
        try workerSubagent.write(to: subagentsDir.appendingPathComponent("worker-1.json"), atomically: true, encoding: .utf8)
        try researchSubagent.write(to: subagentsDir.appendingPathComponent("sub-research-1.json"), atomically: true, encoding: .utf8)

        let update = SwarmSubagentWatcher.readSnapshot(sessionDirectoryURL: convDir, brainDirectoryURL: rootDir)
        let swarm = try XCTUnwrap(update.swarm)
        XCTAssertEqual(swarm.displayTitle, "Ship Swarm HUD")
        XCTAssertEqual(swarm.runningWorkers.count, 1)
        XCTAssertEqual(swarm.waitingWorkers.count, 1)
        XCTAssertEqual(swarm.finishedWorkers.count, 1)
        XCTAssertTrue(swarm.hasLiveWorkers)
        XCTAssertEqual(swarm.collapsedRatioBadge, "1/3")
        XCTAssertTrue(swarm.collapsedSummaryText.contains("notch-hud"))
        XCTAssertEqual(swarm.boardMessages.first?.seq, 2)

        // Standalone subagent filtered cleanly from swarm workers
        let standalone = update.subagents.filter { !$0.isSwarmWorker }
        XCTAssertEqual(standalone.count, 1)
        XCTAssertEqual(standalone[0].role, "Codebase Researcher")
        XCTAssertTrue(standalone[0].isActive)
    }

    func testWriteFileOverwriteComputesTrueDeltaAgainstPreviousContent() {
        var classifier = EventClassifier()
        let path = "/Users/wica/Grav/Grav/Features/Notch/SwarmTelemetryTabView.swift"

        // 1. Initial write_file creates 4 lines
        let createStep = TranscriptStep(
            stepIndex: 10,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T03:15:00Z",
            toolCalls: [
                ToolCall(
                    name: "write_file",
                    args: [
                        "Path": .string(path),
                        "Overwrite": .bool(true),
                        "Content": .string("line1\nline2\nline3\nline4"),
                    ]
                ),
            ]
        )
        let createOut = classifier.process(step: createStep)
        XCTAssertEqual(createOut.fileChanges.first?.addedLines, 4)
        XCTAssertEqual(createOut.fileChanges.first?.removedLines, 0)

        // 2. Subsequent write_file(Overwrite: true) changes line2 and appends line5 & line6
        // Must report +3 -1 (true diff), NOT +6 -0!
        let overwriteStep = TranscriptStep(
            stepIndex: 20,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T03:26:00Z",
            toolCalls: [
                ToolCall(
                    name: "write_file",
                    args: [
                        "Path": .string(path),
                        "Overwrite": .bool(true),
                        "Content": .string("line1\nline2_updated\nline3\nline4\nline5\nline6"),
                    ]
                ),
            ]
        )
        let overwriteOut = classifier.process(step: overwriteStep)
        XCTAssertEqual(overwriteOut.fileChanges.first?.addedLines, 3)
        XCTAssertEqual(overwriteOut.fileChanges.first?.removedLines, 1)
    }

    func testAnnotationTurboParsingContextMeterSpeedAndReplyingState() {
        // 1. Real `.pbtxt` annotation parsing (Turbo preset + official title)
        let pbtxt = #"title:"Grav Telemetry Companion App" last_user_view_time:{seconds:1795380715 nanos:222000000} permission_preset:AGENT_PERMISSION_PRESET_TURBO"#
        let parsed = ConversationAnnotation.parse(pbtxt: pbtxt)
        XCTAssertEqual(parsed.title, "Grav Telemetry Companion App")
        XCTAssertEqual(parsed.executionMode, .turbo)
        XCTAssertTrue(parsed.executionMode.isTurbo)

        // 2. Context window occupancy, tok/s throughput, streaming .replying, and .turnCompleted peek
        var classifier = EventClassifier()
        let userStep = TranscriptStep(
            stepIndex: 1,
            source: "USER_EXPLICIT",
            type: "USER_INPUT",
            status: "DONE",
            createdAt: "2026-11-23T03:50:00Z",
            content: "<USER_REQUEST>\nRecommend top features\n</USER_REQUEST>"
        )
        _ = classifier.process(step: userStep)

        let streamingReply = TranscriptStep(
            stepIndex: 2,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "RUNNING",
            createdAt: "2026-11-23T03:50:05Z",
            model: "gemini-4-neon-high",
            inputTokens: 12_000,
            cacheReadTokens: 810_000,
            outputTokens: 300,
            content: "Here are the top 6 features..."
        )
        let streamOut = classifier.process(step: streamingReply)
        if case .replying = streamOut.state {
            // expected
        } else {
            XCTFail("Expected .replying during streaming response, got \(streamOut.state)")
        }
        XCTAssertEqual(streamOut.tokenMetrics.latestContextTokens, 822_000)
        XCTAssertTrue(streamOut.tokenMetrics.isContextNearCompaction)
        XCTAssertEqual(Int((streamOut.tokenMetrics.lastTurnTokensPerSecond ?? 0).rounded()), 60)

        let finalReply = TranscriptStep(
            stepIndex: 3,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T03:50:08Z",
            model: "gemini-4-neon-high",
            content: "Here are the top 6 features — complete."
        )
        let finalOut = classifier.process(step: finalReply)
        XCTAssertEqual(finalOut.state, .idle)
        XCTAssertTrue(finalOut.peekEvents.contains(.turnCompleted))
    }

    func testUpdateFocusStepsAndAllChatToolStatesClassification() {
        var classifier = EventClassifier()

        let userStep = TranscriptStep(
            stepIndex: 1,
            source: "USER_EXPLICIT",
            type: "USER_INPUT",
            status: "DONE",
            createdAt: "2026-11-23T05:00:00Z",
            content: "Build full realtime telemetry"
        )
        let userOut = classifier.process(step: userStep)
        XCTAssertNotNil(userOut.turnStartedAt)
        XCTAssertTrue(userOut.clearFocus)

        let stepsJSON = """
        [{"status":"done","title":"Reverse engineer app"},{"status":"in_progress","title":"Wire live focus & steps"},{"status":"pending","title":"Build Release"}]
        """
        let focusAndSteps = TranscriptStep(
            stepIndex: 2,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T05:00:12Z",
            toolCalls: [
                ToolCall(name: "update_focus", args: ["focus": .string("\"Wiring multi-color Super Saiyan aura & audio into Notch HUD\"")]),
                ToolCall(name: "update_steps", args: ["steps": .string(stepsJSON)]),
                ToolCall(name: "search_web", args: ["query": .string("\"NotchKit SwiftUI\"")]),
            ]
        )
        let out2 = classifier.process(step: focusAndSteps)
        XCTAssertEqual(out2.focusUpdate, "Wiring multi-color Super Saiyan aura & audio into Notch HUD")
        XCTAssertEqual(out2.stepsProgress?.completedCount, 1)
        XCTAssertEqual(out2.stepsProgress?.totalCount, 3)
        XCTAssertEqual(out2.stepsProgress?.ratioLabel, "1/3 steps")
        XCTAssertEqual(out2.stepsProgress?.activeStep?.title, "Wire live focus & steps")
        if case let .toolActivity(ev) = out2.state {
            XCTAssertEqual(ev.kind, .searchWeb)
            XCTAssertTrue(ev.title.contains("NotchKit SwiftUI"))
        } else {
            XCTFail("Expected .toolActivity(.searchWeb), got \(out2.state)")
        }

        let mcpAndAsk = TranscriptStep(
            stepIndex: 3,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T05:01:00Z",
            toolCalls: [
                ToolCall(name: "call_mcp_tool", args: ["ServerName": .string("\"rea\""), "ToolName": .string("\"inspect_go_binary\"")]),
                ToolCall(name: "ask_question", args: ["questions": .string("[{\"question\":\"Pick Super Saiyan color?\"}]")]),
            ]
        )
        let out3 = classifier.process(step: mcpAndAsk)
        if case let .waitingForInput(prompt) = out3.state {
            XCTAssertEqual(prompt, "Pick Super Saiyan color?")
        } else {
            XCTFail("Expected .waitingForInput, got \(out3.state)")
        }

        let finalStep = TranscriptStep(
            stepIndex: 4,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T05:09:00Z",
            content: "All done!"
        )
        let out4 = classifier.process(step: finalStep)
        XCTAssertEqual(out4.state, .idle)
        XCTAssertTrue(out4.clearFocus)
        XCTAssertEqual(Int((out4.lastTurnDuration ?? 0).rounded()), 540)
    }

    func testMCPToolArgumentsFormattingErrorCorrelationAndArtifacts() {
        var classifier = EventClassifier()

        let mcpCall = TranscriptStep(
            stepIndex: 10,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T05:10:00Z",
            toolCalls: [
                ToolCall(
                    name: "call_mcp_tool",
                    args: [
                        "ServerName": .string("\"rea\""),
                        "ToolName": .string("\"analyze_javascript_application\""),
                        "Arguments": .string("{\"detail\":\"summary\",\"input_path\":\"/Applications/Antigravity.app/Contents/Resources/app.asar\"}"),
                    ]
                ),
            ]
        )
        let outStart = classifier.process(step: mcpCall)
        guard let mcpEvent = outStart.toolActivities.first else {
            XCTFail("Expected MCP tool activity")
            return
        }
        XCTAssertEqual(mcpEvent.kind, .mcpTool)
        XCTAssertEqual(mcpEvent.toolName, "analyze_javascript_application")
        XCTAssertEqual(mcpEvent.serverName, "rea")
        XCTAssertEqual(mcpEvent.title, "analyze_javascript_application · rea")
        XCTAssertEqual(mcpEvent.status, .running)
        XCTAssertTrue(mcpEvent.argumentsJSON?.contains("\"input_path\"") == true)
        XCTAssertTrue(mcpEvent.argumentsJSON?.contains("app.asar") == true)

        let mcpErr = TranscriptStep(
            stepIndex: 11,
            source: "SYSTEM",
            type: "GENERIC",
            status: "ERROR",
            createdAt: "2026-11-23T05:10:04Z",
            content: "Created At: 2026-11-23T05:10:00Z\nCompleted At: 2026-11-23T05:10:04Z\nEncountered error in tool execution: Analysis input is invalid."
        )
        let outErr = classifier.process(step: mcpErr)
        XCTAssertEqual(outErr.updatedToolActivities.first?.status, .failed)
        XCTAssertTrue(outErr.updatedToolActivities.first?.outputPreview?.contains("Analysis input is invalid") == true)

        let artifactWrite = TranscriptStep(
            stepIndex: 12,
            source: "MODEL",
            type: "PLANNER_RESPONSE",
            status: "DONE",
            createdAt: "2026-11-23T05:10:10Z",
            toolCalls: [
                ToolCall(
                    name: "write_file",
                    args: [
                        "Path": .string("\"/Users/wica/.gemini/antigravity/brain/conv/plan.md\""),
                        "Content": .string("\"# Plan\\n- Step 1\""),
                        "ArtifactMetadata": .string("{\"Summary\":\"Implementation plan\",\"UserFacing\":true,\"RequestFeedback\":true}"),
                    ]
                ),
            ]
        )
        let outArt = classifier.process(step: artifactWrite)
        XCTAssertEqual(outArt.toolActivities.first?.kind, .artifact)
        XCTAssertEqual(outArt.toolActivities.first?.title, "Artifact · plan.md")
    }

    // MARK: - Codex Mini Pet API Parser, Sprite Slicer, GIF Export & Preferences

    func testCodexPetSearchInputParsing() {
        XCTAssertEqual(
            CodexPetSearchInput.parse("https://codex-pets.net/#/pets/super-saiyan-goku-combat"),
            .directPetSlug("super-saiyan-goku-combat")
        )
        XCTAssertEqual(
            CodexPetSearchInput.parse("https://codex-pets.net/#/?q=goku"),
            .query("goku")
        )
        XCTAssertEqual(
            CodexPetSearchInput.parse("https://codex-pets.net/#/?sort=popular&q=super%20saiyan"),
            .query("super saiyan")
        )
        XCTAssertEqual(
            CodexPetSearchInput.parse("  pikachu  "),
            .query("pikachu")
        )
        XCTAssertEqual(
            CodexPetSearchInput.parse(""),
            .query("")
        )
    }

    func testCodexPetSpriteSlicerAndGIFExport() throws {
        // Locate the bundled starter spritesheet inside Grav app bundle or repo resources
        let bundleURL = Bundle(for: AntigravityTelemetryStore.self)
            .url(forResource: "super-saiyan-goku-combat", withExtension: "webp")
            ?? URL(fileURLWithPath: "/Users/wica/Grav/Grav/Resources/DefaultPet/super-saiyan-goku-combat.webp")

        let data = try Data(contentsOf: bundleURL)
        let sliced = try XCTUnwrap(CodexPetSpriteSlicer.sliceAtlas(data: data, spriteVersion: 2))

        XCTAssertEqual(sliced.count, 11)
        XCTAssertEqual(sliced[.idle]?.count, 6)
        XCTAssertEqual(sliced[.runningRight]?.count, 8)
        XCTAssertEqual(sliced[.runningLeft]?.count, 8)
        XCTAssertEqual(sliced[.waving]?.count, 4)
        XCTAssertEqual(sliced[.jumping]?.count, 5)
        XCTAssertEqual(sliced[.failed]?.count, 8)
        XCTAssertEqual(sliced[.waiting]?.count, 6)
        XCTAssertEqual(sliced[.running]?.count, 6)
        XCTAssertEqual(sliced[.review]?.count, 6)
        XCTAssertEqual(sliced[.lookRightSide]?.count, 8)
        XCTAssertEqual(sliced[.lookLeftSide]?.count, 8)

        // Verify authentic GIF export via macOS ImageIO
        let idleFrames = try XCTUnwrap(sliced[.idle])
        let tmpGIF = FileManager.default.temporaryDirectory
            .appendingPathComponent("grav-test-goku-idle-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: tmpGIF) }

        try CodexPetSpriteSlicer.exportGIF(frames: idleFrames, to: tmpGIF)
        let gifData = try Data(contentsOf: tmpGIF)
        XCTAssertGreaterThan(gifData.count, 1024)
        let header = String(data: gifData.prefix(6), encoding: .ascii)
        XCTAssertTrue(header == "GIF89a" || header == "GIF87a", "Unexpected GIF header: \(header ?? "nil")")
        if let source = CGImageSourceCreateWithData(gifData as CFData, nil) {
            XCTAssertEqual(CGImageSourceGetCount(source), 6)
        } else {
            XCTFail("Exported GIF could not be decoded by ImageIO")
        }
    }

    @MainActor
    func testMiniPetAndHUDPreferencesPersistence() {
        let suiteName = "grav.test.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store1 = PreferencesStore(defaults: defaults)
        XCTAssertTrue(store1.miniPetEnabled)
        XCTAssertEqual(store1.activeMiniPetID, "super-saiyan-goku-combat")
        XCTAssertEqual(store1.miniPetPlacement, .topRight)
        XCTAssertEqual(store1.miniPetSize, 84.0, accuracy: 0.01)
        XCTAssertEqual(store1.miniPetSpeed, 1.0, accuracy: 0.01)
        XCTAssertTrue(store1.miniPetShowBubble)
        XCTAssertTrue(store1.miniPetAlwaysOnTop)
        XCTAssertEqual(store1.hoverOpenDelay, 0.15, accuracy: 0.001)
        XCTAssertTrue(store1.autoExpandOnNeedsInput)
        XCTAssertTrue(store1.hapticsEnabled)

        store1.miniPetPlacement = .bottomRight
        store1.miniPetSize = 104.0
        store1.miniPetSpeed = 1.4
        store1.miniPetShowBubble = false
        store1.miniPetAlwaysOnTop = false
        store1.hoverOpenDelay = 0.25
        store1.showCollapsedTokens = false
        store1.autoExpandOnNeedsInput = false

        let store2 = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store2.miniPetPlacement, .bottomRight)
        XCTAssertEqual(store2.miniPetSize, 104.0, accuracy: 0.01)
        XCTAssertEqual(store2.miniPetSpeed, 1.4, accuracy: 0.01)
        XCTAssertFalse(store2.miniPetRoaming)
        XCTAssertFalse(store2.miniPetShowBubble)
        XCTAssertFalse(store2.miniPetAlwaysOnTop)
        XCTAssertEqual(store2.hoverOpenDelay, 0.25, accuracy: 0.001)
        XCTAssertFalse(store2.showCollapsedTokens)
        XCTAssertFalse(store2.autoExpandOnNeedsInput)

        // Verify Mini Pet stays deterministically `.idle` when Antigravity is idle (never random actions)
        let telemetry = AntigravityTelemetryStore()
        for offset in stride(from: 0.0, through: 60.0, by: 3.5) {
            let mapped = CodexPetTelemetryMapper.animationState(
                for: telemetry,
                reactionOverride: nil,
                roamingEnabled: true,
                spriteVersion: 2,
                now: Date(timeIntervalSinceReferenceDate: offset)
            )
            XCTAssertEqual(mapped, .idle)
        }

        // Verify Global Hotkey defaults, display keys, and custom serialization
        XCTAssertEqual(GravHotkeyShortcut.defaultToggleNotch.displayKeys, ["⌥", "Space"])
        XCTAssertEqual(GravHotkeyShortcut.defaultToggleMiniPet.displayKeys, ["⌥", "⇧", "P"])
        XCTAssertEqual(GravHotkeyShortcut.defaultFocusAntigravity.displayKeys, ["⌥", "⇧", "A"])

        store1.hotkeyToggleNotch = nil
        store1.smartAlertMinDurationSeconds = 30.0
        store1.urgentAlertWhenBackgrounded = false
        store1.miniPetAutoHideFullscreen = false

        let store3 = PreferencesStore(defaults: defaults)
        XCTAssertNil(store3.hotkeyToggleNotch)
        XCTAssertEqual(store3.smartAlertMinDurationSeconds, 30.0, accuracy: 0.01)
        XCTAssertFalse(store3.urgentAlertWhenBackgrounded)
        XCTAssertFalse(store3.miniPetAutoHideFullscreen)

        // Verify local custom sprite sheet import into isolated temporary Pets directory
        let tmpPetsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grav-test-pets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpPetsDir) }

        let sheetURL = Bundle(for: AntigravityTelemetryStore.self)
            .url(forResource: "super-saiyan-goku-combat", withExtension: "webp")
            ?? URL(fileURLWithPath: "/Users/wica/Grav/Grav/Resources/DefaultPet/super-saiyan-goku-combat.webp")
        let isolatedPetsStore = CodexPetsStore(baseDirectoryURL: tmpPetsDir)
        let imported = isolatedPetsStore.importLocalSpritesheet(from: sheetURL, customName: "My Custom Goku")
        XCTAssertNotNil(imported)
        XCTAssertEqual(imported?.displayName, "My Custom Goku")
        XCTAssertEqual(imported?.spriteVersionNumber, 2)
    }

    func testAntigravitySpotlightAnnotationAndRuntimeInspection() throws {
        // 1. Annotation pbtxt parsing (`permission_preset` + `last_user_view_time`)
        let samplePbtxt = #"title:"Grav Telemetry Companion App" last_user_view_time:{seconds:1795418702 nanos:191000000} permission_preset:AGENT_PERMISSION_PRESET_TURBO"#
        let parsed = ConversationAnnotation.parse(pbtxt: samplePbtxt)
        XCTAssertEqual(parsed.title, "Grav Telemetry Companion App")
        XCTAssertEqual(parsed.executionMode, .turbo)
        let viewedAt = try XCTUnwrap(parsed.lastUserViewTime)
        XCTAssertEqual(viewedAt.timeIntervalSince1970, 1795418702.191, accuracy: 0.01)

        // 2. FTS5 match expression builder
        XCTAssertEqual(
            ConversationSQLiteProbe.buildFTS5MatchExpression(from: "notch token flow!"),
            #""notch"* AND "token"* AND "flow"*"#
        )
        XCTAssertNil(ConversationSQLiteProbe.buildFTS5MatchExpression(from: "   "))

        // 3. Artifacts, MCP servers & background tasks scanners on isolated temp fixture
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("grav-anti-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        let sessionDir = root.appendingPathComponent("brain/session-1", isDirectory: true)
        let scratchDir = sessionDir.appendingPathComponent("scratch", isDirectory: true)
        let tasksDir = sessionDir.appendingPathComponent(".system_generated/tasks", isDirectory: true)
        let mcpReaDir = root.appendingPathComponent("mcp/rea", isDirectory: true)
        try fm.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: tasksDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: mcpReaDir, withIntermediateDirectories: true)

        try "# Plan".write(to: sessionDir.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
        try "print('hi')".write(to: scratchDir.appendingPathComponent("helper.py"), atomically: true, encoding: .utf8)
        try "{}".write(to: mcpReaDir.appendingPathComponent("inspect_macho.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: mcpReaDir.appendingPathComponent("analyze_function.json"), atomically: true, encoding: .utf8)
        try "build ok\n".write(to: tasksDir.appendingPathComponent("task-99.log"), atomically: true, encoding: .utf8)

        let artifacts = AntigravityRuntimeInspector.scanSessionArtifacts(sessionDirectoryURL: sessionDir)
        XCTAssertEqual(artifacts.count, 2)
        XCTAssertTrue(artifacts.contains { $0.name == "plan.md" && $0.kind == .planDocument })
        XCTAssertTrue(artifacts.contains { $0.name == "helper.py" && $0.kind == .scratchScript })

        let servers = AntigravityRuntimeInspector.scanInstalledMCPServers(antigravityRootURL: root)
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers.first?.name, "rea")
        XCTAssertEqual(servers.first?.toolCount, 2)

        let tasks = AntigravityRuntimeInspector.buildScheduledTaskRecords(
            tasksDirectoryURL: tasksDir,
            commands: [],
            recentActivity: []
        )
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "task-99")
    }

    @MainActor
    func testQuotaRateLimitAndModelFallbackDetectorDrivesNotchAndPetFailedState() throws {
        // 1. Direct classifier tests (Quota, 429 Rate Limit, Capacity 503/529, benign prose ignored)
        let quota = try XCTUnwrap(
            AntigravityRuntimeInspector.classifyModelError(
                rawMessage: "RPC error: RESOURCE_EXHAUSTED — daily quota exceeded",
                stepIndex: 10
            )
        )
        XCTAssertEqual(quota.kind, .quotaExceeded)
        XCTAssertEqual(quota.badge, "429 · QUOTA")
        XCTAssertTrue(quota.isFailure)

        let rate = try XCTUnwrap(
            AntigravityRuntimeInspector.classifyModelError(
                rawMessage: "HTTP 429 Too Many Requests: rate limit hit",
                stepIndex: 11
            )
        )
        XCTAssertEqual(rate.kind, .rateLimited)
        XCTAssertTrue(rate.isFailure)

        let cap = try XCTUnwrap(
            AntigravityRuntimeInspector.classifyModelError(
                rawMessage: "503 Service Unavailable: model overloaded due to high demand",
                stepIndex: 12
            )
        )
        XCTAssertEqual(cap.kind, .capacityExhausted)
        XCTAssertTrue(cap.isFailure)

        // Benign assistant prose mentioning "429" on a DONE step must NOT trigger a false alarm
        let benignStep = TranscriptStep(
            stepIndex: 13,
            type: "PLANNER_RESPONSE",
            status: "DONE",
            model: "gemini-4-pro",
            content: "We added a 429 quota detector."
        )
        XCTAssertNil(AntigravityRuntimeInspector.classifyTranscriptStepError(benignStep))

        // 2. End-to-end store ingestion: Quota ERROR -> Notch radar + Mini Pet `.failed`
        let store = AntigravityTelemetryStore()
        store.ingestSteps([benignStep], isInitialHydration: false)
        XCTAssertNil(store.latestModelIncident)

        let failedStep = TranscriptStep(
            stepIndex: 14,
            type: "PLANNER_RESPONSE",
            status: "ERROR",
            model: "gemini-4-pro",
            content: "RESOURCE_EXHAUSTED: Quota exceeded for model gemini-4-pro"
        )
        store.ingestSteps([failedStep], isInitialHydration: false)
        XCTAssertEqual(store.latestModelIncident?.kind, .quotaExceeded)
        XCTAssertEqual(store.activeRadarAlert?.severity, .modelIncident)

        let petStateOnQuota = CodexPetTelemetryMapper.animationState(
            for: store,
            reactionOverride: nil,
            roamingEnabled: false,
            spriteVersion: 2
        )
        XCTAssertEqual(petStateOnQuota, .failed)

        // 3. Recovery + mid-session Model Fallback (`gemini-4-pro` -> `gemini-4-flash`)
        let recoveredFallbackStep = TranscriptStep(
            stepIndex: 15,
            type: "PLANNER_RESPONSE",
            status: "DONE",
            model: "gemini-4-flash",
            content: "Continuing on flash."
        )
        store.ingestSteps([recoveredFallbackStep], isInitialHydration: false)
        XCTAssertEqual(store.latestModelIncident?.kind, .modelFallback(from: "gemini-4-pro", to: "gemini-4-flash"))
        XCTAssertEqual(store.activeRadarAlert?.severity, .modelFallback)

        // Model fallback is informational (not a failure), so Pet leaves `.failed` cleanly
        let petStateAfterFallback = CodexPetTelemetryMapper.animationState(
            for: store,
            reactionOverride: nil,
            roamingEnabled: false,
            spriteVersion: 2
        )
        XCTAssertNotEqual(petStateAfterFallback, .failed)
    }

    func testSpotlightSQLiteFTS5SearchReturnsRealMatchesForEnglishAndVietnamese() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("grav-fts-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let dbURL = root.appendingPathComponent("conversation_summaries.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let schemaSQL = """
        CREATE TABLE conversation_summaries (
            conversation_id text PRIMARY KEY,
            title text NOT NULL DEFAULT '',
            preview text NOT NULL DEFAULT '',
            step_count integer NOT NULL DEFAULT 0,
            last_modified_time datetime NOT NULL,
            workspace_uris text NOT NULL,
            status text NOT NULL DEFAULT '',
            parent_conversation_id text NOT NULL DEFAULT '',
            not_fully_idle numeric NOT NULL DEFAULT 0,
            killed numeric NOT NULL DEFAULT 0
        );
        CREATE VIRTUAL TABLE conversations_fts USING fts5(
            conversation_id UNINDEXED,
            chunk_index UNINDEXED,
            chunk_first_step UNINDEXED,
            chunk_last_step UNINDEXED,
            last_modified_time UNINDEXED,
            step_count UNINDEXED,
            last_step_created_at UNINDEXED,
            archived UNINDEXED,
            user_step_byte_offsets UNINDEXED,
            agent_step_byte_offsets UNINDEXED,
            title,
            workspace,
            project,
            user_body,
            agent_body,
            tokenize = 'unicode61 remove_diacritics 2',
            prefix = '1 2 3'
        );
        INSERT INTO conversation_summaries VALUES (
            'convo-1', 'Grav Telemetry Companion App', 'Overhaul settings panel', 120,
            '2026-11-23 07:00:00+00:00', '["file:///Users/wica/Grav"]', 'CASCADE_RUN_STATUS_IDLE', '', 0, 0
        );
        INSERT INTO conversations_fts VALUES (
            'convo-1', 0, 42, 60, '2026-11-23 07:00:00+00:00', 120, '2026-11-23 07:00:00+00:00', 0, '', '',
            'Grav Telemetry Companion App', 'Grav', 'Grav',
            'thêm mini pet goku và nâng cấp giao diện settings mượt hơn',
            'Đã thêm Super Saiyan Goku và sửa lỗi 429 quota.'
        );
        """
        XCTAssertEqual(sqlite3_exec(db, schemaSQL, nil, nil, nil), SQLITE_OK)

        // 1. Empty query returns recent sessions
        let recent = ConversationSQLiteProbe.searchConversations(antigravityRootURL: root, query: "")
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.conversationID, "convo-1")

        // 2. English FTS5 query finds chunk with exact step label
        let gokuHits = ConversationSQLiteProbe.searchConversations(antigravityRootURL: root, query: "goku")
        XCTAssertEqual(gokuHits.count, 1)
        XCTAssertEqual(gokuHits.first?.chunkStepLabel, "Step 42")
        XCTAssertTrue(gokuHits.first?.snippet.lowercased().contains("goku") == true)

        // 3. Vietnamese query (including decomposed NFD input) finds exact match
        let decomposedVN = "giao diện".decomposedStringWithCanonicalMapping
        let vnHits = ConversationSQLiteProbe.searchConversations(antigravityRootURL: root, query: decomposedVN)
        XCTAssertEqual(vnHits.count, 1)
        XCTAssertEqual(vnHits.first?.conversationID, "convo-1")

        // 4. Agent-body-only match picks agent snippet cleanly
        let agentHits = ConversationSQLiteProbe.searchConversations(antigravityRootURL: root, query: "quota")
        XCTAssertEqual(agentHits.count, 1)
        XCTAssertTrue(agentHits.first?.snippet.lowercased().contains("quota") == true)
    }

    func testAntigravityProfileProbeReadsAccountUsageAndModels() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("grav-profile-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }

        let antiRoot = tmp.appendingPathComponent("antigravity", isDirectory: true)
        let sessionLogs = antiRoot.appendingPathComponent("brain/s1/.system_generated/logs", isDirectory: true)
        let appSupport = tmp.appendingPathComponent("AppSupport", isDirectory: true)
        let agySupport = appSupport.appendingPathComponent("Antigravity", isDirectory: true)
        try fm.createDirectory(at: sessionLogs, withIntermediateDirectories: true)
        try fm.createDirectory(at: agySupport, withIntermediateDirectories: true)

        let storageJSON = #"{"agy.onboarding.lastLoginUsername":"dev.user@example.com"}"#
        try storageJSON.write(to: agySupport.appendingPathComponent("app_storage.json"), atomically: true, encoding: .utf8)

        let nowISO = ISO8601DateFormatter().string(from: Date())
        let transcript = """
        {"step_index":1,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"\(nowISO)","model":"gemini-4-neon-high","input_tokens":5000,"output_tokens":1200}
        {"step_index":2,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"\(nowISO)","model":"gemini-4-argon-high","input_tokens":3000,"output_tokens":800}
        """
        try transcript.write(to: sessionLogs.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = AntigravityProfileProbe.loadProfile(
            antigravityRootURL: antiRoot,
            appSupportURL: appSupport,
            activeModel: "gemini-4-neon-high"
        )
        XCTAssertEqual(snapshot.email, "dev.user@example.com")
        XCTAssertEqual(snapshot.displayName, "Dev User")
        XCTAssertNil(snapshot.avatarURL)
        XCTAssertNil(snapshot.availableCredits)
        XCTAssertFalse(snapshot.hasFreshServerQuota)
        XCTAssertEqual(snapshot.totalTokens5h, 10_000)
        XCTAssertEqual(snapshot.totalTokens7d, 10_000)
        XCTAssertEqual(snapshot.totalTurns5h, 2)
        XCTAssertEqual(snapshot.usageGroups.count, 3)
        XCTAssertNil(snapshot.usageGroups.first?.windows.first?.serverRemainingFraction)
        XCTAssertTrue(snapshot.availableModels.contains { $0.displayName == "Gemini 4 Neon (High)" })
        XCTAssertTrue(snapshot.availableModels.contains { $0.displayName == "Gemini 4 Argon (High)" })
        XCTAssertEqual(AntigravityProfileProbe.prettifyModelIdentifier("gemini-4-neon-high"), "Gemini 4 Neon (High)")
    }
}
