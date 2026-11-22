import XCTest
@testable import Grav

final class DestructiveCommandParserTests: XCTestCase {
    func testParsesStandardRmAndFlags() {
        let paths = DestructiveCommandParser.extractDeletedPaths(
            from: "rm -rf /Users/wica/Grav/OldView.swift \"/Users/wica/Grav/Legacy Helper.swift\""
        )
        XCTAssertEqual(paths, [
            "/Users/wica/Grav/OldView.swift",
            "/Users/wica/Grav/Legacy Helper.swift",
        ])
    }

    func testParsesChainedCommandsGitRmAndUnlinkWithCd() {
        let command = "cd /Users/wica/Grav && git rm -f Sources/Obsolete.swift; unlink temp.lock || rm -- -weird.txt"
        let paths = DestructiveCommandParser.extractDeletedPaths(from: command)
        XCTAssertEqual(paths, [
            "/Users/wica/Grav/Sources/Obsolete.swift",
            "/Users/wica/Grav/temp.lock",
            "/Users/wica/Grav/-weird.txt",
        ])
    }

    func testIgnoresGitRmDryRunAndNonDestructiveCommands() {
        XCTAssertTrue(
            DestructiveCommandParser.extractDeletedPaths(from: "git rm --dry-run README.md").isEmpty
        )
        XCTAssertTrue(
            DestructiveCommandParser.extractDeletedPaths(from: "echo \"rm -rf /tmp/fake\" && swift test").isEmpty
        )
    }
}
