import Foundation

/// Summary of a computed line-level file diff.
public struct DiffResult: Sendable, Equatable {
    public let addedLines: Int
    public let removedLines: Int
    public let hunks: [FileDiffHunk]

    public init(addedLines: Int, removedLines: Int, hunks: [FileDiffHunk]) {
        self.addedLines = addedLines
        self.removedLines = removedLines
        self.hunks = hunks
    }
}

/// Pure line-level diff engine computing real `+added` / `-removed` line counts and contextual
/// `FileDiffHunk`s from `Target` vs `Replacement` strings and `write_file` payloads.
public enum DiffComputer: Sendable {
    private enum RawOp {
        case context(String)
        case removed(String)
        case added(String)
    }

    /// Computes a line-level diff between `oldText` (`Target`) and `newText` (`Replacement`),
    /// returning exact added/removed line counts and contextual `FileDiffHunk`s.
    public static func computeDiff(
        oldText: String,
        newText: String,
        contextLines: Int = 2,
        maxLinesPerHunk: Int = 80
    ) -> DiffResult {
        let oldLines = splitLines(oldText)
        let newLines = splitLines(newText)

        if oldLines == newLines {
            return DiffResult(addedLines: 0, removedLines: 0, hunks: [])
        }

        let ops = computeEditOperations(old: oldLines, new: newLines)
        var totalAdded = 0
        var totalRemoved = 0
        for op in ops {
            switch op {
            case .added: totalAdded += 1
            case .removed: totalRemoved += 1
            case .context: break
            }
        }

        let hunks = buildHunks(
            from: ops,
            contextLines: max(0, contextLines),
            maxLinesPerHunk: max(4, maxLinesPerHunk),
            startingHunkID: 0
        )

        return DiffResult(addedLines: totalAdded, removedLines: totalRemoved, hunks: hunks)
    }

    /// Computes a combined diff across multiple `(target, replacement)` chunks
    /// (such as `multi_replace_file_content` `ReplacementChunks`).
    public static func computeMultiChunkDiff(
        chunks: [(target: String, replacement: String)],
        contextLines: Int = 2,
        maxLinesPerHunk: Int = 80
    ) -> DiffResult {
        var totalAdded = 0
        var totalRemoved = 0
        var allHunks: [FileDiffHunk] = []
        var nextHunkID = 0

        for chunk in chunks {
            let single = computeDiff(
                oldText: chunk.target,
                newText: chunk.replacement,
                contextLines: contextLines,
                maxLinesPerHunk: maxLinesPerHunk
            )
            totalAdded += single.addedLines
            totalRemoved += single.removedLines
            for hunk in single.hunks {
                allHunks.append(
                    FileDiffHunk(
                        id: nextHunkID,
                        lines: hunk.lines,
                        addedCount: hunk.addedCount,
                        removedCount: hunk.removedCount
                    )
                )
                nextHunkID += 1
            }
        }

        return DiffResult(addedLines: totalAdded, removedLines: totalRemoved, hunks: allHunks)
    }

    /// Computes added line count and a preview `FileDiffHunk` for a newly created or overwritten file.
    public static func computeWriteDiff(content: String, maxPreviewLines: Int = 24) -> DiffResult {
        let lines = splitLines(content)
        let totalAdded = lines.count
        guard totalAdded > 0 else {
            return DiffResult(addedLines: 0, removedLines: 0, hunks: [])
        }

        let previewCount = min(totalAdded, max(1, maxPreviewLines))
        var diffLines: [FileDiffLine] = []
        diffLines.reserveCapacity(previewCount)
        for index in 0..<previewCount {
            diffLines.append(FileDiffLine(id: index, kind: .added, text: lines[index]))
        }

        let hunk = FileDiffHunk(
            id: 0,
            lines: diffLines,
            addedCount: totalAdded,
            removedCount: 0
        )
        return DiffResult(addedLines: totalAdded, removedLines: 0, hunks: [hunk])
    }

    /// Returns the logical line count of a text payload (normalizing CRLF and ignoring a single trailing newline).
    public static func lineCount(of text: String) -> Int {
        splitLines(text).count
    }

    /// Splits text into lines cleanly, normalizing `\r\n` and omitting a single trailing empty element after `\n`.
    internal static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    // MARK: - LCS Line Diff with Prefix/Suffix Trimming

    private static func computeEditOperations(old: [String], new: [String]) -> [RawOp] {
        // Trim shared prefix
        var prefixCount = 0
        let minCount = min(old.count, new.count)
        while prefixCount < minCount, old[prefixCount] == new[prefixCount] {
            prefixCount += 1
        }

        // Trim shared suffix
        var suffixCount = 0
        while suffixCount < (minCount - prefixCount),
              old[old.count - 1 - suffixCount] == new[new.count - 1 - suffixCount]
        {
            suffixCount += 1
        }

        let oldMid = Array(old[prefixCount..<(old.count - suffixCount)])
        let newMid = Array(new[prefixCount..<(new.count - suffixCount)])

        var ops: [RawOp] = []
        ops.reserveCapacity(old.count + new.count)

        for i in 0..<prefixCount {
            ops.append(.context(old[i]))
        }

        if oldMid.isEmpty {
            for line in newMid {
                ops.append(.added(line))
            }
        } else if newMid.isEmpty {
            for line in oldMid {
                ops.append(.removed(line))
            }
        } else if oldMid.count * newMid.count <= 160_000 {
            ops.append(contentsOf: lcsOperations(old: oldMid, new: newMid))
        } else {
            ops.append(contentsOf: stdlibDifferenceOperations(old: oldMid, new: newMid))
        }

        let suffixStart = old.count - suffixCount
        for i in suffixStart..<old.count {
            ops.append(.context(old[i]))
        }

        return ops
    }

