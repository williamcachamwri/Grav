import SwiftUI

/// Live telemetry overview combining the collapsible Thinking Glass Ribbon
/// with a magnetic-hover unified recent activity stream.
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
                VStack(spacing: GravSpacing.sm) {
                    if let snapshot = displayedThinking {
                        thinkingGlassRibbon(for: snapshot)
                    }

                    activityFeedSection
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Thinking Glass Ribbon

    private func thinkingGlassRibbon(for snapshot: ThinkingSnapshot) -> some View {
        let resolvedText = loadedFullThoughts[snapshot.stepIndex] ?? snapshot.text
        let needsFullLoad = snapshot.isTruncated
            && !snapshot.isFullTextLoaded
            && loadedFullThoughts[snapshot.stepIndex] == nil
        let isLoadingFull = loadingStepIndex == snapshot.stepIndex
        let modelLabel = snapshot.model ?? store.activeModel

        return VStack(alignment: .leading, spacing: 0) {
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
                        color: snapshot.isActive ? GravPalette.thinking : GravPalette.idleDot,
                        size: 6,
                        isPulsing: snapshot.isActive && !store.isPaused
                    )

                    Text(snapshot.isActive ? "THINKING" : "LAST THOUGHT")
                        .font(GravTypography.monoMicro)
                        .foregroundStyle(snapshot.isActive ? GravPalette.thinking : GravPalette.inkTertiary)

                    if let modelLabel, !modelLabel.isEmpty {
                        Text(modelLabel)
                            .font(GravTypography.monoMicro)
                            .foregroundStyle(GravPalette.inkQuaternary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: GravSpacing.xs)

                    ActiveElapsedTimerText(
                        startDate: snapshot.startedAt,
                        endDate: snapshot.completedAt,
                        isActive: snapshot.isActive && !store.isPaused,
                        font: GravTypography.monoMicro,
                        color: GravPalette.inkTertiary
                    )

                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(GravPalette.inkQuaternary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isThinkingExpanded {
                Rectangle()
                    .fill(GravPalette.hairlineMid.opacity(0.6))
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 5) {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(resolvedText.isEmpty ? "Awaiting reasoning stream…" : resolvedText)
                                    .font(GravTypography.monoBody)
                                    .foregroundStyle(GravPalette.inkSecondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)

                                Color.clear
                                    .frame(height: 1)
                                    .id("thinking-stream-tail")
                            }
                        }
                        .frame(maxHeight: store.recentActivity.isEmpty ? 156 : 74)
                        .mask(verticalFadeMask)
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
                                        .font(GravTypography.monoMicro)
                                }
                                .foregroundStyle(GravPalette.glacialCyan)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(NotchChromeButtonStyle(cornerRadius: GravRadius.controlXS))
                            .disabled(isLoadingFull)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 7)
                .transition(.opacity)
            }
        }
        .notchGlassSurface(.base, cornerRadius: GravRadius.controlM)
    }

    private var verticalFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.86),
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
            LazyVStack(spacing: 2) {
                ForEach(store.recentActivity) { item in
                    activityRow(for: item)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activityRow(for item: TelemetryActivityItem) -> some View {
        let isHovered = hoveredActivityID == item.id

        return Button {
            handleActivityTap(item)
        } label: {
            HStack(spacing: 8) {
                NotchSemanticDot(
                    color: activityDotColor(for: item),
                    size: 6,
                    isPulsing: isActivityPulsing(item)
                )

                activityLabel(for: item)

                Spacer(minLength: GravSpacing.xs)

                activityTrailingMetric(for: item)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                if isHovered {
                    RoundedRectangle.grav(GravRadius.controlS)
                        .fill(GravPalette.cardFillBase)
                        .overlay(
                            RoundedRectangle.grav(GravRadius.controlS)
                                .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "live-activity-hover-pill", in: activityHoverNamespace)
                }
            }
            .contentShape(RoundedRectangle.grav(GravRadius.controlS))
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

    @ViewBuilder
    private func activityLabel(for item: TelemetryActivityItem) -> some View {
        switch item {
        case let .thinking(snapshot):
            let singleLine = snapshot.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Text(singleLine.isEmpty ? "Reasoning step #\(snapshot.stepIndex)" : singleLine)
                .font(GravTypography.body)
                .foregroundStyle(GravPalette.inkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

        case let .fileChange(event):
            HStack(spacing: 5) {
                Text(event.basename)
                    .font(GravTypography.monoBody)
                    .foregroundStyle(GravPalette.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(NotchTelemetryHelpers.compactParentPath(for: event.path))
                    .font(GravTypography.monoMicro)
                    .foregroundStyle(GravPalette.inkQuaternary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

        case let .command(command):
            Text(command.displayTitle)
                .font(GravTypography.monoBody)
                .foregroundStyle(GravPalette.inkPrimary)
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
                font: GravTypography.monoMicro,
                color: GravPalette.inkTertiary
            )

        case let .fileChange(event):
            NotchProportionalDiffMicroBar(
                added: event.addedLines,
                removed: event.removedLines,
                isDeleted: event.kind == .delete,
                showBar: false
            )

        case let .command(command):
            HStack(spacing: 6) {
                if let code = command.exitCode, command.status != .running {
                    Text("exit \(code)")
                        .font(GravTypography.monoMicro)
                        .monospacedDigit()
                        .foregroundStyle(code == 0 ? GravPalette.emerald : GravPalette.coral)
                }
                ActiveElapsedTimerText(
                    startDate: command.startedAt,
                    endDate: command.completedAt,
                    isActive: command.status == .running && !store.isPaused,
                    font: GravTypography.monoMicro,
                    color: GravPalette.inkTertiary
                )
            }
        }
    }

    private func activityDotColor(for item: TelemetryActivityItem) -> Color {
        switch item {
        case let .thinking(snapshot):
            return snapshot.isActive ? GravPalette.thinking : GravPalette.thinking.opacity(0.55)
        case let .fileChange(event):
            return NotchTelemetryHelpers.color(for: event.kind)
        case let .command(command):
            return NotchTelemetryHelpers.color(for: command.status)
        }
    }

    private func isActivityPulsing(_ item: TelemetryActivityItem) -> Bool {
        guard !store.isPaused else { return false }
        switch item {
        case let .thinking(snapshot):
            return snapshot.isActive
        case .fileChange:
            return false
        case let .command(command):
            return command.status == .running
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
        VStack(spacing: 7) {
            GravOrbitalMark(size: 20, tint: GravPalette.inkQuaternary)

            Text("TELEMETRY STANDBY")
                .font(GravTypography.monoMicro)
                .foregroundStyle(GravPalette.inkTertiary)

            Text(
                store.isPaused
                    ? "Monitoring is paused. Resume from the menu bar to stream live activity."
                    : "Waiting for Antigravity reasoning, file mutations, or terminal output."
            )
            .font(GravTypography.caption)
            .foregroundStyle(GravPalette.inkQuaternary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
