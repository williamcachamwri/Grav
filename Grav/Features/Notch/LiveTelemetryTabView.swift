import SwiftUI

/// Live telemetry overview combining the collapsible Thinking Glass Card
/// with a magnetic-hover, real-time animated unified activity stream.
public struct LiveTelemetryTabView: View {
    public var store: AntigravityTelemetryStore
    public var onInspectFile: (FileChangeEvent) -> Void
    public var onInspectCommand: (CommandExecutionEvent) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var activityHoverNamespace

    @State private var isThinkingExpanded: Bool = true
    @State private var hoveredActivityID: String?
    @State private var loadingStepIndex: Int?
    @State private var loadedFullThoughts: [Int: String] = [:]
    @State private var didCopyThought: Bool = false

    public init(
        store: AntigravityTelemetryStore,
        onInspectFile: @escaping (FileChangeEvent) -> Void = { _ in },
        onInspectCommand: @escaping (CommandExecutionEvent) -> Void = { _ in }
    ) {
        self.store = store
        self.onInspectFile = onInspectFile
        self.onInspectCommand = onInspectCommand
    }

    private var displayedThinking: ThinkingSnapshot? {
        store.currentThinking ?? store.thinkingHistory.first
    }

    private var hasAnyTelemetry: Bool {
        displayedThinking != nil || !store.recentActivity.isEmpty
    }

