import Foundation

/// Pure shell command parser that extracts deleted file paths from `rm`, `git rm`, and `unlink`
/// invocations inside Antigravity `run_command` `CommandLine` payloads.
public enum DestructiveCommandParser: Sendable {
    private enum Token: Equatable {
        case word(String)
        case separator
    }

    /// Extracts ordered, deduplicated file paths targeted for deletion by `rm`, `git rm`, or `unlink`
    /// commands in a shell command line.
    public static func extractDeletedPaths(from commandLine: String) -> [String] {
        guard !commandLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let segments = splitIntoCommandSegments(commandLine)
        var currentDirectory: String?
        var results: [String] = []
        var seen = Set<String>()

        for rawTokens in segments {
            let tokens = stripRedirections(from: rawTokens)
            guard !tokens.isEmpty else { continue }

            let startIndex = skipLeadingPrefixes(in: tokens)
            guard startIndex < tokens.count else { continue }

            let command = basenameCommand(tokens[startIndex])
            let remaining = Array(tokens[(startIndex + 1)...])

            if command == "cd" {
                if let targetDir = parseChangeDirectoryTarget(remaining) {
                    currentDirectory = resolvePath(targetDir, relativeTo: currentDirectory)
                }
                continue
            }

            let extracted: [String]
            switch command {
            case "rm":
                extracted = parseRmArguments(remaining, workingDirectory: currentDirectory)
            case "unlink":
                extracted = parseUnlinkArguments(remaining, workingDirectory: currentDirectory)
            case "git":
                extracted = parseGitRmArguments(remaining, workingDirectory: currentDirectory)
            default:
                extracted = []
            }

            for path in extracted where !seen.contains(path) {
                seen.insert(path)
                results.append(path)
            }
        }

        return results
    }

    // MARK: - Lexer & Command Splitting

