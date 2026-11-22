import SwiftUI

/// Dedicated Expanded Notch HUD tab for monitoring Antigravity Swarms (`/swarm` / `/teamwork`)
/// and standalone Subagents (`research`, `browser`, `self`, etc.) directly from
/// `.system_generated/swarm/` and `.system_generated/subagents/`.
public struct SwarmTelemetryTabView: View {
    public var store: AntigravityTelemetryStore
    public var onSelectWorkerSession: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var rowHoverNamespace

    private enum SwarmSubMode: String, CaseIterable, Identifiable {
        case roster = "Roster"
        case board = "Board"

        var id: String { rawValue }
    }

    @State private var subMode: SwarmSubMode = .roster
    @State private var hoveredRowID: String?
    @State private var expandedMessageSeq: Int?
    @State private var copiedMessageSeq: Int?
    @State private var copyFeedbackTask: Task<Void, Never>?

    public init(
        store: AntigravityTelemetryStore,
        onSelectWorkerSession: @escaping (String) -> Void = { _ in }
    ) {
        self.store = store
        self.onSelectWorkerSession = onSelectWorkerSession
    }

    private var swarm: SwarmSnapshot? { store.swarmSnapshot }
    private var standaloneSubagents: [SubagentRecord] { store.standaloneSubagents }

    public var body: some View {
        Group {
            if swarm == nil && standaloneSubagents.isEmpty {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear {
            copyFeedbackTask?.cancel()
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
            onSelectWorkerSession(member.conversationId)
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

                HStack(spacing: 6) {
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

                    if isHovered && member.conversationId != store.activeSession?.id {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.56))
                    }
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
        .help("Inspect \(member.name)'s session transcript")
    }

    private func subagentRow(_ subagent: SubagentRecord) -> some View {
        let rowID = "subagent-\(subagent.id)"
        let isHovered = hoveredRowID == rowID

        return Button {
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            onSelectWorkerSession(subagent.conversationId)
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
        .help("Inspect \(subagent.role) transcript")
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
}
