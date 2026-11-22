import Foundation
import XCTest
@testable import Grav

final class TranscriptTailerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grav-tailer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testIncrementalByteOffsetReadsOnlyAppendedLines() async throws {
        let transcriptURL = tempDir.appendingPathComponent("transcript.jsonl")
        let line0 = #"{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-11-22T17:07:16Z","content":"Build Grav"}"# + "\n"
        try line0.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let tailer = TranscriptTailer(transcriptURL: transcriptURL)
        let firstBatch = await tailer.readNewSteps()
        XCTAssertEqual(firstBatch.count, 1)
        XCTAssertEqual(firstBatch[0].stepIndex, 0)

        let offsetAfterFirst = await tailer.byteOffset
        XCTAssertEqual(offsetAfterFirst, UInt64(line0.utf8.count))

        // Reading again without new bytes returns empty and keeps offset unchanged
        let emptyBatch = await tailer.readNewSteps()
        XCTAssertTrue(emptyBatch.isEmpty)
        let offsetUnchanged = await tailer.byteOffset
        XCTAssertEqual(offsetUnchanged, offsetAfterFirst)

        // Append step 1 and step 2
        let line1 = #"{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-22T17:07:18Z","model":"gemini-4-neon-high","input_tokens":1200,"output_tokens":340,"thinking":"Inspecting workspace"}"# + "\n"
        let line2 = #"{"step_index":2,"source":"MODEL","type":"GENERIC","status":"DONE","created_at":"2026-11-22T17:07:20Z","content":"Command exited with code 0."}"# + "\n"
        let handle = try FileHandle(forWritingTo: transcriptURL)
        try handle.seekToEnd()
        handle.write(Data((line1 + line2).utf8))
        try handle.close()

        let secondBatch = await tailer.readNewSteps()
        XCTAssertEqual(secondBatch.map(\.stepIndex), [1, 2])
        let finalOffset = await tailer.byteOffset
        XCTAssertEqual(finalOffset, UInt64((line0 + line1 + line2).utf8.count))
    }

    func testPartialLineIsHeldUntilNewlineArrives() async throws {
        let transcriptURL = tempDir.appendingPathComponent("transcript.jsonl")
        let partialStart = #"{"step_index":0,"source":"MODEL","type":"PLANNER_RESPONSE","thinking":"Still writ"#
        try partialStart.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let tailer = TranscriptTailer(transcriptURL: transcriptURL)
        let initial = await tailer.readNewSteps()
        XCTAssertTrue(initial.isEmpty)
        let offsetBefore = await tailer.byteOffset
        XCTAssertEqual(offsetBefore, 0)

        let partialEnd = #"ing..."}"# + "\n"
        let handle = try FileHandle(forWritingTo: transcriptURL)
        try handle.seekToEnd()
        handle.write(Data(partialEnd.utf8))
        try handle.close()

        let completed = await tailer.readNewSteps()
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed[0].thinking, "Still writing...")
    }

    func testTruncationRecoveryResetsByteOffset() async throws {
        let transcriptURL = tempDir.appendingPathComponent("transcript.jsonl")
        let initialPayload =
            #"{"step_index":0,"type":"USER_INPUT","content":"Long initial prompt payload to advance byte offset far ahead of replacement"}"# + "\n" +
            #"{"step_index":1,"type":"PLANNER_RESPONSE","thinking":"First session thought with plenty of text"}"# + "\n"
        try initialPayload.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let tailer = TranscriptTailer(transcriptURL: transcriptURL)
        let batch1 = await tailer.readNewSteps()
        XCTAssertEqual(batch1.count, 2)

        // Truncate file to a shorter fresh transcript
        let rotatedLine = #"{"step_index":0,"type":"USER_INPUT","content":"Fresh"}"# + "\n"
        try rotatedLine.write(to: transcriptURL, atomically: false, encoding: .utf8)

        let batch2 = await tailer.readNewSteps()
        XCTAssertEqual(batch2.count, 1)
        XCTAssertEqual(batch2[0].stepIndex, 0)
        XCTAssertEqual(batch2[0].content, "Fresh")
        let newOffset = await tailer.byteOffset
        XCTAssertEqual(newOffset, UInt64(rotatedLine.utf8.count))
    }

    func testReadFullStepFromTranscriptFullOnDemand() async throws {
        let transcriptURL = tempDir.appendingPathComponent("transcript.jsonl")
        let fullURL = tempDir.appendingPathComponent("transcript_full.jsonl")

        let compact = #"{"step_index":4,"type":"PLANNER_RESPONSE","thinking":"Truncated...","truncated_fields":["thinking"]}"# + "\n"
        let full =
            #"{"step_index":0,"type":"USER_INPUT","content":"Prompt"}"# + "\n" +
            #"{"step_index":4,"type":"PLANNER_RESPONSE","thinking":"Complete untruncated chain of thought for step four."}"# + "\n" +
            #"{"step_index":5,"type":"GENERIC","content":"Done"}"# + "\n"

        try compact.write(to: transcriptURL, atomically: true, encoding: .utf8)
        try full.write(to: fullURL, atomically: true, encoding: .utf8)

        let tailer = TranscriptTailer(transcriptURL: transcriptURL)
        let steps = await tailer.readNewSteps()
        XCTAssertEqual(steps.count, 1)
        XCTAssertTrue(steps[0].isFieldTruncated("thinking"))

        let fullStep = await tailer.readFullStep(stepIndex: 4, from: fullURL)
        XCTAssertEqual(fullStep?.stepIndex, 4)
        XCTAssertEqual(fullStep?.thinking, "Complete untruncated chain of thought for step four.")

        let missingStep = await tailer.readFullStep(stepIndex: 99, from: fullURL)
        XCTAssertNil(missingStep)
    }
}