    private static func lcsOperations(old: [String], new: [String]) -> [RawOp] {
        let m = old.count
        let n = new.count
        let rowWidth = n + 1
        var dp = [Int](repeating: 0, count: (m + 1) * rowWidth)

        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                if old[i] == new[j] {
                    dp[i * rowWidth + j] = dp[(i + 1) * rowWidth + (j + 1)] + 1
                } else {
                    dp[i * rowWidth + j] = max(dp[(i + 1) * rowWidth + j], dp[i * rowWidth + (j + 1)])
                }
            }
        }

        var ops: [RawOp] = []
        ops.reserveCapacity(m + n)
        var i = 0
        var j = 0
        while i < m && j < n {
            if old[i] == new[j] {
                ops.append(.context(old[i]))
                i += 1
                j += 1
            } else if dp[(i + 1) * rowWidth + j] >= dp[i * rowWidth + (j + 1)] {
                ops.append(.removed(old[i]))
                i += 1
            } else {
                ops.append(.added(new[j]))
                j += 1
            }
        }
        while i < m {
            ops.append(.removed(old[i]))
            i += 1
        }
        while j < n {
            ops.append(.added(new[j]))
            j += 1
        }
        return ops
    }

    private static func stdlibDifferenceOperations(old: [String], new: [String]) -> [RawOp] {
        let diff = new.difference(from: old)
        var removedOffsets = Set<Int>()
        var insertionsByOffset: [Int: [String]] = [:]

        for change in diff {
            switch change {
            case let .remove(offset, _, _):
                removedOffsets.insert(offset)
            case let .insert(offset, element, _):
                insertionsByOffset[offset, default: []].append(element)
            }
        }

        var ops: [RawOp] = []
        ops.reserveCapacity(old.count + new.count)
        var oldIdx = 0
        var newIdx = 0

        while oldIdx < old.count || newIdx < new.count {
            if oldIdx < old.count, removedOffsets.contains(oldIdx) {
                ops.append(.removed(old[oldIdx]))
                oldIdx += 1
            } else if let inserted = insertionsByOffset[newIdx], !inserted.isEmpty {
                for line in inserted {
                    ops.append(.added(line))
                    newIdx += 1
                }
            } else if oldIdx < old.count {
                ops.append(.context(old[oldIdx]))
                oldIdx += 1
                newIdx += 1
            } else {
                break
            }
        }

        return ops
    }

    // MARK: - Hunk Grouping

    private static func buildHunks(
        from ops: [RawOp],
        contextLines: Int,
        maxLinesPerHunk: Int,
        startingHunkID: Int
    ) -> [FileDiffHunk] {
        // Locate ranges of changed operations expanded by `contextLines`
        var ranges: [Range<Int>] = []
        var idx = 0
        while idx < ops.count {
            if case .context = ops[idx] {
                idx += 1
                continue
            }
            let changeStart = idx
            while idx < ops.count {
                if case .context = ops[idx] { break }
                idx += 1
            }
            let changeEnd = idx
            let expandedStart = max(0, changeStart - contextLines)
            let expandedEnd = min(ops.count, changeEnd + contextLines)

            if let last = ranges.last, expandedStart <= last.upperBound {
                ranges[ranges.count - 1] = last.lowerBound..<max(last.upperBound, expandedEnd)
            } else {
                ranges.append(expandedStart..<expandedEnd)
            }
        }

        var hunks: [FileDiffHunk] = []
        hunks.reserveCapacity(ranges.count)
        var hunkID = startingHunkID

        for range in ranges {
            var added = 0
            var removed = 0
            var lines: [FileDiffLine] = []
            lines.reserveCapacity(min(range.count, maxLinesPerHunk))

            var lineID = 0
            for opIndex in range {
                let op = ops[opIndex]
                switch op {
                case let .context(text):
                    if lines.count < maxLinesPerHunk {
                        lines.append(FileDiffLine(id: lineID, kind: .context, text: text))
                        lineID += 1
                    }
                case let .removed(text):
                    removed += 1
                    if lines.count < maxLinesPerHunk {
                        lines.append(FileDiffLine(id: lineID, kind: .removed, text: text))
                        lineID += 1
                    }
                case let .added(text):
                    added += 1
                    if lines.count < maxLinesPerHunk {
                        lines.append(FileDiffLine(id: lineID, kind: .added, text: text))
                        lineID += 1
                    }
                }
            }

            hunks.append(
                FileDiffHunk(
                    id: hunkID,
                    lines: lines,
                    addedCount: added,
                    removedCount: removed
                )
            )
            hunkID += 1
        }

        return hunks
    }
}
