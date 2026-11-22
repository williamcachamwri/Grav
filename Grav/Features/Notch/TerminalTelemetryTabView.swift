import SwiftUI

/// Split command execution monitor and live-streaming monospaced Log Inspector Drawer.
public struct TerminalTelemetryTabView: View {
    public var store: AntigravityTelemetryStore
    @Binding public var selectedCommandID: String?
    @Binding public var isSearchFieldFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var commandHoverNamespace
    @FocusState private var filterFocus: Bool

    @State private var hoveredCommandID: String?
    @State private var logFilter: String = ""
    @State private var isAutoScrollEnabled: Bool = true
    @State private var copiedCommandID: String?
    @State private var copyFeedbackTask: Task<Void, Never>?

    public init(
        store: AntigravityTelemetryStore,
        selectedCommandID: Binding<String?>,
        isSearchFieldFocused: Binding<Bool> = .constant(false)
    ) {
        self.store = store
        self._selectedCommandID = selectedCommandID
        self._isSearchFieldFocused = isSearchFieldFocused
    }

    private var resolvedSelectedCommand: CommandExecutionEvent? {
        if let id = selectedCommandID,
           let match = store.commands.first(where: { $0.id == id })
        {
            return match
        }
        return store.activeCommand ?? store.commands.first
    }

