import SwiftUI

/// Live telemetry overview pairing a serene editorial Thinking sheet with a clean,
/// zero-badge-clutter chronological activity stream.
public struct LiveTelemetryTabView: View {
    public var store: AntigravityTelemetryStore
    public var onInspectFile: (FileChangeEvent) -> Void
    public var onInspectCommand: (CommandExecutionEvent) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var activityHoverNamespace

    @State private var isThinkingExpanded: Bool = true
    @State private var isStepsExpanded: Bool = false
    @State private var selectedThoughtIndex: Int = 0
    @State private var hoveredActivityID: String?
    @State private var isHoveringThinkingHeader: Bool = false
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

    private var availableThoughts: [ThinkingSnapshot] {
        if !store.thinkingHistory.isEmpty {
            return store.thinkingHistory
        }
        if let current = store.currentThinking {
            return [current]
        }
        return []
    }

    private var displayedThinking: ThinkingSnapshot? {
        guard !availableThoughts.isEmpty else { return nil }
        let safeIndex = min(max(0, selectedThoughtIndex), availableThoughts.count - 1)
        return availableThoughts[safeIndex]
    }

    private var hasAnyTelemetry: Bool {
        displayedThinking != nil
            || !store.recentActivity.isEmpty
            || store.stepsProgress != nil
            || store.currentFocus != nil
    }