    public var body: some View {
        Group {
            if !hasAnyTelemetry {
                quietEmptyState
            } else {
                VStack(spacing: 7) {
                    if let snapshot = displayedThinking {
                        thinkingGlassCard(for: snapshot)
                    }

                    activityFeedSection
                }
                .animation(reduceMotion ? nil : GravMotionSpec.settle.animation, value: store.recentActivity.first?.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Thinking Glass Card

    private func thinkingGlassCard(for snapshot: ThinkingSnapshot) -> some View {
        let resolvedText = (loadedFullThoughts[snapshot.stepIndex] ?? snapshot.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let needsFullLoad = snapshot.isTruncated
            && !snapshot.isFullTextLoaded
            && loadedFullThoughts[snapshot.stepIndex] == nil
        let isLoadingFull = loadingStepIndex == snapshot.stepIndex
        let modelLabel = snapshot.model ?? store.activeModel

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    if reduceMotion {
                        isThinkingExpanded.toggle()
                    } else {
                        withAnimation(GravMotion.contentSlide) {
                            isThinkingExpanded.toggle()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        NotchSemanticDot(
                            color: snapshot.isActive ? GravPalette.thinking : GravPalette.thinking.opacity(0.55),
                            size: 5.5,
                            isPulsing: snapshot.isActive && !store.isPaused
                        )

                        Text(snapshot.isActive ? "Thinking" : "Latest Thought")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(-0.1)
                            .foregroundStyle(snapshot.isActive ? GravPalette.thinking : Color.white.opacity(0.76))

                        if let modelLabel, !modelLabel.isEmpty {
                            Text(modelLabel)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.46))
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        ActiveElapsedTimerText(
                            startDate: snapshot.startedAt,
                            endDate: snapshot.completedAt,
                            isActive: snapshot.isActive && !store.isPaused,
                            font: .system(size: 10, weight: .medium, design: .monospaced),
                            color: Color.white.opacity(0.54)
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !resolvedText.isEmpty {
                    Button {
                        NotchTelemetryHelpers.copyToPasteboard(resolvedText)
                        didCopyThought = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.2))
                            didCopyThought = false
                        }
                    } label: {
                        Image(systemName: didCopyThought ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(didCopyThought ? GravPalette.emerald : Color.white.opacity(0.45))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Copy Thought (⌘C)")
                }

                Button {
                    if reduceMotion {
                        isThinkingExpanded.toggle()
                    } else {
                        withAnimation(GravMotion.contentSlide) {
                            isThinkingExpanded.toggle()
                        }
                    }
                } label: {
                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .frame(width: 16, height: 18)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if isThinkingExpanded {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 5) {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(resolvedText.isEmpty ? "Streaming reasoning tokens…" : resolvedText)
                                    .font(.system(size: 11.5, weight: .regular))
                                    .lineSpacing(3)
                                    .foregroundStyle(Color.white.opacity(0.84))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 5)
                                    .padding(.bottom, 4)

                                Color.clear
                                    .frame(height: 1)
                                    .id("thinking-stream-tail")
                            }
                        }
                        .frame(maxHeight: store.recentActivity.isEmpty ? 154 : 68)
                        .mask(thinkingScrollMask)
                        .onChange(of: resolvedText) { _, _ in
                            guard snapshot.isActive else { return }
                            if reduceMotion {
                                proxy.scrollTo("thinking-stream-tail", anchor: .bottom)
                            } else {
                                withAnimation(.easeOut(duration: 0.14)) {
                                    proxy.scrollTo("thinking-stream-tail", anchor: .bottom)
                                }
                            }
                        }
                        .onAppear {
                            if snapshot.isActive {
                                proxy.scrollTo("thinking-stream-tail", anchor: .bottom)
                            }
                        }
                    }

                    if needsFullLoad {
                        HStack {
                            Spacer()
                            Button {
                                loadFullThought(stepIndex: snapshot.stepIndex)
                            } label: {
                                HStack(spacing: 4) {
                                    if isLoadingFull {
                                        OpticalCommandSpinner(isActive: true, size: 8, tint: GravPalette.glacialCyan)
                                    } else {
                                        Image(systemName: "arrow.down.doc")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    Text(isLoadingFull ? "Loading…" : "Load full thought")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(GravPalette.glacialCyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(NotchChromeButtonStyle(cornerRadius: 6))
                            .disabled(isLoadingFull)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.035),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    snapshot.isActive ? GravPalette.thinking.opacity(0.30) : Color.white.opacity(0.14),
                                    Color.white.opacity(0.04),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
        )
    }

    private var thinkingScrollMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.03),
                .init(color: .black, location: 0.91),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func loadFullThought(stepIndex: Int) {
        guard loadingStepIndex != stepIndex else { return }
        loadingStepIndex = stepIndex
        Task { @MainActor in
            let step = await store.loadFullStep(stepIndex: stepIndex)
            if let fullThinking = step?.thinking, !fullThinking.isEmpty {
                loadedFullThoughts[stepIndex] = fullThinking
            }
            if loadingStepIndex == stepIndex {
                loadingStepIndex = nil
            }
        }
    }

    // MARK: - Unified Recent Activity Feed

    private var activityFeedSection: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 3) {
                ForEach(store.recentActivity) { item in
                    activityRow(for: item)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98)),
                                    removal: .opacity
                                )
                        )
                }
            }
            .padding(.vertical, 2)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activityRow(for item: TelemetryActivityItem) -> some View {
        let isHovered = hoveredActivityID == item.id

        return Button {
            handleActivityTap(item)
        } label: {
            HStack(spacing: 8) {
                activityIconBadge(for: item)

                activityLabel(for: item)

                Spacer(minLength: 6)

                activityTrailingMetric(for: item)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color.white.opacity(0.065))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "live-activity-hover-pill", in: activityHoverNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                hoveredActivityID = hovering ? item.id : (hoveredActivityID == item.id ? nil : hoveredActivityID)
            } else {
                withAnimation(GravMotion.rowHover) {
                    if hovering {
                        hoveredActivityID = item.id
                    } else if hoveredActivityID == item.id {
                        hoveredActivityID = nil
                    }
                }
            }
        }
    }

    private func activityIconBadge(for item: TelemetryActivityItem) -> some View {
        let info = activityBadgeSpec(for: item)
        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(info.color.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(info.color.opacity(0.28), lineWidth: 0.5)
                )

            Image(systemName: info.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(info.color)
        }
        .frame(width: 18, height: 18)
    }

    private func activityBadgeSpec(for item: TelemetryActivityItem) -> (symbol: String, color: Color) {
        switch item {
        case .thinking:
            return ("waveform.path.ecg", GravPalette.thinking)
        case let .fileChange(event):
            switch event.kind {
            case .create: return ("plus", GravPalette.emerald)
            case .edit, .overwrite: return ("pencil.line", GravPalette.fileEdit)
            case .delete: return ("trash.fill", GravPalette.coral)
            }
        case let .command(command):
            switch command.status {
            case .running: return ("terminal.fill", GravPalette.glacialCyan)
            case .succeeded: return ("terminal.fill", GravPalette.emerald)
            case .failed: return ("exclamationmark.triangle.fill", GravPalette.coral)
            }
        }
    }

    @ViewBuilder
    private func activityLabel(for item: TelemetryActivityItem) -> some View {
        switch item {
        case let .thinking(snapshot):
            let singleLine = snapshot.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Text(singleLine.isEmpty ? "Reasoning step #\(snapshot.stepIndex)" : singleLine)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)

        case let .fileChange(event):
            HStack(spacing: 6) {
                Text(event.basename)
                    .font(.system(size: 11.5, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(NotchTelemetryHelpers.compactParentPath(for: event.path))
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.36))
                    .lineLimit(1)
                    .truncationMode(.head)
            }

        case let .command(command):
            Text(command.displayTitle)
                .font(.system(size: 11.5, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func activityTrailingMetric(for item: TelemetryActivityItem) -> some View {
        switch item {
        case let .thinking(snapshot):
            ActiveElapsedTimerText(
                startDate: snapshot.startedAt,
                endDate: snapshot.completedAt,
                isActive: snapshot.isActive && !store.isPaused,
                font: .system(size: 10, weight: .medium, design: .monospaced),
                color: Color.white.opacity(0.46)
            )

        case let .fileChange(event):
            NotchProportionalDiffMicroBar(
                added: event.addedLines,
                removed: event.removedLines,
                isDeleted: event.kind == .delete,
                showBar: false
            )

        case let .command(command):
            HStack(spacing: 5) {
                if let code = command.exitCode, command.status != .running, code != 0 {
                    Text("exit \(code)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(GravPalette.coral)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Capsule(style: .continuous).fill(GravPalette.coral.opacity(0.14)))
                }
                ActiveElapsedTimerText(
                    startDate: command.startedAt,
                    endDate: command.completedAt,
                    isActive: command.status == .running && !store.isPaused,
                    font: .system(size: 10, weight: .medium, design: .monospaced),
                    color: Color.white.opacity(0.46)
                )
            }
        }
    }

    private func handleActivityTap(_ item: TelemetryActivityItem) {
        switch item {
        case .thinking:
            if !isThinkingExpanded {
                if reduceMotion {
                    isThinkingExpanded = true
                } else {
                    withAnimation(GravMotion.contentSlide) {
                        isThinkingExpanded = true
                    }
                }
            }
        case let .fileChange(event):
            onInspectFile(event)
        case let .command(command):
            onInspectCommand(command)
        }
    }

    // MARK: - Quiet Empty State

    private var quietEmptyState: some View {
        VStack(spacing: 8) {
            GravAppIconTile(size: 26)
                .opacity(0.85)

            Text("Telemetry Standby")
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.76))

            Text(
                store.isPaused
                    ? "Monitoring is paused. Resume from the menu bar to stream live activity."
                    : "Waiting for Antigravity reasoning, file mutations, or terminal output."
            )
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.42))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 310)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
