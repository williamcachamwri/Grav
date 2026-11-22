import Foundation

// MARK: - Swarm Runtime Telemetry Models (`.system_generated/swarm/`)

public enum SwarmMemberPhase: String, Sendable, Equatable {
    case running
    case waiting
    case stopped
    case killed

    public var isActive: Bool {
        self == .running
    }

    public var isAlive: Bool {
        self == .running || self == .waiting
    }

    public var displayLabel: String {
        switch self {
        case .running: return "working"
        case .waiting: return "waiting"
        case .stopped: return "stopped"
        case .killed: return "done"
        }
    }

    public static func parse(phase: String?, desiredState: String?, wakeMode: String?, killed: Bool?) -> SwarmMemberPhase {
        if killed == true {
            return .killed
        }
        let raw = (phase ?? desiredState ?? "").uppercased()
        if raw.contains("KILL") {
            return .killed
        }
        if raw.contains("WAIT") || raw.contains("PARK") || raw.contains("IDLE") {
            return .waiting
        }
        if raw.contains("STOP") {
            return .stopped
        }
        if raw.contains("RUN") || raw.contains("WORK") {
            if let wake = wakeMode?.lowercased(), wake == "waiting" || wake == "parked" {
                return .waiting
            }
            return .running
        }
        return .stopped
    }
}

public struct SwarmMember: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let conversationId: String
    public let role: String
    public let phase: SwarmMemberPhase
    public let model: String?
    public let workspaceMode: String?
    public let taskSummary: String?
    public let lastBoardMessage: String?
    public let liveActivityHint: String?

    public init(
        name: String,
        conversationId: String,
        role: String,
        phase: SwarmMemberPhase,
        model: String? = nil,
        workspaceMode: String? = nil,
        taskSummary: String? = nil,
        lastBoardMessage: String? = nil,
        liveActivityHint: String? = nil
    ) {
        self.name = name
        self.conversationId = conversationId
        self.role = role
        self.phase = phase
        self.model = model
        self.workspaceMode = workspaceMode
        self.taskSummary = taskSummary
        self.lastBoardMessage = lastBoardMessage
        self.liveActivityHint = liveActivityHint
    }

    public var isCoordinator: Bool {
        role.lowercased() == "coordinator" || name.lowercased() == "coordinator"
    }

    /// Best single-line summary of what this worker is currently doing or owns.
    public var primarySubtitle: String? {
        if phase == .running, let live = liveActivityHint, !live.isEmpty {
            return live
        }
        if let task = taskSummary, !task.isEmpty {
            return task
        }
        if let board = lastBoardMessage, !board.isEmpty {
            return board
        }
        return nil
    }
}

public struct SwarmBoardMessage: Sendable, Equatable, Identifiable {
    public var id: Int { seq }
    public let seq: Int
    public let agent: String
    public let text: String
    public let timestampLabel: String?

    public init(seq: Int, agent: String, text: String, timestampLabel: String? = nil) {
        self.seq = seq
        self.agent = agent
        self.text = text
        self.timestampLabel = timestampLabel
    }

    public var previewLine: String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct SwarmPlanThread: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let goal: String
    public let tasks: [String]

    public init(id: String, title: String, goal: String, tasks: [String]) {
        self.id = id
        self.title = title
        self.goal = goal
        self.tasks = tasks
    }
}

public struct SwarmSnapshot: Sendable, Equatable {
    public let swarmId: String
    public let title: String?
    public let goalTitle: String?
    public let goalLine: String?
    public let members: [SwarmMember]
    public let threads: [SwarmPlanThread]
    public let boardMessages: [SwarmBoardMessage]
    public let createdAt: Date?

    public init(
        swarmId: String,
        title: String? = nil,
        goalTitle: String? = nil,
        goalLine: String? = nil,
        members: [SwarmMember] = [],
        threads: [SwarmPlanThread] = [],
        boardMessages: [SwarmBoardMessage] = [],
        createdAt: Date? = nil
    ) {
        self.swarmId = swarmId
        self.title = title
        self.goalTitle = goalTitle
        self.goalLine = goalLine
        self.members = members
        self.threads = threads
        self.boardMessages = boardMessages
        self.createdAt = createdAt
    }

    public var workers: [SwarmMember] {
        members.filter { !$0.isCoordinator }
    }

