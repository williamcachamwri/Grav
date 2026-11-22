import SwiftUI

/// Clean, zero-badge-clutter chronological file mutation stream with smooth expandable
/// unified diff drawers and one-click Finder, Antigravity, and Copy Diff actions.
public struct FilesTelemetryTabView: View {
    public var store: AntigravityTelemetryStore
    @Binding public var selectedFileID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var fileHoverNamespace

    private enum FileFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case edited = "Edited"
        case created = "Created"
        case deleted = "Deleted"

        var id: String { rawValue }

        func matches(_ event: FileChangeEvent) -> Bool {
            switch self {
            case .all: return true
            case .edited: return event.kind == .edit || event.kind == .overwrite
            case .created: return event.kind == .create
            case .deleted: return event.kind == .delete
            }
        }
    }

    @State private var activeFilter: FileFilter = .all
    @State private var hoveredFileID: String?
    @State private var copiedFileID: String?
    @State private var copiedPathFileID: String?
    @State private var copyFeedbackTask: Task<Void, Never>?

    private var filteredFileChanges: [FileChangeEvent] {
        store.fileChanges.filter { activeFilter.matches($0) }
    }

    private var shouldShowFilterBar: Bool {
        let kinds = Set(store.fileChanges.map { event -> FileFilter in
            switch event.kind {
            case .create: return .created
            case .delete: return .deleted
            case .edit, .overwrite: return .edited
            }
        })
        return kinds.count >= 2
    }

    public init(
        store: AntigravityTelemetryStore,
        selectedFileID: Binding<String?>
    ) {
        self.store = store
        self._selectedFileID = selectedFileID
    }

    public var body: some View {
        Group {
            if store.fileChanges.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    if shouldShowFilterBar {
                        HStack(spacing: 10) {
                            ForEach(FileFilter.allCases) { filter in
                                let isSelected = activeFilter == filter
                                let count = store.fileChanges.filter { filter.matches($0) }.count
                                if filter == .all || count > 0 {
                                    Button {
                                        if reduceMotion {
                                            activeFilter = filter
                                        } else {
                                            withAnimation(GravMotion.subtleFade) {
                                                activeFilter = filter
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 3.5) {
                                            Text(filter.rawValue)
                                                .font(.system(size: 10.5, weight: isSelected ? .medium : .regular))
                                                .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.38))
                                            Text("\(count)")
                                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                                .monospacedDigit()
                                                .foregroundStyle(isSelected ? Color.white.opacity(0.56) : Color.white.opacity(0.24))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 1)
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredFileChanges) { event in
                                fileRowCard(for: event)
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
                                .init(color: .black, location: 0.93),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : GravMotionSpec.settle.animation, value: store.fileChanges.first?.id)
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
    }

    // MARK: - File Row & Inline Diff Drawer

    private func fileRowCard(for event: FileChangeEvent) -> some View {
        let isExpanded = selectedFileID == event.id
        let isHovered = hoveredFileID == event.id
        let tint = NotchTelemetryHelpers.color(for: event.kind)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleSelection(for: event)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: kindSymbol(for: event.kind))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 14, alignment: .center)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.basename)
                            .font(.system(size: 11.5, weight: .medium))
                            .tracking(-0.15)
                            .foregroundStyle(Color.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(NotchTelemetryHelpers.compactParentPath(for: event.path))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.36))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }

                    Spacer(minLength: 8)

                    NotchProportionalDiffMicroBar(
                        added: event.addedLines,
                        removed: event.removedLines,
                        isDeleted: event.kind == .delete,
                        showBar: true,
                        barWidth: 28,
                        barHeight: 2.5
                    )

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.32))
                        .frame(width: 12)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    if isHovered && !isExpanded {
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .matchedGeometryEffect(id: "files-row-hover-pill", in: fileHoverNamespace)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if reduceMotion {
                    hoveredFileID = hovering ? event.id : (hoveredFileID == event.id ? nil : hoveredFileID)
                } else {
                    withAnimation(GravMotion.rowHover) {
                        if hovering {
                            hoveredFileID = event.id
                        } else if hoveredFileID == event.id {
                            hoveredFileID = nil
                        }
                    }
                }
            }

            if isExpanded {
                inlineDiffDrawer(for: event)
                    .transition(.opacity)
            }
        }
        .background {
            if isExpanded {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.042))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                    )
            }
        }
    }

    private static let maxRenderedDiffLines = 120

    private func inlineDiffDrawer(for event: FileChangeEvent) -> some View {
        let allLines = event.diffHunks.flatMap(\.lines)
        let displayedLines = Array(allLines.prefix(Self.maxRenderedDiffLines))
        let hiddenLineCount = max(0, allLines.count - displayedLines.count)

        return VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal, 8)

            if allLines.isEmpty {
                Text(
                    event.kind == .delete
                        ? "File removed from workspace."
                        : "No inline diff hunks captured for \(event.toolName)."
                )
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.46))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            } else {
                ScrollView([.vertical, .horizontal], showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(displayedLines.enumerated()), id: \.offset) { _, line in
                            diffLineRow(line)
                        }
                        if hiddenLineCount > 0 {
                            Text("+\(hiddenLineCount) more lines — use Copy Diff for full patch")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.36))
                                .padding(.horizontal, 6)
                                .padding(.top, 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 118)
                .padding(.horizontal, 6)
            }

            diffActionBar(for: event)
        }
        .padding(.bottom, 6)
    }

    private func diffLineRow(_ line: FileDiffLine) -> some View {
        HStack(spacing: 6) {
            Text(gutterPrefix(for: line.kind))
                .font(GravTypography.monoMicro)
                .foregroundStyle(gutterColor(for: line.kind))
                .frame(width: 9, alignment: .center)

            Text(line.text.isEmpty ? " " : line.text)
                .font(GravTypography.monoMicro)
                .foregroundStyle(lineTextColor(for: line.kind))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(lineBackground(for: line.kind))
        .clipShape(RoundedRectangle.grav(3))
    }

    private func diffActionBar(for event: FileChangeEvent) -> some View {
        let isCopied = copiedFileID == event.id

        return HStack(spacing: 4) {
            Button {
                store.revealInFinder(path: event.path)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("Finder")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
            }
            .buttonStyle(NotchChromeButtonStyle(cornerRadius: 5.5))

            Button {
                store.openInAntigravity(path: event.path)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("Antigravity")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
            }
            .buttonStyle(NotchChromeButtonStyle(cornerRadius: 5.5))

            Spacer(minLength: 4)

            Button {
                copyPath(for: event)
            } label: {
                let isPathCopied = copiedPathFileID == event.id
                HStack(spacing: 4) {
                    Image(systemName: isPathCopied ? "checkmark" : "link")
                        .font(.system(size: 9.5, weight: .medium))
                    Text(isPathCopied ? "Copied" : "Path")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(isPathCopied ? GravPalette.emerald : Color.white.opacity(0.68))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
            }
            .buttonStyle(NotchChromeButtonStyle(isActive: copiedPathFileID == event.id, cornerRadius: 5.5))

            Button {
                copyDiff(for: event)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5, weight: .medium))
                    Text(isCopied ? "Copied" : "Copy Diff")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(isCopied ? GravPalette.emerald : Color.white.opacity(0.72))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
            }
            .buttonStyle(NotchChromeButtonStyle(isActive: isCopied, cornerRadius: 5.5))
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Helpers

    private func toggleSelection(for event: FileChangeEvent) {
        let next: String? = (selectedFileID == event.id) ? nil : event.id
        if reduceMotion {
            selectedFileID = next
        } else {
            withAnimation(GravMotion.contentSlide) {
                selectedFileID = next
            }
        }
    }

    private func copyPath(for event: FileChangeEvent) {
        NotchTelemetryHelpers.copyToPasteboard(event.path)
        copiedPathFileID = event.id
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            if copiedPathFileID == event.id {
                copiedPathFileID = nil
            }
        }
    }

    private func copyDiff(for event: FileChangeEvent) {
        let diff = NotchTelemetryHelpers.formatUnifiedDiff(for: event)
        NotchTelemetryHelpers.copyToPasteboard(diff)
        copiedFileID = event.id
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            if copiedFileID == event.id {
                copiedFileID = nil
            }
        }
    }

    private func kindSymbol(for kind: FileChangeKind) -> String {
        switch kind {
        case .create: return "plus.circle"
        case .edit, .overwrite: return "pencil"
        case .delete: return "trash"
        }
    }

    private func gutterPrefix(for kind: FileDiffLine.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private func gutterColor(for kind: FileDiffLine.Kind) -> Color {
        switch kind {
        case .added: return GravPalette.emerald
        case .removed: return GravPalette.coral
        case .context: return GravPalette.inkQuaternary
        }
    }

    private func lineTextColor(for kind: FileDiffLine.Kind) -> Color {
        switch kind {
        case .added: return GravPalette.inkPrimary
        case .removed: return GravPalette.inkSecondary
        case .context: return GravPalette.inkTertiary
        }
    }

    private func lineBackground(for kind: FileDiffLine.Kind) -> Color {
        switch kind {
        case .added: return GravPalette.emerald.opacity(0.08)
        case .removed: return GravPalette.coral.opacity(0.08)
        case .context: return Color.clear
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "doc.text")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.30))

            Text("No File Changes")
                .font(.system(size: 12, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.76))

            Text("Edited, created, and deleted files appear here with inline diffs.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.38))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
