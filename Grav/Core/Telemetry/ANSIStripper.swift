import Foundation

/// High-speed ANSI escape sequence stripper and terminal carriage-return normalizer
/// for live Antigravity task logs and completed command outputs.
public enum ANSIStripper: Sendable {
    /// Strips ANSI CSI/OSC/SGR/DCS/APC escape sequences and normalizes carriage returns (`\r\n` and
    /// inline progress-bar `\r` overwrites) into clean plain text.
    public static func strip(_ input: String) -> String {
        guard !input.isEmpty else { return "" }

        // Fast path: if no ESC (0x1B), C1 CSI (0x9B), CR (0x0D), or BEL (0x07) exists, return verbatim.
        let needsWork = input.unicodeScalars.contains { scalar in
            let v = scalar.value
            return v == 0x1B || v == 0x9B || v == 0x0D || v == 0x07 || v == 0x00
        }
        guard needsWork else { return input }

        let scalars = Array(input.unicodeScalars)
        let count = scalars.count
        var output: [UnicodeScalar] = []
        output.reserveCapacity(count)

        var lineStartIndex = 0
        var i = 0

        while i < count {
            let scalar = scalars[i]
            let v = scalar.value

            // Handle ESC-prefixed escape sequences
            if v == 0x1B {
                i = advancePastEscapeSequence(scalars, startingAt: i)
                continue
            }

            // Handle 8-bit C1 CSI (0x9B)
            if v == 0x9B {
                i = advancePastCSI(scalars, startingAt: i + 1)
                continue
            }

            // Normalize CRLF -> LF and standalone CR -> overwrite current line
            if v == 0x0D {
                if i + 1 < count, scalars[i + 1].value == 0x0A {
                    output.append("\n")
                    lineStartIndex = output.count
                    i += 2
                } else {
                    // Only clear the current line if subsequent characters overwrite it on the same line
                    if i + 1 < count, scalars[i + 1].value != 0x0D {
                        output.removeSubrange(lineStartIndex..<output.count)
                    }
                    i += 1
                }
                continue
            }

            if v == 0x0A {
                output.append(scalar)
                lineStartIndex = output.count
                i += 1
                continue
            }

            // Drop stray BEL and NUL bytes
            if v == 0x07 || v == 0x00 {
                i += 1
                continue
            }

            output.append(scalar)
            i += 1
        }

        return String(String.UnicodeScalarView(output))
    }

    // MARK: - Escape Sequence Scanners

    internal static func advancePastEscapeSequence(_ scalars: [UnicodeScalar], startingAt start: Int) -> Int {
        let count = scalars.count
        let next = start + 1
        guard next < count else { return count }

        let intro = scalars[next].value
        switch intro {
        case 0x5B: // '[' -> CSI
            return advancePastCSI(scalars, startingAt: next + 1)
        case 0x5D: // ']' -> OSC (terminated by BEL or ST `ESC \`)
            return advancePastOSC(scalars, startingAt: next + 1)
        case 0x50, 0x58, 0x5E, 0x5F: // DCS ('P'), SOS ('X'), PM ('^'), APC ('_') -> ST terminated
            return advancePastStringTerminator(scalars, startingAt: next + 1)
        case 0x28, 0x29, 0x2A, 0x2B, 0x2D, 0x2E, 0x2F: // Charset designation ESC ( X
            return min(count, next + 2)
        default:
            // Standard 2-byte escape sequence (ESC + final byte)
            return next + 1
        }
    }

    internal static func advancePastCSI(_ scalars: [UnicodeScalar], startingAt start: Int) -> Int {
        let count = scalars.count
        var i = start
        // Parameter bytes: 0x30...0x3F ('0'...'?')
        while i < count {
            let v = scalars[i].value
            if v >= 0x30 && v <= 0x3F {
                i += 1
            } else {
                break
            }
        }
        // Intermediate bytes: 0x20...0x2F (' '...'/' )
        while i < count {
            let v = scalars[i].value
            if v >= 0x20 && v <= 0x2F {
                i += 1
            } else {
                break
            }
        }
        // Final byte: 0x40...0x7E ('@'...'~')
        if i < count {
            let v = scalars[i].value
            if v >= 0x40 && v <= 0x7E {
                return i + 1
            }
        }
        return i
    }

    internal static func advancePastOSC(_ scalars: [UnicodeScalar], startingAt start: Int) -> Int {
        let count = scalars.count
        var i = start
        while i < count {
            let v = scalars[i].value
            if v == 0x07 { // BEL
                return i + 1
            }
            if v == 0x1B, i + 1 < count, scalars[i + 1].value == 0x5C { // ST (ESC \)
                return i + 2
            }
            if v == 0x9C { // 8-bit ST
                return i + 1
            }
            i += 1
        }
        return count
    }

    internal static func advancePastStringTerminator(_ scalars: [UnicodeScalar], startingAt start: Int) -> Int {
        let count = scalars.count
        var i = start
        while i < count {
            let v = scalars[i].value
            if v == 0x1B, i + 1 < count, scalars[i + 1].value == 0x5C {
                return i + 2
            }
            if v == 0x9C {
                return i + 1
            }
            i += 1
        }
        return count
    }
}
