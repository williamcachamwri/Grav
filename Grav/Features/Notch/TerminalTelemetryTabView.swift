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
                HStack(spacing: GravSpacing.sm) {
                    commandListRail
                        .frame(width: 192)

                    if let command = resolvedSelectedCommand {
                        logInspectorDrawer(for: command)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

        return Button {
            selectCommand(command)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    NotchSemanticDot(
                        color: NotchTelemetryHelpers.color(for: command.status),
                        size: 6,
                        isPulsing: command.status == .running && !store.isPaused
                    )

                    Text(command.displayTitle)
                        .font(GravTypography.monoCaption)
                        .foregroundStyle(isSelected ? GravPalette.inkPrimary : GravPalette.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 6) {
                    if command.status == .running {
                        Text("RUNNING")
                            .font(GravTypography.monoMicro)
                            .foregroundStyle(GravPalette.inkTertiary)
                    } else if let exitCode = command.exitCode {
                        Text("exit \(exitCode)")
                            .font(GravTypography.monoMicro)
                            .monospacedDigit()
                            .foregroundStyle(exitCode == 0 ? GravPalette.emerald : GravPalette.coral)
                    } else {
                        Text(command.status == .succeeded ? "exit 0" : "failed")
                            .font(GravTypography.monoMicro)
                            .foregroundStyle(
                                command.status == .succeeded ? GravPalette.emerald : GravPalette.coral
                            )
                    }

                    Spacer(minLength: 4)

                    ActiveElapsedTimerText(
                        startDate: command.startedAt,
                        endDate: command.completedAt,
                        isActive: command.status == .running && !store.isPaused,
                        font: GravTypography.monoMicro,
                        color: GravPalette.inkQuaternary
                    )
                }
                .padding(.leading, 16)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    if isSelected {
                        RoundedRectangle.grav(GravRadius.controlS)
                            .fill(GravPalette.cardFillElevated)
                            .overlay(
                                RoundedRectangle.grav(GravRadius.controlS)
                                    .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                            )
                    } else if isHovered {
                        RoundedRectangle.grav(GravRadius.controlS)
                            .fill(GravPalette.cardFillBase)
                            .overlay(
                                RoundedRectangle.grav(GravRadius.controlS)
                                    .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                            )
                            .matchedGeometryEffect(id: "terminal-row-hover-pill", in: commandHoverNamespace)
                    }
                }
            }
            .contentShape(RoundedRectangle.grav(GravRadius.controlS))
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

    // MARK: - Live Log Inspector Drawer

    private func logInspectorDrawer(for command: CommandExecutionEvent) -> some View {
        let filteredLines = filteredLogLines(from: command.logOutput)
        let isCopied = copiedCommandID == command.id

        return VStack(alignment: .leading, spacing: 0) {
            // Drawer Header: Command line + Controls
            HStack(spacing: 5) {
                Text("$ \(command.commandLine)")
                    .font(GravTypography.monoMicro)
                    .foregroundStyle(GravPalette.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(command.commandLine)

                Spacer(minLength: 4)

                Button {
                    isAutoScrollEnabled.toggle()
                } label: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(
                            isAutoScrollEnabled ? GravPalette.glacialTeal : GravPalette.inkQuaternary
                        )
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(
                    NotchChromeButtonStyle(
                        isActive: isAutoScrollEnabled,
                        cornerRadius: GravRadius.controlXS
                    )
                )
                .help(isAutoScrollEnabled ? "Auto-scroll enabled" : "Auto-scroll paused")
                .accessibilityLabel(isAutoScrollEnabled ? "Disable log auto-scroll" : "Enable log auto-scroll")

                Button {
                    copyLog(for: command, filteredLines: filteredLines)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                        if isCopied {
                            Text("Copied")
                                .font(GravTypography.monoMicro)
                        }
                    }
                    .foregroundStyle(isCopied ? GravPalette.emerald : GravPalette.inkSecondary)
                    .padding(.horizontal, isCopied ? 6 : 0)
                    .frame(minWidth: 20, minHeight: 20)
                }
                .buttonStyle(
                    NotchChromeButtonStyle(
                        isActive: isCopied,
                        cornerRadius: GravRadius.controlXS
                    )
                )
                .help("Copy command output (⌘C)")
                .accessibilityLabel("Copy Log")
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 5)

            // Search Filter Strip
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(GravPalette.inkQuaternary)

                TextField("Filter logs…", text: $logFilter)
                    .textFieldStyle(.plain)
                    .font(GravTypography.monoMicro)
                    .foregroundStyle(GravPalette.inkPrimary)
                    .focused($filterFocus)

                if !logFilter.isEmpty {
                    Button {
                        logFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(GravPalette.inkQuaternary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear log filter")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle.grav(GravRadius.controlXS)
                    .fill(GravPalette.obsidianVoid.opacity(0.65))
            )
            .overlay(
                RoundedRectangle.grav(GravRadius.controlXS)
                    .strokeBorder(
                        filterFocus ? GravPalette.glacialTeal.opacity(0.55) : GravPalette.hairlineMid.opacity(0.55),
                        lineWidth: 0.5
                    )
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 5)

            Rectangle()
                .fill(GravPalette.hairlineMid.opacity(0.5))
                .frame(height: 0.5)

            // Streaming Log Viewport
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 1.5) {
                        if command.logOutput.isEmpty {
                            Text(
                                command.status == .running
                                    ? "Waiting for stdout / stderr…"
                                    : "No output captured."
                            )
                            .font(GravTypography.monoMicro)
                            .foregroundStyle(GravPalette.inkQuaternary)
                            .padding(.top, 6)
                        } else if filteredLines.isEmpty {
                            Text("No log lines match \"\(logFilter)\".")
                                .font(GravTypography.monoMicro)
                                .foregroundStyle(GravPalette.inkQuaternary)
                                .padding(.top, 6)
                        } else {
                            ForEach(Array(filteredLines.enumerated()), id: \.offset) { _, line in
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
                                .foregroundStyle(GravPalette.inkQuaternary)
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
        .notchGlassSurface(.subtle, cornerRadius: GravRadius.controlM)
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
        return GravPalette.inkSecondary
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
        VStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(GravPalette.inkQuaternary)

            Text("NO COMMAND EXECUTIONS")
                .font(GravTypography.monoMicro)
                .foregroundStyle(GravPalette.inkTertiary)

            Text("Active and recent Antigravity terminal commands will stream live output here.")
                .font(GravTypography.caption)
                .foregroundStyle(GravPalette.inkQuaternary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
