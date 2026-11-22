import SwiftUI

/// Dedicated Expanded Notch HUD tab for monitoring Antigravity Swarms (`/swarm` / `/teamwork`)
/// and standalone Subagents (`research`, `browser`, `self`, etc.) directly from
/// `.system_generated/swarm/` and `.system_generated/subagents/`.
///
/// Clicking any worker or subagent opens an inline live inspector **right inside the Swarm tab**
/// without leaving the tab or disrupting the coordinator's active session.
public struct SwarmTelemetryTabView: View {
    public var store: AntigravityTelemetryStore
    public var onPinSessionAsMain: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var rowHoverNamespace

    private enum SwarmSubMode: String, CaseIterable, Identifiable {
        case roster = "Roster"
        case board = "Board"

        var id: String { rawValue }
    }

    private struct InspectedAgentTarget: Equatable, Identifiable {
        let conversationId: String
        let title: String
        let subtitle: String?
        let model: String?
        let statusLabel: String
        let isActive: Bool
        let isWaiting: Bool

        var id: String { conversationId }
    }

    @State private var subMode: SwarmSubMode = .roster
    @State private var inspectedAgent: InspectedAgentTarget?
    @State private var hoveredRowID: String?
    @State private var expandedMessageSeq: Int?
    @State private var copiedMessageSeq: Int?
    @State private var copyFeedbackTask: Task<Void, Never>?

    public init(
        store: AntigravityTelemetryStore,
        onPinSessionAsMain: @escaping (String) -> Void = { _ in }
    ) {
        self.store = store
        self.onPinSessionAsMain = onPinSessionAsMain
    }

    private var swarm: SwarmSnapshot? { store.swarmSnapshot }
    private var standaloneSubagents: [SubagentRecord] { store.standaloneSubagents }

    public var body: some View {
        Group {
            if let target = inspectedAgent {
                SwarmAgentInlineInspectorView(
                    target: target,
                    brainDirectoryURL: store.connectionStatus.brainDirectoryURL,
                    boardMessages: swarm?.boardMessages.filter { $0.agent == target.title } ?? [],
                    reduceMotion: reduceMotion,
                    onBack: {
                        GravOnboardingWelcomeAudio.shared.playButtonTap()
                        closeInspector()
                    },
                    onOpenInAntigravity: { path in
                        store.openInAntigravity(path: path)
                    },
                    onPinAsMain: {
                        GravOnboardingWelcomeAudio.shared.playButtonTap()
                        onPinSessionAsMain(target.conversationId)
                    }
                )
                .id("inspector-\(target.conversationId)")
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        )
                )
            } else if swarm == nil && standaloneSubagents.isEmpty {
                emptyState
            } else {
                VStack(spacing: 6) {
                    headerStrip

                    if subMode == .board, let swarm, !swarm.boardMessages.isEmpty {
                        boardFeed(messages: swarm.boardMessages)
                    } else {
                        rosterFeed
                    }
                }
                .id("swarm-root")
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : GravMotion.contentSlide, value: inspectedAgent?.id)
        .onChange(of: store.activeSession?.id) { _, _ in
            inspectedAgent = nil
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
    }

    private func openInspector(_ target: InspectedAgentTarget) {
        if reduceMotion {
            inspectedAgent = target
        } else {
            withAnimation(GravMotion.contentSlide) {
                inspectedAgent = target
            }
        }
    }

    private func closeInspector() {
        if reduceMotion {
            inspectedAgent = nil
        } else {
            withAnimation(GravMotion.contentSlide) {
                inspectedAgent = nil
            }
        }
    }

    // MARK: - Compact Header Strip (Goal Title · Live Counts · Roster/Board Switch)

