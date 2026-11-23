import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let gravOpenNotchTray = Notification.Name("com.grav.openNotchTray")
}

/// Flush, zero-popover Notch Drop Shelf + Inline Prompt Composer + Follow-Up Prompt Queue.
///
/// Strict Anti-AI-Slop craft:
/// - Sits directly on the pitch-black Notch surface (zero nested cards, zero neon glows).
/// - Staged files/images animate in as a tactile fanned micro-card deck (`±2.2°` physical tilt,
///   straightening and lifting smoothly on hover) with native macOS drag-OUT (`.draggable(url)`).
/// - Borderless prompt input lets you draft follow-ups while Antigravity is busy, queue them
///   persistently, or send them straight into Antigravity chat via `antigravity://open?prompt=...` (`⌘↵`).
public struct NotchDropComposerView: View {
    public var store: AntigravityTelemetryStore
    public var trayStore: NotchTrayStore
    @Binding public var isInputFocused: Bool
    public var onShowToast: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var promptFieldFocused: Bool

    @State private var hoveredItemID: String?
    @State private var hoveredQueueID: String?
    @State private var isDropHovered: Bool = false

    public init(
        store: AntigravityTelemetryStore,
        trayStore: NotchTrayStore = .shared,
        isInputFocused: Binding<Bool>,
        onShowToast: @escaping (String) -> Void
    ) {
        self.store = store
        self.trayStore = trayStore
        self._isInputFocused = isInputFocused
        self.onShowToast = onShowToast
    }

