import Foundation
import XCTest
@testable import Grav

final class TaskLogTailerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grav-tasklog-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testIncrementalTaskLogTailingStripsANSIAndHandlesAppends() async throws {
        let logURL = tempDir.appendingPathComponent("task-56.log")
        try "\u{1B}[32mStep 1\u{1B}[0m\n".write(to: logURL, atomically: true, encoding: .utf8)

        let tailer = TaskLogTailer()
        let updates = LockedBox<[String]>([])

        await tailer.startTailing(commandID: "cmd-56", taskLogURL: logURL) { _, text in
            updates.append(text)
        }

        XCTAssertEqual(updates.snapshot().last, "Step 1\n")

        // Append more output
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        handle.write(Data("\u{1B}[33mStep 2\u{1B}[0m\r\n".utf8))
        try handle.close()

        let updated = await tailer.readIncrementalUpdate(for: "cmd-56")
        XCTAssertEqual(updated, "Step 1\nStep 2\n")

        await tailer.stopAll()
    }
}

private final class LockedBox<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element]

    init(_ initial: [Element]) {
        self.storage = initial
    }

    func append(_ value: Element) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    func snapshot() -> [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