    private var headerStrip: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(swarm?.displayTitle ?? "Subagents")
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(-0.15)
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(headerCountsSummary)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.42))
                        .fixedSize(horizontal: true, vertical: false)
                }

                if let goalLine = swarm?.goalLine, !goalLine.isEmpty {
                    Text(goalLine)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            if let swarm, !swarm.boardMessages.isEmpty {
                HStack(spacing: 2) {
                    ForEach(SwarmSubMode.allCases) { mode in
                        let isSelected = subMode == mode
                        Button {
                            GravOnboardingWelcomeAudio.shared.playButtonTap()
                            if reduceMotion {
                                subMode = mode
                            } else {
                                withAnimation(GravMotion.subtleFade) {
                                    subMode = mode
                                }
                            }
                        } label: {
                            HStack(spacing: 3.5) {
                                Text(mode.rawValue)
                                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                                if mode == .board {
                                    Text("\(swarm.boardMessages.count)")
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundStyle(isSelected ? Color.white.opacity(0.62) : Color.white.opacity(0.30))
                                }
                            }
                            .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.46))
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.11) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 1)
    }

    private var headerCountsSummary: String {
        var parts: [String] = []
        if let swarm {
            let working = swarm.runningWorkers.count
            let waiting = swarm.waitingWorkers.count
            let done = swarm.finishedWorkers.count
            if working > 0 { parts.append("\(working) working") }
            if waiting > 0 { parts.append("\(waiting) waiting") }
            if done > 0 { parts.append("\(done) done") }
        }
        if !standaloneSubagents.isEmpty {
            let active = standaloneSubagents.filter(\.isActive).count
            if active > 0 {
                parts.append("\(active) subagent\(active == 1 ? "" : "s")")
            } else {
                parts.append("\(standaloneSubagents.count) subagent\(standaloneSubagents.count == 1 ? "" : "s")")
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Roster Feed (Swarm Workers + Standalone Subagents)

    private var rosterFeed: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                if let swarm {
                    ForEach(swarm.members) { member in
                        swarmMemberRow(member)
                    }
                }

                if !standaloneSubagents.isEmpty {
                    if swarm != nil {
                        HStack(spacing: 6) {
                            Text("SUBAGENTS")
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Color.white.opacity(0.30))
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 0.5)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                    }

                    ForEach(standaloneSubagents) { subagent in
                        subagentRow(subagent)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.93),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func swarmMemberRow(_ member: SwarmMember) -> some View {
        let rowID = "member-\(member.id)"
        let isHovered = hoveredRowID == rowID
        let dotColor = color(for: member.phase, isCoordinator: member.isCoordinator)

        return Button {
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            openInspector(
                InspectedAgentTarget(
                    conversationId: member.conversationId,
                    title: member.name,
                    subtitle: member.primarySubtitle,
                    model: member.model,
                    statusLabel: member.phase.displayLabel,
                    isActive: member.phase == .running,
                    isWaiting: member.phase == .waiting
                )
            )
        } label: {
            HStack(alignment: .center, spacing: 8) {
                NotchSemanticDot(
                    color: dotColor,
                    size: 5.5,
                    isPulsing: member.phase == .running && !store.isPaused
                )
                .frame(width: 12, alignment: .center)

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text(member.name)
                            .font(.system(size: 11.5, weight: .medium))
                            .tracking(-0.15)
                            .foregroundStyle(
                                member.phase == .killed
                                    ? Color.white.opacity(0.66)
                                    : Color.white.opacity(0.92)
                            )
                            .lineLimit(1)

                        if let model = member.model, !model.isEmpty {
                            Text(model)
                                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.32))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    if let subtitle = member.primarySubtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    if member.phase == .running && !store.isPaused {
                        NotchShimmerText(
                            text: member.phase.displayLabel,
                            font: .system(size: 10, weight: .medium, design: .monospaced),
                            tracking: 0,
                            baseOpacity: 0.50,
                            peakOpacity: 0.96,
                            period: 1.75,
                            reduceMotion: reduceMotion
                        )
                    } else {
                        Text(member.phase.displayLabel)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(
                                member.phase == .waiting
                                    ? GravPalette.fileEdit.opacity(0.84)
                                    : Color.white.opacity(0.34)
                            )
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(isHovered ? 0.62 : 0.22))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .matchedGeometryEffect(id: "swarm-row-hover", in: rowHoverNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            updateHover(rowID: rowID, hovering: hovering)
        }
        .help("Inspect \(member.name) inside Swarm tab")
    }

    private func subagentRow(_ subagent: SubagentRecord) -> some View {
        let rowID = "subagent-\(subagent.id)"
        let isHovered = hoveredRowID == rowID

        return Button {
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            openInspector(
                InspectedAgentTarget(
                    conversationId: subagent.conversationId,
                    title: subagent.role,
                    subtitle: subagent.liveActivityHint,
                    model: subagent.typeName,
                    statusLabel: subagent.state.displayLabel,
                    isActive: subagent.isActive,
                    isWaiting: subagent.state == .waiting
                )
            )
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: symbolForSubagentType(subagent.typeName))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(subagent.isActive ? GravPalette.glacialCyan : Color.white.opacity(0.44))
                    .frame(width: 14, alignment: .center)

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text(subagent.role)
                            .font(.system(size: 11.5, weight: .medium))
                            .tracking(-0.15)
                            .foregroundStyle(subagent.isActive ? Color.white.opacity(0.92) : Color.white.opacity(0.70))
                            .lineLimit(1)

                        Text(subagent.typeName)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.32))
                    }

                    if let hint = subagent.liveActivityHint, !hint.isEmpty {
                        Text(hint)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    if subagent.isActive && !store.isPaused {
                        NotchShimmerText(
                            text: subagent.state.displayLabel,
                            font: .system(size: 10, weight: .medium, design: .monospaced),
                            tracking: 0,
                            baseOpacity: 0.50,
                            peakOpacity: 0.96,
                            period: 1.75,
                            reduceMotion: reduceMotion
                        )
                    } else {
                        Text(subagent.state.displayLabel)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(subagent.state == .error ? GravPalette.coral : Color.white.opacity(0.34))
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(isHovered ? 0.62 : 0.22))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .matchedGeometryEffect(id: "swarm-row-hover", in: rowHoverNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            updateHover(rowID: rowID, hovering: hovering)
        }
        .help("Inspect \(subagent.role) inside Swarm tab")
    }

    // MARK: - Swarm Board Feed (`board.jsonl`)

    private func boardFeed(messages: [SwarmBoardMessage]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 3) {
                ForEach(messages) { message in
                    boardMessageRow(message)
                }
            }
            .padding(.vertical, 1)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.93),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func boardMessageRow(_ message: SwarmBoardMessage) -> some View {
        let rowID = "board-\(message.seq)"
        let isExpanded = expandedMessageSeq == message.seq
        let isHovered = hoveredRowID == rowID

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("#\(message.seq)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.32))

                Text(message.agent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        message.agent == "coordinator"
                            ? GravPalette.glacialCyan
                            : Color.white.opacity(0.88)
                    )

                Spacer()

                if let time = message.timestampLabel {
                    Text(shortTime(from: time))
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.30))
                }

                if isHovered || copiedMessageSeq == message.seq {
                    Button {
                        copyBoardMessage(message)
                    } label: {
                        Image(systemName: copiedMessageSeq == message.seq ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(copiedMessageSeq == message.seq ? GravPalette.emerald : Color.white.opacity(0.46))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(NotchChromeButtonStyle(cornerRadius: 4))
                }
            }

            Text(isExpanded ? message.text : message.previewLine)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(isExpanded ? nil : 2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isExpanded ? Color.white.opacity(0.055) : (isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.02)))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            if reduceMotion {
                expandedMessageSeq = isExpanded ? nil : message.seq
            } else {
                withAnimation(GravMotionSpec.settle.animation) {
                    expandedMessageSeq = isExpanded ? nil : message.seq
                }
            }
        }
        .onHover { hovering in
            updateHover(rowID: rowID, hovering: hovering)
        }
    }

    // MARK: - Helpers & Empty State

    private func color(for phase: SwarmMemberPhase, isCoordinator: Bool) -> Color {
        if isCoordinator && phase == .running {
            return GravPalette.prismViolet
        }
        switch phase {
        case .running: return GravPalette.glacialCyan
        case .waiting: return GravPalette.fileEdit
        case .stopped, .killed: return Color.white.opacity(0.28)
        }
    }

    private func symbolForSubagentType(_ typeName: String) -> String {
        switch typeName.lowercased() {
        case "browser": return "globe"
        case "research": return "magnifyingglass"
        case "image-generator": return "photo"
        default: return "cpu"
        }
    }

    private func shortTime(from raw: String) -> String {
        if let last = raw.split(separator: " ").last {
            return String(last)
        }
        return raw
    }

    private func updateHover(rowID: String, hovering: Bool) {
        if reduceMotion {
            hoveredRowID = hovering ? rowID : (hoveredRowID == rowID ? nil : hoveredRowID)
        } else {
            withAnimation(GravMotion.rowHover) {
                if hovering {
                    hoveredRowID = rowID
                } else if hoveredRowID == rowID {
                    hoveredRowID = nil
                }
            }
        }
    }

    private func copyBoardMessage(_ message: SwarmBoardMessage) {
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        NotchTelemetryHelpers.copyToPasteboard("#\(message.seq) \(message.agent): \(message.text)")
        copiedMessageSeq = message.seq
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            copiedMessageSeq = nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.white.opacity(0.30))

            Text("No Active Swarm or Subagents")
                .font(.system(size: 12, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.76))

            Text("Start a /swarm or launch a subagent in Antigravity to monitor live workers and board messages here.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.38))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inline Worker / Subagent Transcript Inspector (Stays inside Swarm Tab!)

    private struct SwarmAgentInlineInspectorView: View {
        let target: InspectedAgentTarget
        let brainDirectoryURL: URL
        let boardMessages: [SwarmBoardMessage]
        let reduceMotion: Bool
        let onBack: () -> Void
        let onOpenInAntigravity: (String) -> Void
        let onPinAsMain: () -> Void

        @State private var activities: [TelemetryActivityItem] = []
        @State private var tokenMetrics = TokenMetrics()
        @State private var latestThinking: ThinkingSnapshot?
        @State private var latestReply: AssistantResponseSnapshot?
        @State private var fileCount: Int = 0
        @State private var commandCount: Int = 0
        @State private var isLoading: Bool = true
        @State private var liveTailer: TranscriptTailer?
        @State private var workerClassifier = EventClassifier()
        @State private var trackedFileIDs: Set<String> = []
        @State private var trackedCommandIDs: Set<String> = []

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Top Inline Navigation Bar (`< Swarm` · Name · Status · Counts)
                HStack(spacing: 7) {
                    Button(action: onBack) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("Swarm")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(Color.white.opacity(0.74))
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                    }
                    .buttonStyle(NotchChromeButtonStyle(cornerRadius: 5.5))

                    NotchSemanticDot(
                        color: target.isActive
                            ? GravPalette.glacialCyan
                            : (target.isWaiting ? GravPalette.fileEdit : Color.white.opacity(0.30)),
                        size: 5,
                        isPulsing: target.isActive
                    )

                    Text(target.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(-0.15)
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)

                    if let model = target.model, !model.isEmpty {
                        Text(model)
                            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.36))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 6)

                    if tokenMetrics.totalTokens > 0 {
                        Text(TokenMetrics.formatCompact(tokenMetrics.totalTokens))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.42))
                    }

                    if fileCount > 0 || commandCount > 0 {
                        Text("\(fileCount)F · \(commandCount)C")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.36))
                    }

                    Button(action: onPinAsMain) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.46))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(NotchChromeButtonStyle(cornerRadius: 5))
                    .help("Pin \(target.title) as the main HUD session")
                }
                .padding(.horizontal, 6)

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.horizontal, 6)

                if isLoading {
                    HStack(spacing: 6) {
                        NotchShimmerText(
                            text: "Loading \(target.title) telemetry…",
                            font: .system(size: 11, weight: .medium),
                            reduceMotion: reduceMotion
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if activities.isEmpty && boardMessages.isEmpty && latestReply == nil {
                    VStack(spacing: 5) {
                        Text("No transcript steps yet for \(target.title)")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.66))
                        if let subtitle = target.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 10.5, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.38))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 340)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            if let latestBoard = boardMessages.first {
                                HStack(alignment: .top, spacing: 6) {
                                    Text("#\(latestBoard.seq)")
                                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(GravPalette.prismViolet)
                                    Text(latestBoard.previewLine)
                                        .font(.system(size: 10.5, weight: .regular))
                                        .foregroundStyle(Color.white.opacity(0.76))
                                        .lineLimit(2)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.white.opacity(0.035))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                                        )
                                )
                                .padding(.horizontal, 6)
                                .padding(.bottom, 2)
                            }

                            ForEach(activities.prefix(60)) { item in
                                inlineActivityRow(item)
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .task(id: target.conversationId) {
                await startStreamingWorkerTranscript()
            }
            .onDisappear {
                let tailer = liveTailer
                liveTailer = nil
                Task {
                    await tailer?.stopWatching()
                }
            }
        }

        @ViewBuilder
        private func inlineActivityRow(_ item: TelemetryActivityItem) -> some View {
            switch item {
            case let .fileInspection(event):
                Button {
                    onOpenInAntigravity(event.path)
                } label: {
                    HStack(spacing: 7) {
                        LanguageIconView(path: event.path, changeKind: nil, size: 13.5)
                        Text("Analyzed")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.44))
                        Text(event.basename)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.86))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        if let range = event.lineRangeLabel {
                            Text(range)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(Color.white.opacity(0.42))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                }
                .buttonStyle(.plain)

            case let .fileChange(event):
                Button {
                    onOpenInAntigravity(event.path)
                } label: {
                    HStack(spacing: 7) {
                        LanguageIconView(path: event.path, changeKind: event.kind, size: 13.5)
                        Text(event.basename)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.90))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(NotchTelemetryHelpers.compactParentPath(for: event.path))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.32))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        NotchProportionalDiffMicroBar(
                            added: event.addedLines,
                            removed: event.removedLines,
                            isDeleted: event.kind == .delete,
                            showBar: false
                        )
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                }
                .buttonStyle(.plain)

            case let .command(cmd):
                HStack(spacing: 7) {
                    Image(systemName: cmd.status == .failed ? "exclamationmark.triangle" : "terminal")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            cmd.status == .running
                                ? GravPalette.glacialCyan
                                : (cmd.status == .failed ? GravPalette.coral : Color.white.opacity(0.48))
                        )
                        .frame(width: 13.5)
                    Text(cmd.displayTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    if let code = cmd.exitCode, code != 0 {
                        Text("exit \(code)")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(GravPalette.coral)
                    }
                    ActiveElapsedTimerText(
                        startDate: cmd.startedAt,
                        endDate: cmd.completedAt,
                        isActive: cmd.status == .running,
                        font: .system(size: 10, weight: .medium, design: .monospaced),
                        color: cmd.status == .running ? GravPalette.glacialCyan : Color.white.opacity(0.38)
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)

            case let .thinking(snapshot):
                let line = snapshot.text
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                HStack(spacing: 7) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GravPalette.thinking)
                        .frame(width: 13.5)
                    Text(line.isEmpty ? "Reasoning step #\(snapshot.stepIndex)" : line)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)

            case let .compaction(event):
                HStack(spacing: 7) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GravPalette.prismViolet)
                        .frame(width: 13.5)
                    Text(event.isActive ? "Compacting" : "Compacted context")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.56))
                    Spacer(minLength: 6)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
            }
        }

        @MainActor
        private func startStreamingWorkerTranscript() async {
            isLoading = true
            workerClassifier = EventClassifier()
            activities = []
            trackedFileIDs = []
            trackedCommandIDs = []
            fileCount = 0
            commandCount = 0
            tokenMetrics = TokenMetrics()
            latestThinking = nil
            latestReply = nil

            let convDir = brainDirectoryURL.appendingPathComponent(target.conversationId, isDirectory: true)
            let session = ConversationSession(id: target.conversationId, directoryURL: convDir)
            let tailer = TranscriptTailer(transcriptURL: session.transcriptURL, initialOffset: 0)
            liveTailer = tailer

            let initial = await tailer.readNewSteps()
            applyWorkerSteps(initial, session: session)
            isLoading = false

            if target.isActive || target.isWaiting {
                await tailer.startWatching { newSteps in
                    Task { @MainActor in
                        applyWorkerSteps(newSteps, session: session)
                    }
                }
            }
        }

        @MainActor
        private func applyWorkerSteps(_ steps: [TranscriptStep], session: ConversationSession) {
            var nextActivities = activities
            for step in steps {
                let out = workerClassifier.process(step: step, session: session)
                tokenMetrics = out.tokenMetrics
                if let t = out.thinkingSnapshot {
                    latestThinking = t
                    upsert(.thinking(t), into: &nextActivities)
                }
                if let c = out.compactionEvent {
                    upsert(.compaction(c), into: &nextActivities)
                }
                if let r = out.responseSnapshot {
                    latestReply = r
                }
                for i in out.fileInspections {
                    upsert(.fileInspection(i), into: &nextActivities)
                }
                for f in out.fileChanges {
                    trackedFileIDs.insert(f.id)
                    upsert(.fileChange(f), into: &nextActivities)
                }
                for cmd in out.startedCommands {
                    trackedCommandIDs.insert(cmd.id)
                    upsert(.command(cmd), into: &nextActivities)
                }
                for cmd in out.updatedCommands {
                    trackedCommandIDs.insert(cmd.id)
                    upsert(.command(cmd), into: &nextActivities)
                }
            }
            activities = nextActivities
            fileCount = trackedFileIDs.count
            commandCount = trackedCommandIDs.count
        }

        private func upsert(_ item: TelemetryActivityItem, into list: inout [TelemetryActivityItem]) {
            if let idx = list.firstIndex(where: { $0.id == item.id }) {
                list[idx] = item
            } else {
                list.insert(item, at: 0)
                if list.count > 80 {
                    list.removeLast(list.count - 80)
                }
            }
        }
    }
}