    public var body: some View {
        @Bindable var tray = trayStore

        VStack(alignment: .leading, spacing: 8) {
            dropDeckSection

            promptComposerSection(draftBinding: $tray.draftPrompt)

            if !trayStore.queuedPrompts.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 0.5)

                queuedPromptsSection
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [.fileURL, .image, .plainText], isTargeted: $isDropHovered) { providers in
            handleProviders(providers)
        }
        .onChange(of: isDropHovered) { _, targeted in
            trayStore.isDropTargeted = targeted
            if targeted {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        .onChange(of: promptFieldFocused) { _, focused in
            isInputFocused = focused
        }
        .onAppear {
            activateNotchPanelForTyping()
        }
        .onDisappear {
            isInputFocused = false
            trayStore.isDropTargeted = false
        }
    }

    // MARK: - Tactile Magnetic Drop Deck (Fanned Studio Micro-Cards)

    @ViewBuilder
    private var dropDeckSection: some View {
        if trayStore.stagedItems.isEmpty {
            emptyDropTarget
        } else {
            stagedCardDeck
        }
    }

    private var emptyDropTarget: some View {
        HStack(spacing: 9) {
            Image(systemName: isDropHovered ? "arrow.down.to.line.compact" : "tray.and.arrow.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isDropHovered ? Color.white : Color.white.opacity(0.42))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(Color.white.opacity(isDropHovered ? 0.14 : 0.05))
                )
                .scaleEffect(!reduceMotion && isDropHovered ? 1.08 : 1.0)

            VStack(alignment: .leading, spacing: 1) {
                Text(isDropHovered ? "Release to stage onto Notch" : "Drop files, screenshots, or code here")
                    .font(.system(size: 11.5, weight: isDropHovered ? .medium : .regular))
                    .foregroundStyle(isDropHovered ? Color.white.opacity(0.95) : Color.white.opacity(0.62))

                Text("Drag items straight out into Antigravity or pair with a prompt below.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.32))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                browseLocalFiles()
            } label: {
                Text("Browse")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.065))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isDropHovered ? 0.075 : 0.026))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(isDropHovered ? 0.42 : 0.10),
                            style: StrokeStyle(
                                lineWidth: isDropHovered ? 1.0 : 0.65,
                                dash: isDropHovered ? [4, 3] : [3, 3]
                            )
                        )
                )
        )
        .scaleEffect(!reduceMotion && isDropHovered ? 1.008 : 1.0)
        .animation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.18), value: isDropHovered)
    }

    private var stagedCardDeck: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(trayStore.stagedItems.enumerated()), id: \.element.id) { index, item in
                        fannedCard(for: item, index: index)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.82)).combined(with: .offset(y: -6)),
                                        removal: .opacity.combined(with: .scale(scale: 0.86))
                                    )
                            )
                    }

                    // Quiet inline "+ Add" micro-tile at the end of the deck
                    Button {
                        browseLocalFiles()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .frame(width: 38, height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.035))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.09), style: StrokeStyle(lineWidth: 0.6, dash: [3, 2.5]))
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Add another file")
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isDropHovered ? Color.white.opacity(0.055) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            isDropHovered ? Color.white.opacity(0.32) : Color.clear,
                            style: StrokeStyle(lineWidth: 0.85, dash: [4, 3])
                        )
                )
        )
        .animation(reduceMotion ? nil : .spring(duration: 0.30, bounce: 0.16), value: trayStore.stagedItems.map(\.id))
        .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.14), value: isDropHovered)
    }

    private func fannedCard(for item: StagedDropItem, index: Int) -> some View {
        let isHovered = hoveredItemID == item.id
        let restingAngle: Double = {
            if reduceMotion || isHovered { return 0 }
            let angles: [Double] = [-2.2, 1.5, -1.3, 2.0, -1.6, 1.2]
            return angles[index % angles.count]
        }()

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 3) {
                Group {
                    if item.isImage, let img = trayStore.thumbnails[item.id] {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .padding(5)
                    }
                }
                .frame(width: 44, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

                Text(item.name)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isHovered ? 0.90 : 0.56))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 48)
            }
            .padding(3.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.10 : 0.048))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(isHovered ? 0.22 : 0.09),
                                lineWidth: 0.6
                            )
                    )
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.45 : 0.22), radius: isHovered ? 7 : 3, y: isHovered ? 3 : 1)
            .rotationEffect(.degrees(restingAngle))
            .scaleEffect(!reduceMotion && isHovered ? 1.06 : 1.0)
            .offset(y: !reduceMotion && isHovered ? -2.5 : 0)
            .draggable(item.url)
            .onTapGesture {
                NSWorkspace.shared.open(item.url)
            }

            if isHovered {
                Button {
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.12)) {
                        trayStore.removeStagedItem(id: item.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(width: 15, height: 15)
                        .background(
                            Circle()
                                .fill(Color(red: 0.14, green: 0.15, blue: 0.18))
                                .overlay(
                                    Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.6)
                                )
                        )
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.18)) {
                hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            }
        }
        .help("\(item.name) — Drag out to Antigravity or click to open")
    }

    // MARK: - Inline Borderless Prompt Composer

    private func promptComposerSection(draftBinding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                store.state.isActive
                    ? "Draft your next prompt while Antigravity works…"
                    : "Write a prompt to pair with staged files…",
                text: draftBinding,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.94))
            .lineLimit(1...3)
            .focused($promptFieldFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .fill(Color.white.opacity(promptFieldFocused ? 0.065 : 0.038))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(promptFieldFocused ? 0.18 : 0.08),
                                lineWidth: 0.6
                            )
                    )
            )
            .onSubmit {
                if NSEvent.modifierFlags.contains(.command) {
                    sendToAntigravityChat()
                } else {
                    queueCurrentDraft()
                }
            }

            HStack(spacing: 6) {
                if trayStore.hasComposableContent {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                            trayStore.draftPrompt = ""
                            trayStore.clearStagedItems()
                        }
                    } label: {
                        Text("Clear")
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.40))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("↵ Queue  ·  ⌘↵ Send to Chat")
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.28))
                }

                Spacer(minLength: 6)

                Button {
                    queueCurrentDraft()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 9.5, weight: .medium))
                        Text("Queue")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(trayStore.hasComposableContent ? 0.80 : 0.30))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(Color.white.opacity(trayStore.hasComposableContent ? 0.075 : 0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .strokeBorder(Color.white.opacity(trayStore.hasComposableContent ? 0.12 : 0.05), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!trayStore.hasComposableContent)

                Button {
                    sendToAntigravityChat()
                } label: {
                    HStack(spacing: 4.5) {
                        Text("Send")
                            .font(.system(size: 10.5, weight: .semibold))
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .foregroundStyle(trayStore.hasComposableContent ? Color.black.opacity(0.92) : Color.white.opacity(0.28))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(trayStore.hasComposableContent ? Color.white.opacity(0.94) : Color.white.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!trayStore.hasComposableContent)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send straight into Antigravity chat (⌘↵)")
            }
        }
    }

    // MARK: - Follow-Up Prompt Queue (Zero Clutter, Only Shown When Populated)

    private var queuedPromptsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Up next")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))
                Spacer()
                Text("\(trayStore.queuedPrompts.count) queued")
                    .font(.system(size: 9.5, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.32))
            }
            .padding(.horizontal, 2)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(trayStore.queuedPrompts.enumerated()), id: \.element.id) { index, item in
                        queuedPromptRow(item, index: index)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .top)),
                                        removal: .opacity.combined(with: .move(edge: .trailing))
                                    )
                            )
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.12), value: trayStore.queuedPrompts.map(\.id))
    }

    private func queuedPromptRow(_ item: QueuedPromptItem, index: Int) -> some View {
        let isHovered = hoveredQueueID == item.id

        return HStack(spacing: 7) {
            Text("\(index + 1)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.34))
                .frame(width: 12, alignment: .leading)

            Text(item.text)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(isHovered ? 0.94 : 0.78))
                .lineLimit(1)
                .truncationMode(.tail)

            if !item.attachedPaths.isEmpty {
                Text("\(item.attachedPaths.count) file\(item.attachedPaths.count == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )
            }

            Spacer(minLength: 4)

            if isHovered {
                Button {
                    sendQueuedPrompt(item)
                } label: {
                    HStack(spacing: 3.5) {
                        Text("Send")
                            .font(.system(size: 9.5, weight: .semibold))
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 7.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.black.opacity(0.90))
                    .padding(.horizontal, 7.5)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.90))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        trayStore.removeQueuedPrompt(id: item.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.065) : Color.white.opacity(0.024))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
        .onTapGesture {
            sendQueuedPrompt(item)
        }
        .onHover { hovering in
            hoveredQueueID = hovering ? item.id : (hoveredQueueID == item.id ? nil : hoveredQueueID)
        }
    }

    // MARK: - Actions

    private func handleProviders(_ providers: [NSItemProvider]) -> Bool {
        trayStore.handleDrop(providers: providers) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            onShowToast("Staged on Notch")
            activateNotchPanelForTyping()
        }
    }

    private func queueCurrentDraft() {
        guard trayStore.enqueueCurrentDraft() != nil else { return }
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        onShowToast("Queued for next turn")
    }

    private func sendToAntigravityChat() {
        guard let result = trayStore.sendCurrentBundleToAntigravity() else { return }
        promptFieldFocused = false
        isInputFocused = false
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        switch result {
        case .openedDeepLink:
            onShowToast("Sent to Antigravity chat")
        case .copiedToClipboardFallback:
            onShowToast("Copied · Paste ⌘V in Antigravity")
            store.activateAntigravityApp()
        }
    }

    private func sendQueuedPrompt(_ item: QueuedPromptItem) {
        guard let result = trayStore.sendQueuedPromptToAntigravity(id: item.id) else { return }
        promptFieldFocused = false
        isInputFocused = false
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        switch result {
        case .openedDeepLink:
            onShowToast("Sent to Antigravity chat")
        case .copiedToClipboardFallback:
            onShowToast("Copied · Paste ⌘V in Antigravity")
            store.activateAntigravityApp()
        }
    }

    private func browseLocalFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.title = "Stage files on Grav Notch"
        panel.prompt = "Stage"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            let added = trayStore.stageFileURLs(panel.urls)
            if added > 0 {
                onShowToast("Staged \(added) item\(added == 1 ? "" : "s")")
            }
            activateNotchPanelForTyping()
        }
    }

    private func activateNotchPanelForTyping() {
        NSApp.activate(ignoringOtherApps: true)
        if let notchPanel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) {
            notchPanel.makeKeyAndOrderFront(nil)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(35))
            promptFieldFocused = true
        }
    }
}