    private static func splitIntoCommandSegments(_ input: String) -> [[String]] {
        let tokens = tokenize(input)
        var segments: [[String]] = []
        var current: [String] = []

        for token in tokens {
            switch token {
            case let .word(word):
                current.append(word)
            case .separator:
                if !current.isEmpty {
                    segments.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            }
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    private static func tokenize(_ input: String) -> [Token] {
        let chars = Array(input)
        let count = chars.count
        var tokens: [Token] = []
        var current = ""
        var inToken = false
        var quote: Character? = nil
        var i = 0

        func flushWord() {
            if inToken {
                tokens.append(.word(current))
                current.removeAll(keepingCapacity: true)
                inToken = false
            }
        }

        while i < count {
            let ch = chars[i]

            if let activeQuote = quote {
                if activeQuote == "'" {
                    if ch == "'" {
                        quote = nil
                    } else {
                        current.append(ch)
                    }
                    i += 1
                    continue
                } else { // Double quotes
                    if ch == "\\" && i + 1 < count {
                        let next = chars[i + 1]
                        if next == "\"" || next == "\\" || next == "$" || next == "`" {
                            current.append(next)
                            i += 2
                            continue
                        }
                    }
                    if ch == "\"" {
                        quote = nil
                    } else {
                        current.append(ch)
                    }
                    i += 1
                    continue
                }
            }

            // Unquoted backslash escape
            if ch == "\\" && i + 1 < count {
                let next = chars[i + 1]
                if next == "\n" {
                    i += 2
                    continue
                }
                current.append(next)
                inToken = true
                i += 2
                continue
            }

            // Quote start
            if ch == "'" || ch == "\"" {
                quote = ch
                inToken = true
                i += 1
                continue
            }

            // Comment until end of line (only at start of word)
            if ch == "#" && !inToken {
                while i < count && chars[i] != "\n" {
                    i += 1
                }
                continue
            }

            // Command separators: &&, ||, ;, |, \n
            if ch == ";" || ch == "\n" {
                flushWord()
                tokens.append(.separator)
                i += 1
                continue
            }
            if ch == "&" {
                if i + 1 < count, chars[i + 1] == "&" {
                    flushWord()
                    tokens.append(.separator)
                    i += 2
                    continue
                }
                // Handle `2>&1` or `&>` inside redirection tokens without splitting
                if !inToken {
                    flushWord()
                    tokens.append(.separator)
                    i += 1
                    continue
                }
            }
            if ch == "|" {
                flushWord()
                tokens.append(.separator)
                i += (i + 1 < count && chars[i + 1] == "|") ? 2 : 1
                continue
            }

            // Subshell / grouping parens
            if ch == "(" || ch == ")" {
                flushWord()
                tokens.append(.separator)
                i += 1
                continue
            }

            // Whitespace
            if ch == " " || ch == "\t" || ch == "\r" {
                flushWord()
                i += 1
                continue
            }

            current.append(ch)
            inToken = true
            i += 1
        }

        flushWord()
        return tokens
    }

    // MARK: - Redirection & Prefix Filtering

    private static func stripRedirections(from tokens: [String]) -> [String] {
        var cleaned: [String] = []
        cleaned.reserveCapacity(tokens.count)
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if isStandaloneRedirectionOperator(token) {
                // Skip operator and its target operand
                i += 2
                continue
            }
            if isAttachedRedirection(token) {
                i += 1
                continue
            }
            cleaned.append(token)
            i += 1
        }
        return cleaned
    }

    private static func isStandaloneRedirectionOperator(_ token: String) -> Bool {
        let operators: Set<String> = [">", ">>", "<", "2>", "2>>", "1>", "1>>", "&>", "&>>"]
        return operators.contains(token)
    }

    private static func isAttachedRedirection(_ token: String) -> Bool {
        if token.hasPrefix(">") || token.hasPrefix("<") || token.hasPrefix("&>") {
            return true
        }
        if let first = token.first, first.isNumber {
            let rest = token.dropFirst()
            if rest.hasPrefix(">") || rest.hasPrefix("<") {
                return true
            }
        }
        return false
    }

    private static func skipLeadingPrefixes(in tokens: [String]) -> Int {
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            // Shell control keywords that can precede a command (`then rm foo`, `do rm bar`)
            if token == "then" || token == "do" || token == "else" || token == "!" {
                i += 1
                continue
            }
            // Environment variable assignment (`FOO=bar`)
            if isEnvironmentAssignment(token) {
                i += 1
                continue
            }
            let base = basenameCommand(token)
            if base == "sudo" {
                i += 1
                // Skip sudo flags like `-u root` or `-E`
                while i < tokens.count, tokens[i].hasPrefix("-") {
                    let flag = tokens[i]
                    i += 1
                    if flag == "-u" || flag == "-g" || flag == "-C" || flag == "-p" {
                        i += 1
                    }
                }
                continue
            }
            if base == "env" {
                i += 1
                while i < tokens.count {
                    if tokens[i].hasPrefix("-") {
                        let flag = tokens[i]
                        i += 1
                        if flag == "-u" || flag == "-C" {
                            i += 1
                        }
                    } else if isEnvironmentAssignment(tokens[i]) {
                        i += 1
                    } else {
                        break
                    }
                }
                continue
            }
            if base == "command" || base == "nohup" || base == "time" {
                i += 1
                while i < tokens.count, tokens[i].hasPrefix("-") {
                    i += 1
                }
                continue
            }
            break
        }
        return i
    }

    private static func isEnvironmentAssignment(_ token: String) -> Bool {
        guard let eqIndex = token.firstIndex(of: "="), eqIndex > token.startIndex else {
            return false
        }
        let name = token[..<eqIndex]
        guard let first = name.first, first.isLetter || first == "_" else {
            return false
        }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func basenameCommand(_ token: String) -> String {
        if token.contains("/") {
            return URL(fileURLWithPath: token).lastPathComponent
        }
        return token
    }

    // MARK: - Command-Specific Parsers

    private static func parseChangeDirectoryTarget(_ args: [String]) -> String? {
        for arg in args {
            if arg == "--" { continue }
            if arg.hasPrefix("-") { continue }
            return arg
        }
        return nil
    }

    private static func parseRmArguments(_ args: [String], workingDirectory: String?) -> [String] {
        var paths: [String] = []
        var endOfOptions = false

        for arg in args {
            if !endOfOptions {
                if arg == "--" {
                    endOfOptions = true
                    continue
                }
                if arg.hasPrefix("-") && arg.count > 1 {
                    continue
                }
            }
            if let sanitized = sanitizeFilePath(arg, workingDirectory: workingDirectory) {
                paths.append(sanitized)
            }
        }
        return paths
    }

    private static func parseUnlinkArguments(_ args: [String], workingDirectory: String?) -> [String] {
        var paths: [String] = []
        var endOfOptions = false

        for arg in args {
            if !endOfOptions {
                if arg == "--" {
                    endOfOptions = true
                    continue
                }
                if arg.hasPrefix("-") && arg.count > 1 {
                    continue
                }
            }
            if let sanitized = sanitizeFilePath(arg, workingDirectory: workingDirectory) {
                paths.append(sanitized)
            }
        }
        return paths
    }

    private static func parseGitRmArguments(_ args: [String], workingDirectory: String?) -> [String] {
        var effectiveDir = workingDirectory
        var i = 0

        // Skip global git flags before subcommand (`git -C /repo --no-pager rm ...`)
        while i < args.count {
            let token = args[i]
            if token == "-C" || token == "--git-dir" || token == "--work-tree" || token == "-c" {
                if token == "-C", i + 1 < args.count {
                    effectiveDir = resolvePath(args[i + 1], relativeTo: effectiveDir)
                }
                i += 2
                continue
            }
            if token.hasPrefix("-C") && token.count > 2 {
                let dir = String(token.dropFirst(2))
                effectiveDir = resolvePath(dir, relativeTo: effectiveDir)
                i += 1
                continue
            }
            if token.hasPrefix("-") {
                i += 1
                continue
            }
            break
        }

        guard i < args.count, args[i] == "rm" else {
            return []
        }

        let rmArgs = Array(args[(i + 1)...])
        var paths: [String] = []
        var endOfOptions = false
        var isDryRun = false

        for arg in rmArgs {
            if !endOfOptions {
                if arg == "--" {
                    endOfOptions = true
                    continue
                }
                if arg == "-n" || arg == "--dry-run" {
                    isDryRun = true
                    continue
                }
                if arg.hasPrefix("-") && arg.count > 1 {
                    // Check combined short flags like `-rn`
                    if !arg.hasPrefix("--"), arg.dropFirst().contains("n") {
                        isDryRun = true
                    }
                    continue
                }
            }
            if let sanitized = sanitizeFilePath(arg, workingDirectory: effectiveDir) {
                paths.append(sanitized)
            }
        }

        return isDryRun ? [] : paths
    }

    // MARK: - Path Normalization

    private static func sanitizeFilePath(_ raw: String, workingDirectory: String?) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Skip non-file meta-tokens, bare wildcards, and unresolved shell variables
        let ignored: Set<String> = [".", "..", "/", "~", "*", "-", "fi", "done", "esac"]
        if ignored.contains(trimmed) { return nil }
        if trimmed.hasPrefix("$") || trimmed.hasPrefix("`") { return nil }

        return resolvePath(trimmed, relativeTo: workingDirectory)
    }

    private static func resolvePath(_ path: String, relativeTo workingDirectory: String?) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        if let workingDirectory, !workingDirectory.isEmpty {
            let base = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            return base.appendingPathComponent(path).standardizedFileURL.path
        }
        return path
    }
}
