import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let gravOpenNotchTray = Notification.Name("com.grav.openNotchTray")
}

// MARK: - Native AppKit NSDraggingDestination Catcher

/// Reliable AppKit `NSDraggingDestination` bridge that intercepts Finder files, macOS Screenshots,
/// Safari/Chrome/Figma dragged images, `NSFilePromiseReceiver` promises, and text drops across
/// the Notch drop zones — while passing 100% of clicks/typing/hover through when idle.
public struct NotchNativeDropBridgeView: NSViewRepresentable {
    public var isCatchingActive: Bool
    public var onTargetedChanged: (Bool) -> Void
    public var onDropPasteboard: (NSPasteboard) -> Int
    public var onPromisedURLs: ([URL]) -> Void

    public init(
        isCatchingActive: Bool,
        onTargetedChanged: @escaping (Bool) -> Void,
        onDropPasteboard: @escaping (NSPasteboard) -> Int,
        onPromisedURLs: @escaping ([URL]) -> Void
    ) {
        self.isCatchingActive = isCatchingActive
        self.onTargetedChanged = onTargetedChanged
        self.onDropPasteboard = onDropPasteboard
        self.onPromisedURLs = onPromisedURLs
    }

    public func makeNSView(context: Context) -> NativeDropCatcherNSView {
        let view = NativeDropCatcherNSView()
        view.isCatchingActive = isCatchingActive
        view.onTargetedChanged = onTargetedChanged
        view.onDropPasteboard = onDropPasteboard
        view.onPromisedURLs = onPromisedURLs
        return view
    }

    public func updateNSView(_ nsView: NativeDropCatcherNSView, context: Context) {
        nsView.isCatchingActive = isCatchingActive
        nsView.onTargetedChanged = onTargetedChanged
        nsView.onDropPasteboard = onDropPasteboard
        nsView.onPromisedURLs = onPromisedURLs
    }
}

public final class NativeDropCatcherNSView: NSView {
    var isCatchingActive: Bool = false
    var onTargetedChanged: ((Bool) -> Void)?
    var onDropPasteboard: ((NSPasteboard) -> Int)?
    var onPromisedURLs: (([URL]) -> Void)?

    private static let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.grav.notch.filePromise"
        q.qualityOfService = .userInitiated
        return q
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerTypes()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerTypes()
    }

    private func registerTypes() {
        var types: [NSPasteboard.PasteboardType] = [
            .fileURL,
            .png,
            .tiff,
            .string,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("org.webmproject.webp"),
        ]
        types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        registerForDraggedTypes(types)
    }

    /// Passes normal clicks, typing, scrolling, and hover straight through to SwiftUI when not dragging.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard isCatchingActive else { return nil }
        return super.hitTest(point)
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTargetedChanged?(true)
        return .copy
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    public override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetedChanged?(false)
    }

    public override func draggingEnded(_ sender: NSDraggingInfo) {
        onTargetedChanged?(false)
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetedChanged?(false)
        let pb = sender.draggingPasteboard

        if let count = onDropPasteboard?(pb), count > 0 {
            return true
        }

        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !receivers.isEmpty
        {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let destDir = caches.appendingPathComponent("com.grav.telemetry/DropShelf", isDirectory: true)
            try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

            for receiver in receivers {
                receiver.receivePromisedFiles(atDestination: destDir, options: [:], operationQueue: Self.promiseQueue) { [weak self] url, error in
                    guard error == nil else { return }
                    Task { @MainActor [weak self] in
                        self?.onPromisedURLs?([url])
                    }
                }
            }
            return true
        }

        return false
    }
}

// MARK: - boring.notch-Inspired Dual-Zone Drop Shelf + Obsidian Prompt Composer

/// Dual-zone Notch Drop Shelf inspired by `TheBoredTeam/boring.notch` (`ShelfView` + `FileShareView` +
/// `ShelfItemView`), paired with Grav's flush borderless Antigravity Prompt Composer:
/// - **Left Square Pod (`Instant Send`)**: Drop an image/file straight onto it to immediately send/attach
///   into your active Antigravity session (or click to browse local files).
/// - **Right Expansive Shelf Bay (`Drop Shelf`)**: Drop 1 or many images/files to hold them on the Notch
///   as crisp `52×52` rounded Finder/Studio thumbnails with native drag-out (`.draggable`), Quick Look / click
///   to open, and pairing with the borderless prompt composer right underneath.
public struct NotchDropComposerView: View {
    public var store: AntigravityTelemetryStore
    public var trayStore: NotchTrayStore
    @Binding public var isInputFocused: Bool
    public var onShowToast: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var promptFieldFocused: Bool
    @Namespace private var targetSwitchNamespace

