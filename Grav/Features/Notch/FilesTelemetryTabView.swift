import SwiftUI

/// Chronological file mutation stream with magnetic row hover, expandable inline mini-diff hunks,
/// and one-click Reveal in Finder, Open in Antigravity, and Copy Diff actions.
public struct FilesTelemetryTabView: View {
    public var store: AntigravityTelemetryStore
    @Binding public var selectedFileID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var fileHoverNamespace

    @State private var hoveredFileID: String?
    @State private var copiedFileID: String?
    @State private var copyFeedbackTask: Task<Void, Never>?

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
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3.5) {
                        ForEach(store.fileChanges) { event in
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
                    .padding(.vertical, 2)
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
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(tint.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(tint.opacity(0.28), lineWidth: 0.5)
                            )

                        Image(systemName: kindSymbol(for: event.kind))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 19, height: 19)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(event.basename)
                                .font(.system(size: 11.5, weight: .semibold))
                                .tracking(-0.1)
                                .foregroundStyle(Color.white.opacity(0.95))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text(kindLabel(for: event.kind))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(tint.opacity(0.92))
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 0.5)
                                .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))
                        }

                        Text(NotchTelemetryHelpers.compactParentPath(for: event.path))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.38))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }

                    Spacer(minLength: 6)

                    NotchProportionalDiffMicroBar(
                        added: event.addedLines,
                        removed: event.removedLines,
                        isDeleted: event.kind == .delete,
                        showBar: true,
                        barWidth: 32,
                        barHeight: 3
                    )

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .frame(width: 12)
                }
                .padding(.horizontal, 8.5)
                .padding(.vertical, 5)
                .background {
                    if isHovered && !isExpanded {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.065))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                            )
                            .matchedGeometryEffect(id: "files-row-hover-pill", in: fileHoverNamespace)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            }
        }
    }

    private static let maxRenderedDiffLines = 120

    private func inlineDiffDrawer(for event: FileChangeEvent) -> some View {
        let allLines = event.diffHunks.flatMap(\.lines)
        let displayedLines = Array(allLines.prefix(Self.maxRenderedDiffLines))
        let hiddenLineCount = max(0, allLines.count - displayedLines.count)

        return VStack(alignment: .leading, spacing: 5) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 9)

            if allLines.isEmpty {
                Text(
                    event.kind == .delete
                        ? "File removed from workspace."
                        : "No inline diff hunks captured for \(event.toolName)."
                )
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.48))
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
                                .foregroundStyle(Color.white.opacity(0.38))
                                .padding(.horizontal, 6)
                                .padding(.top, 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 112)
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

        return HStack(spacing: 6) {
            Button {
                store.revealInFinder(path: event.path)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("Reveal in Finder")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
            }
            .buttonStyle(NotchChromeButtonStyle(cornerRadius: 6))

            Button {
                store.openInAntigravity(path: event.path)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("Open in Antigravity")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
            }
            .buttonStyle(NotchChromeButtonStyle(cornerRadius: 6))

            Spacer(minLength: 4)

            Button {
                copyDiff(for: event)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5, weight: .medium))
                    Text(isCopied ? "Copied" : "Copy Diff")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(isCopied ? GravPalette.emerald : Color.white.opacity(0.78))
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
            }
            .buttonStyle(NotchChromeButtonStyle(isActive: isCopied, cornerRadius: 6))
        }
        .padding(.horizontal, 9)
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
        case .create: return "plus"
        case .edit: return "pencil.line"
        case .overwrite: return "doc.badge.gearshape"
        case .delete: return "trash.fill"
        }
    }

    private func kindLabel(for kind: FileChangeKind) -> String {
        switch kind {
        case .create: return "New"
        case .edit: return "Edit"
        case .overwrite: return "Write"
        case .delete: return "Del"
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
        case .added: return GravPalette.emerald.opacity(0.09)
        case .removed: return GravPalette.coral.opacity(0.09)
        case .context: return Color.clear
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "doc.text")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.32))

            Text("No File Mutations")
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.76))

            Text("Edited, created, and deleted files will appear here with inline diffs.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