    public var runningWorkers: [SwarmMember] {
        workers.filter { $0.phase == .running }
    }

    public var waitingWorkers: [SwarmMember] {
        workers.filter { $0.phase == .waiting }
    }

    public var finishedWorkers: [SwarmMember] {
        workers.filter { $0.phase == .killed || $0.phase == .stopped }
    }

    /// True whenever at least one swarm worker is actively running or parked/waiting on the board.
    public var hasLiveWorkers: Bool {
        !runningWorkers.isEmpty || !waitingWorkers.isEmpty
    }

    public var displayTitle: String {
        if let g = goalTitle, !g.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return g
        }
        if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        return "Swarm"
    }

    /// Comprehensive single-line summary for the Collapsed Notch pill when a swarm is active.
    public var collapsedSummaryText: String {
        let running = runningWorkers
        let waiting = waitingWorkers
        let activeNames = running.map(\.name)

        if !running.isEmpty {
            let namesPart = activeNames.prefix(3).joined(separator: ", ")
            let suffix = activeNames.count > 3 ? " +\(activeNames.count - 3)" : ""
            if waiting.isEmpty {
                return "Swarm · \(namesPart)\(suffix)"
            }
            return "Swarm · \(running.count) working, \(waiting.count) waiting · \(namesPart)\(suffix)"
        }
        if !waiting.isEmpty {
            let namesPart = waiting.map(\.name).prefix(2).joined(separator: ", ")
            return "Swarm · \(waiting.count) waiting · \(namesPart)"
        }
        return "Swarm · \(workers.count) workers"
    }

    /// Compact `running/total` tabular ratio (e.g. `2/4`) for the right edge of the Collapsed Notch.
    public var collapsedRatioBadge: String {
        let total = max(workers.count, 1)
        if !runningWorkers.isEmpty {
            return "\(runningWorkers.count)/\(total)"
        }
        if !waitingWorkers.isEmpty {
            return "\(waitingWorkers.count)/\(total)"
        }
        return "\(workers.count)"
    }
}

// MARK: - Subagent Telemetry Models (`.system_generated/subagents/`)

public enum SubagentState: String, Sendable, Equatable {
    case running
    case waiting
    case idle
    case completed
    case killed
    case error

    public var isActive: Bool {
        self == .running
    }

    public var displayLabel: String {
        switch self {
        case .running: return "running"
        case .waiting: return "waiting"
        case .idle: return "idle"
        case .completed: return "done"
        case .killed: return "done"
        case .error: return "error"
        }
    }

    public static func parse(_ raw: String?) -> SubagentState {
        let upper = (raw ?? "").uppercased()
        if upper.contains("RUNNING") || upper.contains("ACTIVE") || upper.contains("WORKING") {
            return .running
        }
        if upper.contains("WAIT") {
            return .waiting
        }
        if upper.contains("IDLE") {
            return .idle
        }
        if upper.contains("ERROR") || upper.contains("FAIL") {
            return .error
        }
        if upper.contains("KILL") {
            return .killed
        }
        return .completed
    }
}

public struct SubagentRecord: Sendable, Equatable, Identifiable {
    public var id: String { conversationId }
    public let conversationId: String
    public let typeName: String
    public let role: String
    public let state: SubagentState
    public let spawnStepIndex: Int?
    public let isSwarmWorker: Bool
    public let liveActivityHint: String?

    public init(
        conversationId: String,
        typeName: String,
        role: String,
        state: SubagentState,
        spawnStepIndex: Int? = nil,
        isSwarmWorker: Bool = false,
        liveActivityHint: String? = nil
    ) {
        self.conversationId = conversationId
        self.typeName = typeName
        self.role = role
        self.state = state
        self.spawnStepIndex = spawnStepIndex
        self.isSwarmWorker = isSwarmWorker
        self.liveActivityHint = liveActivityHint
    }

    public var isActive: Bool {
        state.isActive
    }
}

public struct SwarmSubagentUpdate: Sendable, Equatable {
    public let swarm: SwarmSnapshot?
    public let subagents: [SubagentRecord]

    public init(swarm: SwarmSnapshot?, subagents: [SubagentRecord]) {
        self.swarm = swarm
        self.subagents = subagents
    }
}
