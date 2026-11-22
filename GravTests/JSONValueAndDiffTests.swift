import Foundation
import XCTest
@testable import Grav

final class JSONValueAndDiffTests: XCTestCase {
    func testJSONValueUnwrapsAntigravityDoubleQuotedStringsAndPrimitives() throws {
        let json = """
        {
            "Path": "\\"/Users/wica/Grav/Auth.swift\\"",
            "Overwrite": "true",
            "WaitMsBeforeAsync": "5000",
            "NativeBool": false,
            "NativeInt": 42,
            "PlainString": "hello"
        }
        """
        let dict = try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))

        XCTAssertEqual(dict["Path"]?.unwrappedString, "/Users/wica/Grav/Auth.swift")
        XCTAssertEqual(dict["Overwrite"]?.unwrappedBool, true)
        XCTAssertEqual(dict["WaitMsBeforeAsync"]?.unwrappedInt, 5000)
        XCTAssertEqual(dict["NativeBool"]?.unwrappedBool, false)
        XCTAssertEqual(dict["NativeInt"]?.unwrappedInt, 42)
        XCTAssertEqual(dict["PlainString"]?.unwrappedString, "hello")
    }

    func testDiffComputerLineCountsAndMiniDiffHunks() {
        let target = """
        struct Config {
            let timeout = 10
            let retries = 3
            let debug = false
        }
        """
        let replacement = """
        struct Config {
            let timeout = 30
            let retries = 3
            let backoff = 1.5
            let debug = true
        }
        """

        let result = DiffComputer.computeDiff(oldText: target, newText: replacement)
        XCTAssertEqual(result.removedLines, 2)
        XCTAssertEqual(result.addedLines, 3)
        XCTAssertFalse(result.hunks.isEmpty)

        let allLines = result.hunks.flatMap(\.lines)
        XCTAssertTrue(allLines.contains(where: { $0.kind == .removed && $0.text.contains("timeout = 10") }))
        XCTAssertTrue(allLines.contains(where: { $0.kind == .added && $0.text.contains("timeout = 30") }))
        XCTAssertTrue(allLines.contains(where: { $0.kind == .added && $0.text.contains("backoff = 1.5") }))
    }

    func testDiffComputerWriteDiffCountsLines() {
        let content = "import Foundation\n\nstruct Telemetry {}\n"
        let result = DiffComputer.computeWriteDiff(content: content)
        XCTAssertEqual(result.addedLines, 3)
        XCTAssertEqual(result.removedLines, 0)
        XCTAssertEqual(result.hunks.first?.lines.count, 3)
    }

    func testANSIStripperRemovesEscapeSequencesAndNormalizesProgressLines() {
        let raw = "\u{1B}[32mPASS\u{1B}[0m Build succeeded\r\nCompiling 20%\rCompiling 100%\r\n\u{1B}]0;Window Title\u{07}Done"
        let stripped = ANSIStripper.strip(raw)
        XCTAssertEqual(stripped, "PASS Build succeeded\nCompiling 100%\nDone")

        let segments = ANSIStripper.parseSegments("\u{1B}[1;31mERROR\u{1B}[0m: failed")
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "ERROR")
        XCTAssertEqual(segments[0].style.foreground, .red)
        XCTAssertTrue(segments[0].style.isBold)
        XCTAssertEqual(segments[1].text, ": failed")
        XCTAssertNil(segments[1].style.foreground)
    }
}
