import Foundation

/// Semantic ANSI terminal color decoded from SGR escape sequences.
public enum ANSIColor: Sendable, Equatable, Hashable {
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
    case brightBlack
    case brightRed
    case brightGreen
    case brightYellow
    case brightBlue
    case brightMagenta
    case brightCyan
    case brightWhite
    case indexed(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}

/// Text attributes parsed from ANSI SGR codes.
public struct ANSIStyle: Sendable, Equatable, Hashable {
    public var foreground: ANSIColor?
    public var background: ANSIColor?
    public var isBold: Bool
    public var isDim: Bool
    public var isItalic: Bool
    public var isUnderlined: Bool

    public static let plain = ANSIStyle()

    public init(
        foreground: ANSIColor? = nil,
        background: ANSIColor? = nil,
        isBold: Bool = false,
        isDim: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.isBold = isBold
        self.isDim = isDim
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
    }
}

/// A contiguous styled text span produced by `ANSIStripper.parseSegments(_:)`.
public struct ANSISegment: Sendable, Equatable, Identifiable {
    public let id: Int
    public let text: String
    public let style: ANSIStyle

    public init(id: Int = 0, text: String, style: ANSIStyle = .plain) {
        self.id = id
        self.text = text
        self.style = style
    }
}

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

    /// Parses ANSI SGR sequences into structured `ANSISegment` spans while stripping non-SGR
    /// escape codes and normalizing `\r\n` line endings for monospaced terminal rendering.
    public static func parseSegments(_ input: String) -> [ANSISegment] {
        guard !input.isEmpty else { return [] }

        let scalars = Array(input.unicodeScalars)
        let count = scalars.count
        var segments: [ANSISegment] = []
        var buffer: [UnicodeScalar] = []
        var currentStyle = ANSIStyle.plain
        var nextID = 0
        var i = 0

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            let text = String(String.UnicodeScalarView(buffer))
            buffer.removeAll(keepingCapacity: true)
            if let last = segments.last, last.style == currentStyle {
                segments[segments.count - 1] = ANSISegment(
                    id: last.id,
                    text: last.text + text,
                    style: currentStyle
                )
            } else {
                segments.append(ANSISegment(id: nextID, text: text, style: currentStyle))
                nextID += 1
            }
        }

        while i < count {
            let scalar = scalars[i]
            let v = scalar.value

            if v == 0x1B {
                // Check for CSI SGR (`ESC [ ... m`)
                if i + 1 < count, scalars[i + 1].value == 0x5B {
                    let end = advancePastCSI(scalars, startingAt: i + 2)
                    if end > i + 2, scalars[end - 1].value == 0x6D { // 'm'
                        let paramsSlice = scalars[(i + 2)..<(end - 1)]
                        let newStyle = applySGR(params: paramsSlice, to: currentStyle)
                        if newStyle != currentStyle {
                            flushBuffer()
                            currentStyle = newStyle
                        }
                    }
                    i = end
                } else {
                    i = advancePastEscapeSequence(scalars, startingAt: i)
                }
                continue
            }

            if v == 0x9B {
                let end = advancePastCSI(scalars, startingAt: i + 1)
                if end > i + 1, scalars[end - 1].value == 0x6D {
                    let paramsSlice = scalars[(i + 1)..<(end - 1)]
                    let newStyle = applySGR(params: paramsSlice, to: currentStyle)
                    if newStyle != currentStyle {
                        flushBuffer()
                        currentStyle = newStyle
                    }
                }
                i = end
                continue
            }

            if v == 0x0D {
                if i + 1 < count, scalars[i + 1].value == 0x0A {
                    buffer.append("\n")
                    i += 2
                } else {
                    i += 1
                }
                continue
            }

            if v == 0x07 || v == 0x00 {
                i += 1
                continue
            }

            buffer.append(scalar)
            i += 1
        }

        flushBuffer()
        return segments
    }

    private static func applySGR(params: ArraySlice<UnicodeScalar>, to style: ANSIStyle) -> ANSIStyle {
        var updated = style
        let raw = String(String.UnicodeScalarView(params))
        if raw.isEmpty {
            return .plain
        }

        let codes = raw.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var idx = 0
        while idx < codes.count {
            let code = codes[idx]
            switch code {
            case 0:
                updated = .plain
            case 1:
                updated.isBold = true
            case 2:
                updated.isDim = true
            case 3:
                updated.isItalic = true
            case 4:
                updated.isUnderlined = true
            case 22:
                updated.isBold = false
                updated.isDim = false
            case 23:
                updated.isItalic = false
            case 24:
                updated.isUnderlined = false
            case 30...37:
                updated.foreground = standardColor(for: code - 30, bright: false)
            case 38:
                if let (color, consumed) = parseExtendedColor(codes: codes, startingAt: idx + 1) {
                    updated.foreground = color
                    idx += consumed
                }
            case 39:
                updated.foreground = nil
            case 40...47:
                updated.background = standardColor(for: code - 40, bright: false)
            case 48:
                if let (color, consumed) = parseExtendedColor(codes: codes, startingAt: idx + 1) {
                    updated.background = color
                    idx += consumed
                }
            case 49:
                updated.background = nil
            case 90...97:
                updated.foreground = standardColor(for: code - 90, bright: true)
            case 100...107:
                updated.background = standardColor(for: code - 100, bright: true)
            default:
                break
            }
            idx += 1
        }
        return updated
    }

    private static func standardColor(for offset: Int, bright: Bool) -> ANSIColor {
        switch (offset, bright) {
        case (0, false): return .black
        case (1, false): return .red
        case (2, false): return .green
        case (3, false): return .yellow
        case (4, false): return .blue
        case (5, false): return .magenta
        case (6, false): return .cyan
        case (7, false): return .white
        case (0, true): return .brightBlack
        case (1, true): return .brightRed
        case (2, true): return .brightGreen
        case (3, true): return .brightYellow
        case (4, true): return .brightBlue
        case (5, true): return .brightMagenta
        case (6, true): return .brightCyan
        default: return .brightWhite
        }
    }

    private static func parseExtendedColor(codes: [Int], startingAt start: Int) -> (ANSIColor, Int)? {
        guard start < codes.count else { return nil }
        let mode = codes[start]
        if mode == 5, start + 1 < codes.count {
            let value = UInt8(clamping: codes[start + 1])
            return (.indexed(value), 2)
        }
        if mode == 2, start + 3 < codes.count {
            let r = UInt8(clamping: codes[start + 1])
            let g = UInt8(clamping: codes[start + 2])
            let b = UInt8(clamping: codes[start + 3])
            return (.rgb(r, g, b), 4)
        }
        return nil
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
