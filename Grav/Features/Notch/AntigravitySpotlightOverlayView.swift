import SwiftUI

// MARK: - Feature #1: Inline FTS5 Spotlight Search Overlay (`⌘K`)

/// Raycast-grade inline full-text Spotlight palette querying Antigravity's native SQLite FTS5 index
/// (`conversations_fts`) across every local workspace, prompt, and reply.
public struct AntigravitySpotlightOverlayView: View {
    public var store: AntigravityTelemetryStore
    public var onSelectSession: (String, Bool) -> Void
    public var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isSearchFocused: Bool

    @State private var query: String = ""
    @State private var hits: [AntigravitySpotlightHit] = []
    @State private var selectedIndex: Int = 0
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?

    public init(
        store: AntigravityTelemetryStore,
        onSelectSession: @escaping (String, Bool) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.onSelectSession = onSelectSession
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchInputBar

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            resultsList

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            footerHints
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.075, green: 0.080, blue: 0.098).opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.75)
                )
        )
        .shadow(color: Color.black.opacity(0.55), radius: 18, y: 8)
        .onAppear {
            isSearchFocused = true
            runSearch(query: "")
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onChange(of: query) { _, newValue in
            runSearch(query: newValue)
        }
        .onKeyPress(.downArrow) {
            moveSelection(delta: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(delta: -1)
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private var searchInputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.52))

            TextField("Search all Antigravity chats, prompts & replies…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.94))
                .focused($isSearchFocused)
                .onSubmit {
                    confirmSelected(focusAntigravity: false)
                }

            if isSearching {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.72)
            } else if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.36))
                }
                .buttonStyle(.plain)
            }

            Button {
                onDismiss()
            } label: {
                Text("ESC")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var resultsList: some View {
        if hits.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.28))
                Text(query.isEmpty ? "No Antigravity sessions indexed yet" : "No matches for “\(query)”")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.46))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                            spotlightRow(hit: hit, isSelected: index == selectedIndex)
                                .id(hit.id)
                                .onTapGesture {
                                    selectedIndex = index
                                    confirmSelected(focusAntigravity: false)
                                }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selectedIndex) { _, idx in
                    if hits.indices.contains(idx) {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                            proxy.scrollTo(hits[idx].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func spotlightRow(hit: AntigravitySpotlightHit, isSelected: Bool) -> some View {
        let isActiveSession = store.activeSession?.id == hit.conversationID

        return HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(statusColor(for: hit))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 6) {
                    Text(hit.title)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(Color.white.opacity(isSelected ? 0.96 : 0.84))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isActiveSession {
                        Text("ACTIVE")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                            )
                    } else if hit.isUnread {
                        Text("UNREAD")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(GravPalette.glacialCyan)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(GravPalette.glacialCyan.opacity(0.16))
                            )
                    }

                    Spacer(minLength: 4)

                    if let ws = hit.workspaceName, !ws.isEmpty {
                        Text(ws)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(1)
                    }

                    if let modified = hit.lastModified {
                        Text(relativeShortTime(modified))
                            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.34))
                    }
                }

                if !hit.snippet.isEmpty {
                    Text(hit.snippet)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(isSelected ? 0.62 : 0.42))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            if isSelected {
                Button {
                    onSelectSession(hit.conversationID, true)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                .fill(Color.white.opacity(0.09))
                        )
                }
                .buttonStyle(.plain)
                .help("Open in Grav & Focus Antigravity")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.095) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.white.opacity(0.12) : Color.clear, lineWidth: 0.5)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footerHints: some View {
        HStack(spacing: 12) {
            hintBadge(keys: "↑↓", label: "Navigate")
            hintBadge(keys: "↵", label: "Inspect in Notch")
            Spacer()
            Text("\(hits.count) indexed")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.32))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func hintBadge(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.38))
        }
    }

    private func statusColor(for hit: AntigravitySpotlightHit) -> Color {
        if hit.isRunning { return GravPalette.glacialCyan }
        if hit.isUnread { return GravPalette.emerald }
        return Color.white.opacity(0.24)
    }

    private func relativeShortTime(_ date: Date) -> String {
        let delta = max(0, Int(Date().timeIntervalSince(date)))
        if delta < 60 { return "now" }
        if delta < 3600 { return "\(delta / 60)m" }
        if delta < 86_400 { return "\(delta / 3600)h" }
        return "\(delta / 86_400)d"
    }

    private func moveSelection(delta: Int) {
        guard !hits.isEmpty else { return }
        selectedIndex = max(0, min(hits.count - 1, selectedIndex + delta))
    }

    private func confirmSelected(focusAntigravity: Bool) {
        guard hits.indices.contains(selectedIndex) else { return }
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        onSelectSession(hits[selectedIndex].conversationID, focusAntigravity)
    }

    private func runSearch(query: String) {
        searchTask?.cancel()
        isSearching = true
        searchTask = Task {
            if !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(85))
            }
            guard !Task.isCancelled else { return }
            let results = await store.searchConversations(query: query, limit: 24)
            guard !Task.isCancelled else { return }
            hits = results
            selectedIndex = 0
            isSearching = false
        }
    }
}

// MARK: - Feature #2: Approval & Question Banner Strip

/// Compact, anti-AI-slop matte alert strip shown only when Antigravity needs user approval or an answer.
public struct AntigravityRadarBannerView: View {
    public let alert: AntigravityRadarAlert
    public let onFocusAntigravity: () -> Void
    public let onDismiss: () -> Void

    public init(
        alert: AntigravityRadarAlert,
        onFocusAntigravity: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.alert = alert
        self.onFocusAntigravity = onFocusAntigravity
        self.onDismiss = onDismiss
    }

    private var accentColor: Color {
        Color(red: 0.96, green: 0.72, blue: 0.28)
    }

    public var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accentColor)
                .frame(width: 2.5, height: 22)

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(alert.badge)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(accentColor.opacity(0.14))
                        )

                    Text(alert.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                }

                Text(alert.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.54))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 6)

            Button {
                GravOnboardingWelcomeAudio.shared.playButtonTap()
                onFocusAntigravity()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("Focus")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Dismiss alert")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(Color.white.opacity(0.048))
                .overlay(
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.26), lineWidth: 0.65)
                )
        )
    }
}