    @State private var hoveredItemID: String?
    @State private var hoveredQueueID: String?
    @State private var isShelfDropTargeted: Bool = false
    @State private var isAccessibilityTrusted: Bool = false
    @State private var sendLaunchImpulse: Bool = false
    @State private var captureShutterFlash: Bool = false
    @State private var pasteKeyMonitor: Any?
    @State private var accessibilityPollTask: Task<Void, Never>?

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

    private var activeSessionShortTitle: String {
        guard let raw = store.activeSession?.title, !raw.isEmpty else {
            return "Active Chat"
        }
        let cleaned = raw
            .replacingOccurrences(of: "<USER_REQUEST>", with: "")
            .replacingOccurrences(of: "</USER_REQUEST>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "Active Chat" }
        return cleaned.count > 24 ? String(cleaned.prefix(23)) + "…" : cleaned
    }

    private var isNativeDragCatching: Bool {
        trayStore.isGlobalDragActive || trayStore.isGlobalDragNearNotch
    }

    private var shelfHeight: CGFloat {
        trayStore.queuedPrompts.isEmpty ? 104 : 88
    }

    public var body: some View {
        @Bindable var tray = trayStore

        VStack(alignment: .leading, spacing: 9) {
            // 1. Full-width boring.notch-inspired Drop Shelf Bay
            dropShelfBay
                .frame(maxWidth: .infinity, minHeight: shelfHeight, maxHeight: shelfHeight)
                .animation(reduceMotion ? nil : .spring(duration: 0.30, bounce: 0.16), value: shelfHeight)

            // 2. Seamless Borderless Obsidian Prompt Composer + Target Switcher
            seamlessPromptSection(draftBinding: $tray.draftPrompt)

            // 3. Compact Horizontal Queue Rail (only when prompts are queued)
            if !trayStore.queuedPrompts.isEmpty {
                horizontalQueueRail
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            if captureShutterFlash {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.0)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.14), value: trayStore.queuedPrompts.isEmpty)
        .onChange(of: trayStore.lastCapturePulseToken) { _, _ in
            triggerCaptureShutterPulse()
            activateNotchPanelForTyping()
        }
        .onChange(of: promptFieldFocused) { _, focused in
            isInputFocused = focused
        }
        .onAppear {
            isAccessibilityTrusted = trayStore.isAccessibilityTrustedForAutoSend
            startAccessibilityPollingIfNeeded()
            installImagePasteMonitor()
            if !trayStore.isGlobalDragNearNotch {
                activateNotchPanelForTyping()
            }
        }
        .onDisappear {
            accessibilityPollTask?.cancel()
            accessibilityPollTask = nil
            removeImagePasteMonitor()
            isInputFocused = false
            trayStore.isDropTargeted = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityTrusted = trayStore.isAccessibilityTrustedForAutoSend
        }
    }

    // MARK: - boring.notch ShelfView-Inspired Expansive Drop Shelf

    private var dropShelfBay: some View {
        let targeted = isShelfDropTargeted || trayStore.isDropTargeted
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(targeted ? 0.065 : 0.024))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            targeted
                                ? Color.white.opacity(0.72)
                                : Color.white.opacity(trayStore.isGlobalDragNearNotch ? 0.24 : 0.11),
                            style: StrokeStyle(
                                lineWidth: targeted ? 2.0 : 1.15,
                                lineCap: .round,
                                dash: [8, 6]
                            )
                        )
                )

            if trayStore.stagedItems.isEmpty {
                // Clean boring.notch empty drop bay with live magnetic spring cue (click to browse files)
                VStack(spacing: 6) {
                    Image(systemName: targeted ? "arrow.down.circle.fill" : "tray.and.arrow.down.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            targeted ? Color.white : Color.white.opacity(0.78),
                            Color.white.opacity(0.32)
                        )
                        .scaleEffect(!reduceMotion && targeted ? 1.14 : 1.0)
                        .offset(y: !reduceMotion && targeted ? -2 : 0)

                    Text(targeted ? releaseHeadline : "Drop images or files here")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(targeted ? 0.96 : 0.66))

                    Text("Click to browse · drag out anytime · ⌘V paste")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.30))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    browseLocalFiles()
                }
            } else {
                // boring.notch ShelfItemView-inspired horizontal thumbnail strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(trayStore.stagedItems) { item in
                            shelfItemTile(item)
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.78)).combined(with: .offset(y: -6)),
                                            removal: .opacity.combined(with: .scale(scale: 0.82))
                                        )
                                )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.30, bounce: 0.18), value: trayStore.stagedItems.map(\.id))
            }

            // Native AppKit drop catcher covering the entire right shelf bay during active macOS drags
            NotchNativeDropBridgeView(
                isCatchingActive: isNativeDragCatching,
                onTargetedChanged: { isOver in
                    isShelfDropTargeted = isOver
                    trayStore.isDropTargeted = isOver
                    if isOver {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                },
                onDropPasteboard: { pb in
                    let added = trayStore.stageFromPasteboard(pb, allowPlainText: true)
                    if added > 0 {
                        completeShelfStage(count: added)
                    }
                    return added
                },
                onPromisedURLs: { urls in
                    let added = trayStore.stageFileURLs(urls)
                    if added > 0 {
                        completeShelfStage(count: added)
                    }
                }
            )
        }
        .scaleEffect(!reduceMotion && targeted ? 1.012 : 1.0)
        .onDrop(of: [.fileURL, .url, .image, .png, .tiff, .utf8PlainText, .plainText, .data], isTargeted: $isShelfDropTargeted) { providers in
            trayStore.handleDrop(providers: providers) {
                completeShelfStage(count: 1)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.76), value: targeted)
    }

    private var releaseHeadline: String {
        if trayStore.globalDragHasImage {
            return trayStore.globalDragItemCount > 1
                ? "Release to stage \(trayStore.globalDragItemCount) images"
                : "Release to stage image"
        }
        return trayStore.globalDragItemCount > 1
            ? "Release to stage \(trayStore.globalDragItemCount) files"
            : "Release to stage file"
    }

    /// Clean `boring.notch` `ShelfItemView`-inspired rounded tile (`50×50` thumbnail + centered filename + native drag-out).
    private func shelfItemTile(_ item: StagedDropItem) -> some View {
        let isHovered = hoveredItemID == item.id
        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .center, spacing: 4) {
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
                .frame(width: 52, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(isHovered ? 0.34 : 0.12), lineWidth: 0.6)
                )
                .shadow(color: Color.black.opacity(0.35), radius: isHovered ? 6 : 3, y: 2)

                Text(item.name)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isHovered ? 0.96 : 0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 68)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.085 : 0.0))
            )
            .scaleEffect(!reduceMotion && isHovered ? 1.04 : 1.0)
            .offset(y: !reduceMotion && isHovered ? -1.5 : 0)
            .draggable(item.url)
            .onTapGesture {
                NSWorkspace.shared.open(item.url)
            }

            if isHovered {
                Button {
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.14)) {
                        trayStore.removeStagedItem(id: item.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(width: 15, height: 15)
                        .background(
                            Circle()
                                .fill(Color(red: 0.12, green: 0.13, blue: 0.15))
                                .overlay(
                                    Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6)
                                )
                        )
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
                .transition(.scale(scale: 0.65).combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.18)) {
                hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            }
        }
        .help("\(item.name) — Drag out to any app or click to open")
    }

    // MARK: - 2. Seamless Borderless Obsidian Prompt Composer

    private func seamlessPromptSection(draftBinding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                // Active Session vs New Chat sliding pill
                HStack(spacing: 2) {
                    targetChip(target: .activeSession, label: "Active", showLiveDot: true)
                    targetChip(target: .newChat, label: "New", showLiveDot: false)
                }
                .padding(2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.045))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.075), lineWidth: 0.5)
                        )
                )

                Text(trayStore.sendTarget == .activeSession ? activeSessionShortTitle : "New thread")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if trayStore.sendTarget == .activeSession && !isAccessibilityTrusted {
                    Button {
                        trayStore.requestAccessibilityPermission()
                        onShowToast("Allow Grav in Accessibility for 1-click auto-send")
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(GravPalette.fileEdit)
                                .frame(width: 4.5, height: 4.5)
                            Text("Auto-Send")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.68))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Grant macOS Accessibility once so Grav pastes & submits straight into your active Antigravity session")
                }

                if trayStore.hasComposableContent {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.10)) {
                            trayStore.draftPrompt = ""
                            trayStore.clearStagedItems()
                        }
                    } label: {
                        Text("Clear")
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.36))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    composerPlaceholder,
                    text: draftBinding,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1...2)
                .focused($promptFieldFocused)
                .padding(.vertical, 3)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.command) {
                        sendToAntigravityChat()
                    } else {
                        queueCurrentDraft()
                    }
                }

                HStack(spacing: 5) {
                    // Queue button (↵)
                    Button {
                        queueCurrentDraft()
                    } label: {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(trayStore.hasComposableContent ? 0.74 : 0.24))
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(trayStore.hasComposableContent ? 0.07 : 0.025))
                                    .overlay(
                                        Circle().strokeBorder(
                                            Color.white.opacity(trayStore.hasComposableContent ? 0.12 : 0.05),
                                            lineWidth: 0.5
                                        )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!trayStore.hasComposableContent)
                    .help("Queue for next turn (↵)")

                    // Kinetic Send Orb (⌘↵)
                    Button {
                        sendToAntigravityChat()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    trayStore.hasComposableContent
                                        ? Color.white.opacity(0.96)
                                        : Color.white.opacity(0.055)
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            trayStore.hasComposableContent ? Color.clear : Color.white.opacity(0.10),
                                            lineWidth: 0.5
                                        )
                                )

                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(
                                    trayStore.hasComposableContent
                                        ? Color.black.opacity(0.94)
                                        : Color.white.opacity(0.24)
                                )
                                .offset(y: sendLaunchImpulse ? -13 : 0)
                                .opacity(sendLaunchImpulse ? 0 : 1)
                        }
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                        .scaleEffect(!reduceMotion && trayStore.hasComposableContent ? 1.0 : 0.94)
                    }
                    .buttonStyle(.plain)
                    .disabled(!trayStore.hasComposableContent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .help(
                        trayStore.sendTarget == .activeSession
                            ? "Send straight to \(activeSessionShortTitle) (⌘↵)"
                            : "Open New Chat with prompt (⌘↵)"
                    )
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.20), value: trayStore.hasComposableContent)
            }

            // Center-expanding optical hairline directly beneath the typing baseline
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 0.5)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.32), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 0.85)
                    .scaleEffect(x: promptFieldFocused ? 1.0 : 0.001, y: 1.0, anchor: .center)
                    .opacity(promptFieldFocused ? 1.0 : 0.0)
                    .animation(reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.08), value: promptFieldFocused)
            }
        }
    }

    private func targetChip(target: AntigravitySendTarget, label: String, showLiveDot: Bool) -> some View {
        let selected = trayStore.sendTarget == target
        return Button {
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.16)) {
                trayStore.sendTarget = target
            }
        } label: {
            HStack(spacing: 3.5) {
                if showLiveDot {
                    Circle()
                        .fill(selected ? GravPalette.emerald : Color.white.opacity(0.28))
                        .frame(width: 4, height: 4)
                }
                Text(label)
                    .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white.opacity(0.95) : Color.white.opacity(0.45))
            }
            .padding(.horizontal, 7.5)
            .padding(.vertical, 2.5)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.13))
                        .matchedGeometryEffect(id: "composerTargetPill", in: targetSwitchNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var composerPlaceholder: String {
        let imageCount = trayStore.stagedItems.filter(\.isImage).count
        let fileCount = trayStore.stagedItems.count
        if imageCount > 0 {
            return imageCount == 1
                ? "Ask Antigravity about this image… (⌘↵ send)"
                : "Ask Antigravity about these \(imageCount) images… (⌘↵ send)"
        }
        if fileCount > 0 {
            return "Write instruction for \(fileCount) file\(fileCount == 1 ? "" : "s")… (⌘↵ send)"
        }
        let cleanTitle = activeSessionShortTitle.trimmingCharacters(in: CharacterSet(charactersIn: ".… "))
        return trayStore.sendTarget == .activeSession
            ? "Message \(cleanTitle)… (↵ queue · ⌘↵ send)"
            : "Start a new conversation… (↵ queue · ⌘↵ send)"
    }

    // MARK: - 3. Compact Horizontal Queue Rail

    private var horizontalQueueRail: some View {
        HStack(spacing: 6) {
            Text("UP NEXT")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.32))
                .fixedSize()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(trayStore.queuedPrompts.enumerated()), id: \.element.id) { index, item in
                        queuedChip(item, index: index)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.88)).combined(with: .offset(x: 10)),
                                        removal: .opacity.combined(with: .scale(scale: 0.86))
                                    )
                            )
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.14), value: trayStore.queuedPrompts.map(\.id))
    }

    private func queuedChip(_ item: QueuedPromptItem, index: Int) -> some View {
        let isHovered = hoveredQueueID == item.id
        return HStack(spacing: 5) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.38))

            Text(item.text)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color.white.opacity(isHovered ? 0.96 : 0.74))
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)

            if !item.attachedPaths.isEmpty {
                Image(systemName: "photo")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            if isHovered {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                        trayStore.removeQueuedPrompt(id: item.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.46))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.11 : 0.048))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(isHovered ? 0.20 : 0.075), lineWidth: 0.5)
                )
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            sendQueuedPrompt(item)
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                hoveredQueueID = hovering ? item.id : (hoveredQueueID == item.id ? nil : hoveredQueueID)
            }
        }
        .help("Click to send queued prompt to Antigravity")
    }

    // MARK: - Actions & Micro-Animations

    private func completeShelfStage(count: Int) {
        trayStore.isGlobalDragActive = false
        trayStore.isGlobalDragNearNotch = false
        trayStore.isDropTargeted = false
        isShelfDropTargeted = false
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        onShowToast(count == 1 ? "Staged on Notch Shelf" : "Staged \(count) items on Shelf")
        activateNotchPanelForTyping()
    }

    private func triggerCaptureShutterPulse() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.10)) {
            captureShutterFlash = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(190))
            withAnimation(.easeOut(duration: 0.18)) {
                captureShutterFlash = false
            }
        }
    }

    private func triggerSendLaunchImpulse() {
        guard !reduceMotion else { return }
        withAnimation(.spring(duration: 0.20, bounce: 0.10)) {
            sendLaunchImpulse = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            sendLaunchImpulse = false
        }
    }

    private func queueCurrentDraft() {
        guard trayStore.enqueueCurrentDraft() != nil else { return }
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        onShowToast("Queued for next turn")
    }

    private func sendToAntigravityChat() {
        let currentTarget = trayStore.sendTarget
        guard let result = trayStore.sendCurrentBundleToAntigravity(
            target: currentTarget,
            activateApp: { store.activateAntigravityApp() }
        ) else { return }

        triggerSendLaunchImpulse()
        promptFieldFocused = false
        isInputFocused = false
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        handleDispatchToast(result)
    }

    private func sendQueuedPrompt(_ item: QueuedPromptItem) {
        let currentTarget = trayStore.sendTarget
        guard let result = trayStore.sendQueuedPromptToAntigravity(
            id: item.id,
            target: currentTarget,
            activateApp: { store.activateAntigravityApp() }
        ) else { return }

        promptFieldFocused = false
        isInputFocused = false
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        handleDispatchToast(result)
    }

    private func handleDispatchToast(_ result: AntigravityPromptDispatchResult) {
        switch result {
        case .sentToActiveSession:
            onShowToast("Sent to \(activeSessionShortTitle)")
        case .copiedToActiveSessionNeedsAccessibility:
            isAccessibilityTrusted = false
            trayStore.requestAccessibilityPermission(openSystemSettings: true)
            startAccessibilityPollingIfNeeded()
            onShowToast("Bật Grav trong Accessibility để gửi thẳng vào chat")
        case .openedNewChatDeepLink:
            onShowToast("Opened in new Antigravity chat")
        case .copiedToClipboardFallback:
            onShowToast("Copied · Press ⌘V in Antigravity")
        }
    }

    private func startAccessibilityPollingIfNeeded() {
        accessibilityPollTask?.cancel()
        guard !trayStore.isAccessibilityTrustedForAutoSend else {
            isAccessibilityTrusted = true
            return
        }
        accessibilityPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                if trayStore.isAccessibilityTrustedForAutoSend {
                    isAccessibilityTrusted = true
                    onShowToast("Active-chat auto-send ready")
                    break
                }
            }
        }
    }

    private func browseLocalFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.title = "Attach images or files to Grav Notch"
        panel.prompt = "Stage"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            let added = trayStore.stageFileURLs(panel.urls)
            if added > 0 {
                onShowToast("Staged \(added) item\(added == 1 ? "" : "s")")
            }
            activateNotchPanelForTyping()
        }
    }

    private func installImagePasteMonitor() {
        removeImagePasteMonitor()
        pasteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [trayStore, onShowToast] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" else {
                return event
            }
            let pb = NSPasteboard.general
            let hasPlainText = (pb.string(forType: .string)?.isEmpty == false)
            let hasFileOrImage = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
                || pb.data(forType: .png) != nil
                || pb.data(forType: .tiff) != nil
                || pb.data(forType: NSPasteboard.PasteboardType("public.image")) != nil
            guard hasFileOrImage && !hasPlainText else {
                return event
            }
            Task { @MainActor in
                let added = trayStore.stageFromPasteboard(pb, allowPlainText: false)
                if added > 0 {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    onShowToast(added == 1 ? "Image pasted to Notch" : "\(added) items pasted to Notch")
                }
            }
            return nil
        }
    }

    private func removeImagePasteMonitor() {
        if let pasteKeyMonitor {
            NSEvent.removeMonitor(pasteKeyMonitor)
            self.pasteKeyMonitor = nil
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
