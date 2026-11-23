import AppKit
import SwiftUI

/// Feature #6: Unified Background Tasks, Daemons, `/schedule` Timers/Crons & MCP Tool Monitor
/// nested cleanly inside the Notch HUD Terminal tab.
public struct TasksAndMCPMonitorView: View {
    public var store: AntigravityTelemetryStore

    public init(store: AntigravityTelemetryStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                tasksSection
                mcpSection
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            store.refreshRuntimeInspection()
        }
    }

    // MARK: - Background Tasks, Daemons & Schedules

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("BACKGROUND TASKS & SCHEDULES")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Color.white.opacity(0.42))
                Spacer()
                let running = store.scheduledTasks.filter { $0.status == .running }.count
                if running > 0 {
                    Text("\(running) active")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GravPalette.glacialCyan)
                }
            }
            .padding(.horizontal, 4)

            if store.scheduledTasks.isEmpty {
                quietEmptyRow("No background tasks, daemons, or /schedule timers in this session.")
            } else {
                VStack(spacing: 3) {
                    ForEach(store.scheduledTasks.prefix(8)) { task in
                        taskRow(task)
                    }
                }
            }
        }
    }

    private func taskRow(_ task: ScheduledTaskRecord) -> some View {
        let tint = NotchTelemetryHelpers.color(for: task.status)
        return HStack(spacing: 8) {
            NotchSemanticDot(
                color: tint,
                size: 5,
                isPulsing: task.status == .running && !store.isPaused
            )

            Image(systemName: task.kind.symbolName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.56))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 5) {
                    Text(task.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)

                    Text(task.kind.rawValue.uppercased())
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                }

                Text(task.detail)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if let logURL = task.logURL {
                Button {
                    NSWorkspace.shared.open(logURL)
                } label: {
                    Text("Log")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6.5)
        .background(
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .fill(Color.white.opacity(0.036))
                .overlay(
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                )
        )
    }

    // MARK: - MCP Servers & Tool Invocations

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("MCP SERVERS & CALLS")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Color.white.opacity(0.42))
                Spacer()
                if !store.mcpServers.isEmpty {
                    Text("\(store.mcpServers.count) server\(store.mcpServers.count == 1 ? "" : "s")")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.38))
                }
            }
            .padding(.horizontal, 4)

            if !store.mcpServers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.mcpServers) { server in
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([server.directoryURL])
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(GravPalette.emerald.opacity(0.85))
                                        .frame(width: 5, height: 5)
                                    Text(server.name)
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.88))
                                    Text("\(server.toolCount) tools")
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundStyle(Color.white.opacity(0.44))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.white.opacity(0.055))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Reveal ~/.gemini/antigravity/mcp/\(server.name)")
                        }
                    }
                }
            }

            let mcpCalls = store.mcpToolActivities
            if mcpCalls.isEmpty {
                quietEmptyRow(
                    store.mcpServers.isEmpty
                        ? "No MCP servers installed in ~/.gemini/antigravity/mcp/."
                        : "No MCP tool calls recorded in this session yet."
                )
            } else {
                VStack(spacing: 3) {
                    ForEach(mcpCalls.prefix(10)) { call in
                        mcpCallRow(call)
                    }
                }
            }
        }
    }

    private func mcpCallRow(_ call: AgentToolActivityEvent) -> some View {
        let tint = NotchTelemetryHelpers.color(for: call.status)
        return HStack(spacing: 8) {
            NotchSemanticDot(
                color: tint,
                size: 5,
                isPulsing: call.status == .running && !store.isPaused
            )

            VStack(alignment: .leading, spacing: 1.5) {
                Text(call.title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)

                if let detail = call.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.44))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            if let completed = call.completedAt {
                let ms = max(1, Int(completed.timeIntervalSince(call.startedAt) * 1000))
                Text(ms >= 1000 ? String(format: "%.1fs", Double(ms) / 1000.0) : "\(ms)ms")
                    .font(.system(size: 9.5, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.36))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .fill(Color.white.opacity(0.032))
        )
    }

    private func quietEmptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Color.white.opacity(0.36))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .fill(Color.white.opacity(0.025))
            )
    }
}
