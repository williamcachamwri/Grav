import AppKit
import SwiftUI

/// Feature #4: Artifacts, Plans, Scratch Scripts & Media Quick-Look browser inside the Notch HUD.
public struct ArtifactsQuickLookView: View {
    public var store: AntigravityTelemetryStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedKind: SessionArtifactItem.Kind? = nil
    @State private var selectedArtifactID: String?
    @State private var previewText: String?
    @State private var previewImage: NSImage?
    @State private var previewTask: Task<Void, Never>?

    public init(store: AntigravityTelemetryStore) {
        self.store = store
    }

    private var filteredItems: [SessionArtifactItem] {
        guard let selectedKind else { return store.sessionArtifacts }
        return store.sessionArtifacts.filter { $0.kind == selectedKind }
    }

    private var selectedArtifact: SessionArtifactItem? {
        if let id = selectedArtifactID,
           let match = filteredItems.first(where: { $0.id == id })
        {
            return match
        }
        return filteredItems.first
    }

    public var body: some View {
        Group {
            if store.sessionArtifacts.isEmpty {
                emptyState
            } else {
                VStack(spacing: 5) {
                    filterStrip

                    HStack(spacing: 8) {
                        artifactListRail
                            .frame(width: 188)

                        if let artifact = selectedArtifact {
                            artifactPreviewPane(for: artifact)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            store.refreshSessionArtifacts()
            if selectedArtifactID == nil {
                selectedArtifactID = filteredItems.first?.id
            }
            loadPreview(for: selectedArtifact)
        }
        .onChange(of: selectedArtifact?.id) { _, _ in
            loadPreview(for: selectedArtifact)
        }
        .onDisappear {
            previewTask?.cancel()
        }
    }

    private var filterStrip: some View {
        HStack(spacing: 10) {
            filterChip(label: "All", count: store.sessionArtifacts.count, kind: nil)
            ForEach(SessionArtifactItem.Kind.allCases, id: \.self) { kind in
                let count = store.sessionArtifacts.filter { $0.kind == kind }.count
                if count > 0 {
                    filterChip(label: kind.rawValue, count: count, kind: kind)
                }
            }
            Spacer()
            Button {
                store.refreshSessionArtifacts()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Refresh session artifacts")
        }
        .padding(.horizontal, 6)
    }

    private func filterChip(label: String, count: Int, kind: SessionArtifactItem.Kind?) -> some View {
        let isSelected = selectedKind == kind
        return Button {
            withAnimation(reduceMotion ? nil : GravMotion.subtleFade) {
                selectedKind = kind
                selectedArtifactID = nil
            }
        } label: {
            HStack(spacing: 3.5) {
                Text(label)
                    .font(.system(size: 10.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.40))
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white.opacity(0.56) : Color.white.opacity(0.24))
            }
        }
        .buttonStyle(.plain)
    }

    private var artifactListRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(filteredItems) { item in
                    let isSelected = selectedArtifact?.id == item.id
                    Button {
                        selectedArtifactID = item.id
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: item.kind.symbolName)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.44))
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 1.5) {
                                Text(item.name)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.78))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                HStack(spacing: 5) {
                                    Text(item.relativePath)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.34))
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                    Spacer(minLength: 2)
                                    Text(item.formattedSize)
                                        .font(.system(size: 9, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundStyle(Color.white.opacity(0.30))
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? Color.white.opacity(0.09) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func artifactPreviewPane(for item: SessionArtifactItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(item.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    NSWorkspace.shared.open(item.url)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "eye")
                            .font(.system(size: 9.5, weight: .medium))
                        Text("Open")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.76))
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .frame(width: 22, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            Group {
                if item.kind == .image, let img = previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(8)
                } else if let text = previewText, !text.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(text)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.74))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(9)
                    }
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: item.kind.symbolName)
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.32))
                        Text("Binary file · \(item.formattedSize)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.white.opacity(0.28))
            Text("No artifacts or scratch files in this session")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.46))
            Text("Plans, walkthroughs, screenshots & scratch scripts appear here automatically.")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.30))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadPreview(for item: SessionArtifactItem?) {
        previewTask?.cancel()
        previewText = nil
        previewImage = nil
        guard let item else { return }

        let url = item.url
        let kind = item.kind
        previewTask = Task {
            if kind == .image {
                let image = await Task.detached(priority: .userInitiated) {
                    NSImage(contentsOf: url)
                }.value
                guard !Task.isCancelled else { return }
                previewImage = image
            } else {
                let text = await Task.detached(priority: .userInitiated) { () -> String? in
                    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
                    defer { try? handle.close() }
                    let data = (try? handle.read(upToCount: 8192)) ?? Data()
                    return String(data: data, encoding: .utf8)
                }.value
                guard !Task.isCancelled else { return }
                previewText = text
            }
        }
    }
}
