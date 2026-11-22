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
                    LazyVStack(spacing: 4) {
                        ForEach(store.fileChanges) { event in
                            fileRowCard(for: event)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
    }

    // MARK: - File Row & Inline Diff Drawer

    private func fileRowCard(for event: FileChangeEvent) -> some View {
        let isExpanded = selectedFileID == event.id
        let isHovered = hoveredFileID == event.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleSelection(for: event)
            } label: {
                HStack(spacing: 8) {
                    NotchSemanticDot(
                        color: NotchTelemetryHelpers.color(for: event.kind),
                        size: 6,
                        isPulsing: false
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(event.basename)
                                .font(GravTypography.monoTitle)
                                .foregroundStyle(GravPalette.inkPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text(kindCode(for: event.kind))
                                .font(GravTypography.monoMicro)
                                .foregroundStyle(NotchTelemetryHelpers.color(for: event.kind).opacity(0.82))
                        }

                        Text(NotchTelemetryHelpers.compactParentPath(for: event.path))
                            .font(GravTypography.monoMicro)
                            .foregroundStyle(GravPalette.inkQuaternary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }

                    Spacer(minLength: GravSpacing.xs)

                    NotchProportionalDiffMicroBar(
                        added: event.addedLines,
                        removed: event.removedLines,
                        isDeleted: event.kind == .delete,
                        showBar: true,
                        barWidth: 34,
                        barHeight: 3
                    )

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(GravPalette.inkQuaternary)
                        .frame(width: 12)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background {
                    if isHovered && !isExpanded {
                        RoundedRectangle.grav(GravRadius.controlS)
                            .fill(GravPalette.cardFillBase)
                            .overlay(
                                RoundedRectangle.grav(GravRadius.controlS)
                                    .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                            )
                            .matchedGeometryEffect(id: "files-row-hover-pill", in: fileHoverNamespace)
                    }
                }
                .contentShape(RoundedRectangle.grav(GravRadius.controlS))
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
                RoundedRectangle.grav(GravRadius.controlM)
                    .fill(GravPalette.cardFillSubtle)
                    .overlay(
                        RoundedRectangle.grav(GravRadius.controlM)
                            .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                    )
            }
        }
    }

    private func inlineDiffDrawer(for event: FileChangeEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(GravPalette.hairlineMid.opacity(0.6))
                .frame(height: 0.5)
                .padding(.horizontal, 9)

            if event.diffHunks.isEmpty {
                Text(
                    event.kind == .delete
                        ? "File removed from workspace."
                        : "No inline diff hunks captured for \(event.toolName)."
                )
                .font(GravTypography.monoMicro)
                .foregroundStyle(GravPalette.inkTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            } else {
                ScrollView([.vertical, .horizontal], showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(event.diffHunks) { hunk in
                            ForEach(hunk.lines) { line in
                                diffLineRow(line)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 108)
                .padding(.horizontal, 6)
            }

            diffActionBar(for: event)
        }
        .padding(.bottom, 7)
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
                        .font(GravTypography.micro)
                }
                .foregroundStyle(GravPalette.inkSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
            }
            .buttonStyle(NotchChromeButtonStyle(cornerRadius: GravRadius.controlXS))

            Button {
                store.openInAntigravity(path: event.path)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("Open in Antigravity")
                        .font(GravTypography.micro)
                }
                .foregroundStyle(GravPalette.inkSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
            }
            .buttonStyle(NotchChromeButtonStyle(cornerRadius: GravRadius.controlXS))

            Spacer(minLength: 4)

            Button {
                copyDiff(for: event)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5, weight: .medium))
                    Text(isCopied ? "Copied" : "Copy Diff")
                        .font(GravTypography.micro)
                }
                .foregroundStyle(isCopied ? GravPalette.emerald : GravPalette.inkSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
            }
            .buttonStyle(NotchChromeButtonStyle(isActive: isCopied, cornerRadius: GravRadius.controlXS))
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

    private func kindCode(for kind: FileChangeKind) -> String {
        switch kind {
        case .create: return "NEW"
        case .edit: return "MOD"
        case .overwrite: return "WRT"
        case .delete: return "DEL"
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
        VStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(GravPalette.inkQuaternary)

            Text("NO FILE MUTATIONS")
                .font(GravTypography.monoMicro)
                .foregroundStyle(GravPalette.inkTertiary)

            Text("Edited, created, and deleted files will appear here with inline diffs.")
                .font(GravTypography.caption)
                .foregroundStyle(GravPalette.inkQuaternary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