    public var body: some View {
        Group {
            if store.commands.isEmpty {
                emptyState
            } else {
                HStack(spacing: 7) {
                    commandListRail
                        .frame(width: 176)

                    if let command = resolvedSelectedCommand {
                        logInspectorDrawer(for: command)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : GravMotionSpec.settle.animation, value: store.commands.first?.id)
        .onAppear {
            if selectedCommandID == nil, let initial = store.activeCommand ?? store.commands.first {
                selectedCommandID = initial.id
            }
        }
        .onChange(of: store.commands.first?.id) { _, newestID in
            if selectedCommandID == nil, let newestID {
                selectedCommandID = newestID
            }
        }
        .onChange(of: filterFocus) { _, focused in
            isSearchFieldFocused = focused
        }
        .onDisappear {
            isSearchFieldFocused = false
            copyFeedbackTask?.cancel()
        }
    }

    // MARK: - Command Executions List

    private var commandListRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 3) {
                ForEach(store.commands) { command in
                    commandRow(for: command)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: .infinity)
    }

    private func commandRow(for command: CommandExecutionEvent) -> some View {
        let isSelected = resolvedSelectedCommand?.id == command.id
        let isHovered = hoveredCommandID == command.id
        let statusTint = NotchTelemetryHelpers.color(for: command.status)

        return Button {
            selectCommand(command)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    NotchSemanticDot(
                        color: statusTint,
                        size: 5.5,
                        isPulsing: command.status == .running && !store.isPaused
                    )

                    Text(command.displayTitle)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .tracking(-0.1)
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.80))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 5) {
                    if command.status == .running {
                        Text("Running")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(GravPalette.glacialCyan)
                    } else if let exitCode = command.exitCode {
                        Text("Exit \(exitCode)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(exitCode == 0 ? GravPalette.emerald : GravPalette.coral)
                    } else {
                        Text(command.status == .succeeded ? "Exit 0" : "Failed")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(
                                command.status == .succeeded ? GravPalette.emerald : GravPalette.coral
                            )
                    }

                    Spacer(minLength: 4)

                    ActiveElapsedTimerText(
                        startDate: command.startedAt,
                        endDate: command.completedAt,
                        isActive: command.status == .running && !store.isPaused,
                        font: .system(size: 9.5, weight: .medium, design: .monospaced),
                        color: Color.white.opacity(0.42)
                    )
                }
                .padding(.leading, 15)
            }
            .padding(.horizontal, 7.5)
            .padding(.vertical, 5.5)
            .background {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .fill(Color.white.opacity(0.095))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                            )
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .fill(Color.white.opacity(0.055))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                            .matchedGeometryEffect(id: "terminal-row-hover-pill", in: commandHoverNamespace)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                hoveredCommandID = hovering ? command.id : (hoveredCommandID == command.id ? nil : hoveredCommandID)
            } else {
                withAnimation(GravMotion.rowHover) {
                    if hovering {
                        hoveredCommandID = command.id
                    } else if hoveredCommandID == command.id {
                        hoveredCommandID = nil
                    }
                }
            }
        }
    }

    // MARK: - Live Log Inspector Drawer (Single-Line Unified Header + Maximum Viewport)

    private static let maxRenderedLogLines = 400

    private func logInspectorDrawer(for command: CommandExecutionEvent) -> some View {
        let allFilteredLines = filteredLogLines(from: command.logOutput)
        let omittedLineCount = max(0, allFilteredLines.count - Self.maxRenderedLogLines)
        let renderedLines: [String] = omittedLineCount > 0
            ? Array(allFilteredLines.suffix(Self.maxRenderedLogLines))
            : allFilteredLines
        let isCopied = copiedCommandID == command.id

        return VStack(alignment: .leading, spacing: 0) {
            // Unified Header: $ Command + Compact Search Capsule + Auto-Scroll + Copy Log
            HStack(spacing: 5) {
                Text("$ \(command.commandLine)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(command.commandLine)

                Spacer(minLength: 4)

                // Compact inline filter pill
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.38))

                    TextField("Filter…", text: $logFilter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .focused($filterFocus)
                        .frame(width: 68)

                    if !logFilter.isEmpty {
                        Button {
                            logFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 8.5))
                                .foregroundStyle(Color.white.opacity(0.42))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear log filter")
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: 19)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.45))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    filterFocus ? GravPalette.glacialCyan.opacity(0.55) : Color.white.opacity(0.10),
                                    lineWidth: 0.5
                                )
                        )
                )

                Button {
                    isAutoScrollEnabled.toggle()
                } label: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(
                            isAutoScrollEnabled ? GravPalette.glacialCyan : Color.white.opacity(0.40)
                        )
                        .frame(width: 19, height: 19)
                }
                .buttonStyle(NotchChromeButtonStyle(isActive: isAutoScrollEnabled, cornerRadius: 5.5))
                .help(isAutoScrollEnabled ? "Auto-scroll enabled" : "Auto-scroll paused")
                .accessibilityLabel(isAutoScrollEnabled ? "Disable log auto-scroll" : "Enable log auto-scroll")

                Button {
                    copyLog(for: command, filteredLines: allFilteredLines)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                        if isCopied {
                            Text("Copied")
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .foregroundStyle(isCopied ? GravPalette.emerald : Color.white.opacity(0.68))
                    .padding(.horizontal, isCopied ? 5.5 : 0)
                    .frame(minWidth: 19, minHeight: 19)
                }
                .buttonStyle(NotchChromeButtonStyle(isActive: isCopied, cornerRadius: 5.5))
                .help("Copy command output (⌘C)")
                .accessibilityLabel("Copy Log")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            // Streaming Log Viewport
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 1.5) {
                        if command.logOutput.isEmpty {
                            Text(
                                command.status == .running
                                    ? "Streaming stdout / stderr…"
                                    : "No output captured."
                            )
                            .font(GravTypography.monoMicro)
                            .foregroundStyle(Color.white.opacity(0.36))
                            .padding(.top, 6)
                        } else if allFilteredLines.isEmpty {
                            Text("No log lines match \"\(logFilter)\".")
                                .font(GravTypography.monoMicro)
                                .foregroundStyle(Color.white.opacity(0.36))
                                .padding(.top, 6)
                        } else {
                            if omittedLineCount > 0 {
                                Text("— latest \(Self.maxRenderedLogLines) of \(allFilteredLines.count) lines (Copy Log for full output) —")
                                    .font(GravTypography.monoMicro)
                                    .foregroundStyle(Color.white.opacity(0.35))
                                    .padding(.bottom, 3)
                            }
                            ForEach(Array(renderedLines.enumerated()), id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(GravTypography.monoMicro)
                                    .foregroundStyle(logLineColor(line))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if command.isTruncated {
                            Text("— log output truncated —")
                                .font(GravTypography.monoMicro)
                                .foregroundStyle(Color.white.opacity(0.35))
                                .padding(.top, 4)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("terminal-log-tail")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: command.logOutput) { _, _ in
                    scrollToLogTail(proxy: proxy)
                }
                .onChange(of: command.id) { _, _ in
                    scrollToLogTail(proxy: proxy)
                }
                .onAppear {
                    scrollToLogTail(proxy: proxy)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                .fill(Color.white.opacity(0.038))
                .overlay(
                    RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Helpers

    private func selectCommand(_ command: CommandExecutionEvent) {
        selectedCommandID = command.id
    }

    private func scrollToLogTail(proxy: ScrollViewProxy) {
        guard isAutoScrollEnabled else { return }
        if reduceMotion {
            proxy.scrollTo("terminal-log-tail", anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.14)) {
                proxy.scrollTo("terminal-log-tail", anchor: .bottom)
            }
        }
    }

    private func filteredLogLines(from output: String) -> [String] {
        guard !output.isEmpty else { return [] }
        let rawLines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let query = logFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rawLines }
        return rawLines.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func logLineColor(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error:") || lower.contains("fatal:") || lower.contains("failed") {
            return GravPalette.coral.opacity(0.92)
        }
        if lower.contains("warning:") {
            return GravPalette.fileEdit.opacity(0.90)
        }
        return Color.white.opacity(0.80)
    }

    private func copyLog(for command: CommandExecutionEvent, filteredLines: [String]) {
        let text: String
        if logFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = command.logOutput
        } else {
            text = filteredLines.joined(separator: "\n")
        }
        NotchTelemetryHelpers.copyToPasteboard(text)
        copiedCommandID = command.id
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            if copiedCommandID == command.id {
                copiedCommandID = nil
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "terminal")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.32))

            Text("No Command Executions")
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.76))

            Text("Active and recent Antigravity terminal commands will stream live output here.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