    public var body: some View {
        Group {
            if !hasAnyTelemetry {
                quietEmptyState
            } else {
                VStack(spacing: 7) {
                    if store.stepsProgress != nil || (store.currentFocus != nil && !store.isPaused) {
                        antigravityStepsAndFocusStrip
                    }

                    if let snapshot = displayedThinking {
                        thinkingEditorialSheet(for: snapshot)
                    }

                    activityFeedSection
                }
                .animation(reduceMotion ? nil : GravMotionSpec.settle.animation, value: store.recentActivity.first?.id)
                .animation(reduceMotion ? nil : GravMotionSpec.settle.animation, value: isStepsExpanded)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: store.thinkingHistory.first?.stepIndex) { _, _ in
            // Auto-snap back to the freshest streaming thought whenever a new step arrives
            selectedThoughtIndex = 0
        }
    }

    // MARK: - 1:1 Antigravity `Worked for Nm › ◔ X/Y steps` & Live Focus Strip

    private var antigravityStepsAndFocusStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let steps = store.stepsProgress {
                HStack(spacing: 7) {
                    workedDurationLabel

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.32))
                        .rotationEffect(.degrees(isStepsExpanded ? 90 : 0))

                    Button {
                        GravOnboardingWelcomeAudio.shared.playTabSwitch()
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.08)) {
                            isStepsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                                Circle()
                                    .trim(from: 0, to: CGFloat(max(0.06, steps.fraction)))
                                    .stroke(
                                        steps.isAllDone ? GravPalette.emerald : Color.white.opacity(0.90),
                                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 10, height: 10)

                            Text(steps.ratioLabel)
                                .font(.system(size: 10.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Color.white.opacity(0.86))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(isStepsExpanded ? 0.09 : 0.045))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(
                                            isStepsExpanded ? GravPalette.glacialCyan.opacity(0.55) : Color.white.opacity(0.10),
                                            lineWidth: 0.75
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 6)

                    if let activeTitle = steps.activeStep?.title, !isStepsExpanded {
                        Text(activeTitle)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.46))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if isStepsExpanded {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(steps.steps) { item in
                            HStack(spacing: 7) {
                                stepStatusGlyph(item.status)
                                Text(item.title)
                                    .font(.system(size: 11, weight: item.status == .inProgress ? .semibold : .regular))
                                    .foregroundStyle(stepTextColor(item.status))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .notchGlassSurface(.subtle, cornerRadius: 9)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if let focus = store.currentFocus, !focus.isEmpty, !store.isPaused {
                HStack(spacing: 6) {
                    NotchSemanticDot(color: GravPalette.glacialCyan, size: 4.5, isPulsing: store.state.isActive)
                    NotchShimmerText(
                        text: focus,
                        font: .system(size: 11, weight: .medium),
                        tracking: -0.1,
                        baseOpacity: 0.56,
                        peakOpacity: 0.96,
                        period: 1.9,
                        reduceMotion: reduceMotion
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder
    private var workedDurationLabel: some View {
        if store.state.isActive, let started = store.turnStartedAt {
            TimelineView(.periodic(from: started, by: 1.0)) { context in
                let elapsed = max(1, Int(context.date.timeIntervalSince(started)))
                Text("Worked for \(formatCompactDuration(elapsed))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.56))
            }
        } else if let finalDur = store.lastTurnDuration {
            Text("Worked for \(formatCompactDuration(Int(finalDur.rounded())))")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.56))
        } else {
            Text("Progress")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.56))
        }
    }

    private func formatCompactDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let mins = seconds / 60
        let secs = seconds % 60
        if mins >= 5 || secs == 0 { return "\(mins)m" }
        return "\(mins)m \(secs)s"
    }

    @ViewBuilder
    private func stepStatusGlyph(_ status: AgentStepStatus) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.46))
        case .inProgress:
            Image(systemName: "pause.circle")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.28))
        case .skipped:
            Image(systemName: "circle.dashed")
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.28))
        case .failed:
            Image(systemName: "xmark.circle")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(GravPalette.coral)
        }
    }

    private func stepTextColor(_ status: AgentStepStatus) -> Color {
        switch status {
        case .inProgress: return Color.white.opacity(0.96)
        case .done: return Color.white.opacity(0.52)
        case .pending, .skipped: return Color.white.opacity(0.38)
        case .failed: return GravPalette.coral.opacity(0.92)
        }
    }

    // MARK: - Editorial Thinking Sheet

    private func thinkingEditorialSheet(for snapshot: ThinkingSnapshot) -> some View {
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
                    toggleThinking()
                } label: {
                    HStack(spacing: 6) {
                        NotchSemanticDot(
                            color: snapshot.isActive ? GravPalette.thinking : Color.white.opacity(0.32),
                            size: 5,
                            isPulsing: snapshot.isActive && !store.isPaused
                        )

                        if snapshot.isActive && !store.isPaused {
                            NotchThinkingShimmerLabel(
                                startDate: snapshot.startedAt,
                                compact: false,
                                font: .system(size: 11.5, weight: .semibold),
                                reduceMotion: reduceMotion
                            )
                        } else {
                            Text("Thought")
                                .font(.system(size: 11.5, weight: .semibold))
                                .tracking(-0.15)
                                .foregroundStyle(Color.white.opacity(0.70))
                        }

                        if let modelLabel, !modelLabel.isEmpty {
                            Text(modelLabel)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.36))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Spacer(minLength: 6)

                        ActiveElapsedTimerText(
                            startDate: snapshot.startedAt,
                            endDate: snapshot.completedAt,
                            isActive: snapshot.isActive && !store.isPaused,
                            font: .system(size: 10.5, weight: .medium, design: .monospaced),
                            color: snapshot.isActive ? GravPalette.thinking.opacity(0.92) : Color.white.opacity(0.42)
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if availableThoughts.count > 1 {
                    HStack(spacing: 2) {
                        Button {
                            stepThought(by: 1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(selectedThoughtIndex < availableThoughts.count - 1 ? 0.56 : 0.20))
                                .frame(width: 15, height: 18)
                        }
                        .buttonStyle(NotchChromeButtonStyle(cornerRadius: 4))
                        .disabled(selectedThoughtIndex >= availableThoughts.count - 1)
                        .help("Previous thought")

                        Text("\(selectedThoughtIndex + 1)/\(availableThoughts.count)")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.36))

                        Button {
                            stepThought(by: -1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(selectedThoughtIndex > 0 ? 0.56 : 0.20))
                                .frame(width: 15, height: 18)
                        }
                        .buttonStyle(NotchChromeButtonStyle(cornerRadius: 4))
                        .disabled(selectedThoughtIndex <= 0)
                        .help("Newer thought")
                    }
                }

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
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(didCopyThought ? GravPalette.emerald : Color.white.opacity(isHoveringThinkingHeader ? 0.62 : 0.34))
                            .frame(width: 20, height: 18)
                    }
                    .buttonStyle(NotchChromeButtonStyle(cornerRadius: 5))
                    .help("Copy Thought (⌘C)")
                }

                Button {
                    toggleThinking()
                } label: {
                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(NotchChromeButtonStyle(cornerRadius: 5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .onHover { isHoveringThinkingHeader = $0 }

            if isThinkingExpanded {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 5) {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(resolvedText.isEmpty ? "Streaming reasoning tokens…" : resolvedText)
                                    .font(.system(size: 11.5, weight: .regular))
                                    .lineSpacing(3.2)
                                    .foregroundStyle(Color.white.opacity(0.82))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 6)
                                    .padding(.bottom, 5)

                                Color.clear
                                    .frame(height: 1)
                                    .id("thinking-stream-tail")
                            }
                        }
                        .frame(maxHeight: store.recentActivity.isEmpty ? 164 : 74)
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
                                    }
                                    Text(isLoadingFull ? "Loading…" : "Load full thought")
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                                .foregroundStyle(GravPalette.glacialCyan)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                            }
                            .buttonStyle(NotchChromeButtonStyle(cornerRadius: 5))
                            .disabled(isLoadingFull)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 7)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.042))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.11),
                                    Color.white.opacity(0.03),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
        )
    }

    private func stepThought(by delta: Int) {
        let maxIdx = max(0, availableThoughts.count - 1)
        let target = min(max(0, selectedThoughtIndex + delta), maxIdx)
        guard target != selectedThoughtIndex else { return }
        if reduceMotion {
            selectedThoughtIndex = target
        } else {
            withAnimation(GravMotion.subtleFade) {
                selectedThoughtIndex = target
            }
        }
    }

    private func toggleThinking() {
        if reduceMotion {
            isThinkingExpanded.toggle()
        } else {
            withAnimation(GravMotion.contentSlide) {
                isThinkingExpanded.toggle()
            }
        }
    }

    private var thinkingScrollMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.04),
                .init(color: .black, location: 0.90),
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

    // MARK: - Clean Activity Feed (Zero Icon Boxes, Pure Typography & Alignment)

    private var activityFeedSection: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 1.5) {
                if !store.isPaused {
                    switch store.state {
                    case let .working(startedAt):
                        liveWorkingThinkingStatusRow(startedAt: startedAt)
                    case .replying:
                        liveInlineStatusRow(
                            symbol: "text.bubble",
                            symbolColor: store.isTurboMode ? GravPalette.turboEmber : GravPalette.emerald,
                            label: "Replying",
                            startedAt: store.currentPhaseStartedAt
                        )
                    case let .compacting(event) where !store.recentActivity.contains(where: { $0.id == event.id }):
                        liveInlineStatusRow(
                            symbol: "rectangle.compress.vertical",
                            symbolColor: GravPalette.prismViolet,
                            label: "Compacting",
                            startedAt: event.startedAt
                        )
                    case .idle where store.runningTaskCount > 0:
                        liveRunningTasksStatusRow(count: store.runningTaskCount)
                    default:
                        EmptyView()
                    }
                }

                ForEach(store.recentActivity) { item in
                    activityRow(for: item)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                )
                        )
                }
            }
            .padding(.vertical, 1)
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
                activityLeadingGlyph(for: item)

                activityLabel(for: item)

                Spacer(minLength: 8)

                activityTrailingMetric(for: item)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .matchedGeometryEffect(id: "live-activity-hover-pill", in: activityHoverNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            activityContextMenu(for: item)
        }
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
    private func activityLeadingGlyph(for item: TelemetryActivityItem) -> some View {
        switch item {
        case let .fileChange(event):
            LanguageIconView(path: event.path, changeKind: event.kind, size: 14.5)
        case let .fileInspection(event):
            LanguageIconView(path: event.path, changeKind: nil, size: 14.5)
        default:
            let spec = activityGlyphSpec(for: item)
            Image(systemName: spec.symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(spec.color)
                .frame(width: 14.5, alignment: .center)
        }
    }

    private func liveWorkingThinkingStatusRow(startedAt: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(GravPalette.thinking)
                .frame(width: 14.5, alignment: .center)

            NotchWorkingThinkingShimmerLabel(
                startDate: startedAt,
                compact: false,
                font: .system(size: 11.5, weight: .medium),
                reduceMotion: reduceMotion
            )

            Spacer(minLength: 8)

            if store.runningTaskCount > 0 {
                Text("\(store.runningTaskCount) task\(store.runningTaskCount == 1 ? "" : "s") running")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(GravPalette.glacialCyan.opacity(0.84))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5.5)
    }

    private func liveRunningTasksStatusRow(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(GravPalette.glacialCyan)
                .frame(width: 14.5, alignment: .center)

            NotchShimmerText(
                text: count == 1 ? "1 task running" : "\(count) tasks running",
                font: .system(size: 11.5, weight: .medium),
                tracking: -0.15,
                baseOpacity: 0.46,
                peakOpacity: 0.96,
                period: 1.75,
                reduceMotion: reduceMotion
            )
            .monospacedDigit()

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5.5)
    }

    private func liveInlineStatusRow(
        symbol: String,
        symbolColor: Color,
        label: String,
        startedAt: Date
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(symbolColor)
                .frame(width: 14.5, alignment: .center)

            NotchShimmerText(
                text: label,
                font: .system(size: 11.5, weight: .medium),
                tracking: -0.15,
                baseOpacity: 0.44,
                peakOpacity: 0.96,
                period: 1.75,
                reduceMotion: reduceMotion
            )

            Spacer(minLength: 8)

            ActiveElapsedTimerText(
                startDate: startedAt,
                endDate: nil,
                isActive: true,
                font: .system(size: 10.5, weight: .medium, design: .monospaced),
                color: Color.white.opacity(0.36)
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5.5)
    }

    private func activityGlyphSpec(for item: TelemetryActivityItem) -> (symbol: String, color: Color) {
        switch item {
        case .thinking:
            return ("waveform.path.ecg", GravPalette.thinking)
        case .compaction:
            return ("rectangle.compress.vertical", GravPalette.prismViolet)
        case .fileInspection:
            return ("doc.text.magnifyingglass", GravPalette.glacialCyan)
        case let .fileChange(event):
            switch event.kind {
            case .create: return ("plus", GravPalette.emerald)
            case .edit, .overwrite: return ("pencil", GravPalette.fileEdit)
            case .delete: return ("trash", GravPalette.coral)
            }
        case let .command(command):
            switch command.status {
            case .running: return ("terminal", GravPalette.glacialCyan)
            case .succeeded: return ("terminal", Color.white.opacity(0.54))
            case .failed: return ("exclamationmark.triangle", GravPalette.coral)
            }
        case let .toolActivity(event):
            let color: Color = event.kind == .waitingForInput ? GravPalette.fileEdit : GravPalette.glacialCyan
            return (event.kind.symbolName, color)
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
                .foregroundStyle(Color.white.opacity(0.76))
                .lineLimit(1)
                .truncationMode(.tail)

        case let .compaction(event):
            if event.isActive && !store.isPaused {
                NotchShimmerText(
                    text: "Compacting",
                    font: .system(size: 11.5, weight: .medium),
                    tracking: -0.15,
                    baseOpacity: 0.46,
                    peakOpacity: 0.96,
                    period: 1.85,
                    reduceMotion: reduceMotion
                )
            } else {
                Text("Compacted context")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .lineLimit(1)
            }

        case let .fileInspection(event):
            HStack(spacing: 5.5) {
                Text("Analyzed")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .fixedSize(horizontal: true, vertical: false)

                Text(event.basename)
                    .font(.system(size: 11.5, weight: .medium))
                    .tracking(-0.15)
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                Text(NotchTelemetryHelpers.compactParentPath(for: event.path))
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.32))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

        case let .fileChange(event):
            HStack(spacing: 6) {
                Text(event.basename)
                    .font(.system(size: 11.5, weight: .medium))
                    .tracking(-0.15)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                Text(NotchTelemetryHelpers.compactParentPath(for: event.path))
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.34))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

        case let .command(command):
            Text(command.displayTitle)
                .font(.system(size: 11.5, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.90))
                .lineLimit(1)
                .truncationMode(.tail)

        case let .toolActivity(event):
            Text(event.title)
                .font(.system(size: 11.5, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(event.kind == .waitingForInput ? GravPalette.fileEdit : Color.white.opacity(0.86))
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
                font: .system(size: 10.5, weight: .medium, design: .monospaced),
                color: Color.white.opacity(0.40)
            )

        case let .compaction(event):
            if event.isActive && !store.isPaused {
                ActiveElapsedTimerText(
                    startDate: event.startedAt,
                    endDate: event.completedAt,
                    isActive: true,
                    font: .system(size: 10.5, weight: .medium, design: .monospaced),
                    color: GravPalette.prismViolet.opacity(0.84)
                )
            } else {
                Text("checkpoint")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.32))
            }

        case let .fileInspection(event):
            if let range = event.lineRangeLabel {
                Text(range)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.46))
            }

        case let .fileChange(event):
            NotchProportionalDiffMicroBar(
                added: event.addedLines,
                removed: event.removedLines,
                isDeleted: event.kind == .delete,
                showBar: false
            )

        case let .command(command):
            HStack(spacing: 6) {
                if let code = command.exitCode, command.status != .running, code != 0 {
                    Text("exit \(code)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(GravPalette.coral)
                }
                ActiveElapsedTimerText(
                    startDate: command.startedAt,
                    endDate: command.completedAt,
                    isActive: command.status == .running && !store.isPaused,
                    font: .system(size: 10.5, weight: .medium, design: .monospaced),
                    color: command.status == .running ? GravPalette.glacialCyan : Color.white.opacity(0.40)
                )
            }

        case let .toolActivity(event):
            Text(event.kind.shortLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.36))
        }
    }

    private func handleActivityTap(_ item: TelemetryActivityItem) {
        switch item {
        case let .thinking(snapshot):
            if let idx = availableThoughts.firstIndex(where: { $0.stepIndex == snapshot.stepIndex }) {
                selectedThoughtIndex = idx
            }
            if !isThinkingExpanded {
                toggleThinking()
            }
        case .compaction:
            break
        case let .fileInspection(event):
            store.openInAntigravity(path: event.path, line: event.startLine)
        case let .fileChange(event):
            onInspectFile(event)
        case let .command(command):
            onInspectCommand(command)
        case .toolActivity:
            store.activateAntigravityApp()
        }
    }

    @ViewBuilder
    private func activityContextMenu(for item: TelemetryActivityItem) -> some View {
        switch item {
        case let .fileInspection(event):
            Button(event.startLine != nil ? "Open in Antigravity at Line \(event.startLine!)" : "Open in Antigravity") {
                store.openInAntigravity(path: event.path, line: event.startLine)
            }
            Button("Reveal in Finder") {
                store.revealInFinder(path: event.path)
            }
            Button("Copy Path") {
                NotchTelemetryHelpers.copyToPasteboard(event.path)
            }

        case let .fileChange(event):
            Button("Open in Antigravity") {
                store.openInAntigravity(path: event.path)
            }
            Button("Reveal in Finder") {
                store.revealInFinder(path: event.path)
            }
            Divider()
            Button("Copy Path") {
                NotchTelemetryHelpers.copyToPasteboard(event.path)
            }
            Button("Copy Unified Diff") {
                NotchTelemetryHelpers.copyToPasteboard(NotchTelemetryHelpers.formatUnifiedDiff(for: event))
            }

        case let .command(command):
            Button("Copy Command") {
                NotchTelemetryHelpers.copyToPasteboard(command.commandLine)
            }
            if !command.logOutput.isEmpty {
                Button("Copy Output Log") {
                    NotchTelemetryHelpers.copyToPasteboard(command.logOutput)
                }
            }

        case let .thinking(snapshot):
            Button("Copy Reasoning") {
                NotchTelemetryHelpers.copyToPasteboard(snapshot.text)
            }

        case let .toolActivity(event):
            Button("Focus Antigravity") {
                store.activateAntigravityApp()
            }
            Button("Copy Details") {
                let text = [event.title, event.detail].compactMap { $0 }.joined(separator: "\n")
                NotchTelemetryHelpers.copyToPasteboard(text)
            }

        case .compaction:
            EmptyView()
        }
    }

    // MARK: - Quiet Empty State

    private var quietEmptyState: some View {
        VStack(spacing: 8) {
            GravAppIconTile(size: 28)
                .opacity(0.88)

            Text("Telemetry Standby")
                .font(.system(size: 12, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.76))

            Text(
                store.isPaused
                    ? "Monitoring is paused. Resume from the menu bar to stream live activity."
                    : "Waiting for Antigravity reasoning, file changes, or shell output."
            )
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.38))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
