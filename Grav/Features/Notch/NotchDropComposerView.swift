import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let gravOpenNotchTray = Notification.Name("com.grav.openNotchTray")
}

// MARK: - Native AppKit NSDraggingDestination Catcher

/// Reliable AppKit `NSDraggingDestination` bridge that intercepts Finder files, macOS Screenshots,
/// Safari/Chrome/Figma dragged images, `NSFilePromiseReceiver` promises, and text drops across
/// the entire Notch surface — while passing 100% of clicks/typing/hover through when idle.
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

    /// Passes all normal mouse clicks, typing, scrolling, and hover straight through to SwiftUI
    /// whenever no macOS file/image drag is active.
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

        // First try synchronous local URLs / PNG / TIFF / NSImage / text
        if let count = onDropPasteboard?(pb), count > 0 {
            return true
        }

        // Fallback: NSFilePromiseReceiver (Photos.app, Safari dragged images, Mail)
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

// MARK: - Living Optical Drop Aperture (Monochrome Leica Viewfinder Physics)

/// Pure-monochrome 120fps optical viewfinder takeover shown when dragging an image/file
/// into the Notch capture bay. Zero dashed SaaS boxes, zero neon rainbow glow.
public struct OpticalDropApertureOverlay: View {
    public var isHovered: Bool
    public var hasImage: Bool
    public var itemCount: Int
    public var targetLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        ZStack {
            // Subtle optical vignette directly on the obsidian Notch surface
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.92))

            // 60/120fps monochrome viewfinder brackets & subtle harmonic refraction rings
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let phase = reduceMotion ? 0.0 : (t * 0.85).truncatingRemainder(dividingBy: 1.0)

                    // Two whisper-thin contracting concentric optical rings (pulls image IN)
                    for ringIndex in 0..<2 {
                        let p = (phase + Double(ringIndex) * 0.5).truncatingRemainder(dividingBy: 1.0)
                        let radius = CGFloat(1.0 - p) * (min(size.width, size.height) * 0.48) + 18
                        let alpha = sin(p * .pi) * (isHovered ? 0.16 : 0.08)
                        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        ctx.stroke(
                            Path(ellipseIn: rect),
                            with: .color(Color.white.opacity(alpha)),
                            lineWidth: isHovered ? 0.85 : 0.6
                        )
                    }

                    // Four precision camera viewfinder corner brackets that pull inward when hovered
                    let inset: CGFloat = isHovered ? 12 : 18
                    let arm: CGFloat = isHovered ? 16 : 12
                    let bracketColor = Color.white.opacity(isHovered ? 0.62 : 0.28)
                    let lw: CGFloat = isHovered ? 1.25 : 0.9

                    let corners: [(CGPoint, CGFloat, CGFloat)] = [
                        (CGPoint(x: inset, y: inset), 1, 1),
                        (CGPoint(x: size.width - inset, y: inset), -1, 1),
                        (CGPoint(x: inset, y: size.height - inset), 1, -1),
                        (CGPoint(x: size.width - inset, y: size.height - inset), -1, -1),
                    ]
                    for (pt, dx, dy) in corners {
                        var path = Path()
                        path.move(to: CGPoint(x: pt.x + dx * arm, y: pt.y))
                        path.addLine(to: pt)
                        path.addLine(to: CGPoint(x: pt.x, y: pt.y + dy * arm))
                        ctx.stroke(
                            path,
                            with: .color(bracketColor),
                            style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }

            // Minimal centered optical readout
            VStack(spacing: 6) {
                Image(systemName: hasImage ? "photo.on.rectangle.angled" : "arrow.down.doc")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color.white.opacity(isHovered ? 0.96 : 0.72))
                    .scaleEffect(!reduceMotion && isHovered ? 1.12 : 1.0)
                    .offset(y: !reduceMotion && isHovered ? -2 : 0)

                Text(isHovered ? releaseHeadline : approachHeadline)
                    .font(.system(size: 12.5, weight: .medium))
                    .tracking(-0.15)
                    .foregroundStyle(Color.white.opacity(isHovered ? 0.96 : 0.78))

                Text(targetLabel)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .lineLimit(1)
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.24), value: isHovered)
        }
        .allowsHitTesting(false)
    }

    private var releaseHeadline: String {
        if hasImage {
            return itemCount > 1 ? "Release to attach \(itemCount) images" : "Release to attach image"
        }
        return itemCount > 1 ? "Release to stage \(itemCount) files" : "Release to stage file"
    }

    private var approachHeadline: String {
        hasImage ? "Drop image onto Notch" : "Drop file onto Notch"
    }
}

// MARK: - Obsidian Studio Composer (Zero Boxes, Tactile Instrument Craft)

/// Flush, bespoke obsidian Notch Composer + Contact-Sheet Image Filmstrip + Horizontal Queue Rail.
///
/// Strict Anti-AI-Slop Industrial Craft:
/// - ZERO dashed upload boxes, ZERO grey bordered TextField rectangles, ZERO generic button toolbars.
/// - Seamless borderless typing directly on `#000000` with a center-expanding optical focus hairline.
/// - Active-session vs New-chat sliding capsule switcher (`matchedGeometryEffect`).
/// - Tactile studio Contact-Sheet filmstrip for dragged/pasted images (`⌘V` screenshot paste supported!).
/// - Kinetic launch orb (`↑` / `⌘↵`) with spring-launch physics and haptic feedback.
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
    @State private var isDropHovered: Bool = false
    @State private var isAccessibilityTrusted: Bool = false
    @State private var sendLaunchImpulse: Bool = false
    @State private var captureShutterFlash: Bool = false
    @State private var pasteKeyMonitor: Any?

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
        return cleaned.count > 26 ? String(cleaned.prefix(25)) + "…" : cleaned
    }

    private var isApertureVisible: Bool {
        trayStore.isGlobalDragNearNotch || trayStore.isDropTargeted || isDropHovered
    }

    public var body: some View {
        @Bindable var tray = trayStore

        ZStack {
            // Primary flush obsidian studio composer
            VStack(alignment: .leading, spacing: 9) {
                targetAndToolsRail

                if !trayStore.stagedItems.isEmpty {
                    contactSheetFilmstrip
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)).combined(with: .offset(y: -4)),
                                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                                )
                        )
                }

                seamlessWritingCanvas(draftBinding: $tray.draftPrompt)

                if !trayStore.queuedPrompts.isEmpty {
                    horizontalQueueRail
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .bottom))
                        )
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .opacity(isApertureVisible ? 0.14 : 1.0)
            .scaleEffect(!reduceMotion && isApertureVisible ? 0.982 : 1.0)
            .blur(radius: !reduceMotion && isApertureVisible ? 2.5 : 0)
            .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.14), value: isApertureVisible)
            .animation(reduceMotion ? nil : .spring(duration: 0.30, bounce: 0.16), value: trayStore.stagedItems.isEmpty)
            .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.14), value: trayStore.queuedPrompts.isEmpty)

            // Living Optical Drop Aperture Takeover (drag an image anywhere near the Notch!)
            if isApertureVisible {
                OpticalDropApertureOverlay(
                    isHovered: trayStore.isDropTargeted || isDropHovered,
                    hasImage: trayStore.globalDragHasImage || true,
                    itemCount: max(1, trayStore.globalDragItemCount),
                    targetLabel: trayStore.sendTarget == .activeSession
                        ? "Attaching to \(activeSessionShortTitle)"
                        : "Attaching to New Chat"
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.96))
                )
            }

            // Crisp 220ms monochrome optical shutter confirmation pulse on image capture
            if captureShutterFlash {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.0)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [.fileURL, .image, .plainText], isTargeted: $isDropHovered) { providers in
            handleSwiftUIDrop(providers)
        }
        .onChange(of: isDropHovered) { _, targeted in
            trayStore.isDropTargeted = targeted
            if targeted {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        .onChange(of: trayStore.lastCapturePulseToken) { _, _ in
            triggerCaptureShutterPulse()
            activateNotchPanelForTyping()
        }
        .onChange(of: promptFieldFocused) { _, focused in
            isInputFocused = focused
        }
        .onAppear {
            isAccessibilityTrusted = trayStore.isAccessibilityTrustedForAutoSend
            installImagePasteMonitor()
            if !trayStore.isGlobalDragNearNotch {
                activateNotchPanelForTyping()
            }
        }
        .onDisappear {
            removeImagePasteMonitor()
            isInputFocused = false
            trayStore.isDropTargeted = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityTrusted = trayStore.isAccessibilityTrustedForAutoSend
        }
    }

    // MARK: - 1. Whisper-Quiet Target Switcher & Utility Rail

    private var targetAndToolsRail: some View {
        HStack(spacing: 8) {
            // Sliding monochrome capsule switcher: Active Session vs New Chat
            HStack(spacing: 2) {
                targetChip(
                    target: .activeSession,
                    label: "Active",
                    showLiveDot: true
                )
                targetChip(
                    target: .newChat,
                    label: "New",
                    showLiveDot: false
                )
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

            // Live session context subtitle (only in Active mode)
            if trayStore.sendTarget == .activeSession {
                Text(activeSessionShortTitle)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity)
            } else {
                Text("Starts fresh thread")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.32))
                    .lineLimit(1)
                    .transition(.opacity)
            }

            Spacer(minLength: 6)

            // If Active mode & Accessibility not granted yet, show a single quiet 1-click grant chip
            if trayStore.sendTarget == .activeSession && !isAccessibilityTrusted {
                Button {
                    trayStore.requestAccessibilityPermission()
                    onShowToast("Allow Grav in Accessibility for 1-click send")
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(GravPalette.fileEdit)
                            .frame(width: 4.5, height: 4.5)
                        Text("Enable Auto-Send")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.66))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.055))
                    )
                }
                .buttonStyle(.plain)
                .help("Grant Accessibility once so Grav types & sends straight into your active Antigravity session")
            }

            if trayStore.hasComposableContent {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.10)) {
                        trayStore.draftPrompt = ""
                        trayStore.clearStagedItems()
                    }
                } label: {
                    Text("Clear")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.36))
                }
                .buttonStyle(.plain)
            }

            Button {
                browseLocalFiles()
            } label: {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.54))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Attach image or file (or drag onto Notch / ⌘V screenshot)")
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.14), value: trayStore.sendTarget)
    }

    private func targetChip(target: AntigravitySendTarget, label: String, showLiveDot: Bool) -> some View {
        let selected = trayStore.sendTarget == target
        return Button {
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            withAnimation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.16)) {
                trayStore.sendTarget = target
            }
        } label: {
            HStack(spacing: 4) {
                if showLiveDot {
                    Circle()
                        .fill(selected ? GravPalette.emerald : Color.white.opacity(0.28))
                        .frame(width: 4.5, height: 4.5)
                }
                Text(label)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white.opacity(0.95) : Color.white.opacity(0.45))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
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

    // MARK: - 2. Studio Contact-Sheet Image Filmstrip (Zero Empty Box!)

    private var contactSheetFilmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(trayStore.stagedItems.enumerated()), id: \.element.id) { index, item in
                    contactSheetFrame(for: item, index: index)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.72)).combined(with: .offset(y: -10)),
                                    removal: .opacity.combined(with: .scale(scale: 0.80))
                                )
                        )
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.22), value: trayStore.stagedItems.map(\.id))
    }

    private func contactSheetFrame(for item: StagedDropItem, index: Int) -> some View {
        let isHovered = hoveredItemID == item.id
        let organicTilt: Double = {
            if reduceMotion || isHovered { return 0 }
            let angles: [Double] = [-1.8, 1.3, -1.1, 1.6, -1.4, 1.0]
            return angles[index % angles.count]
        }()

        return ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if item.isImage, let img = trayStore.thumbnails[item.id] {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color.white.opacity(0.05)
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                        }
                    }
                }
                .frame(width: 62, height: 44)
                .clipped()

                // Whisper bottom scrim with filename only when hovered (keeps image 100% pure at rest!)
                if isHovered || !item.isImage {
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 18)

                    Text(item.name)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2.5)
                }
            }
            .frame(width: 62, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(isHovered ? 0.38 : 0.12),
                        lineWidth: isHovered ? 0.9 : 0.5
                    )
            )
            .shadow(
                color: Color.black.opacity(isHovered ? 0.55 : 0.26),
                radius: isHovered ? 8 : 3,
                y: isHovered ? 4 : 1.5
            )
            .rotationEffect(.degrees(organicTilt))
            .scaleEffect(!reduceMotion && isHovered ? 1.08 : 1.0)
            .offset(y: !reduceMotion && isHovered ? -3 : 0)
            .draggable(item.url)
            .onTapGesture {
                NSWorkspace.shared.open(item.url)
            }

            if isHovered {
                Button {
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.14)) {
                        trayStore.removeStagedItem(id: item.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(width: 15, height: 15)
                        .background(
                            Circle()
                                .fill(Color(red: 0.11, green: 0.12, blue: 0.14))
                                .overlay(
                                    Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6)
                                )
                        )
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.scale(scale: 0.65).combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.20)) {
                hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            }
        }
        .help("\(item.name) — Drag out or click to open")
    }

    // MARK: - 3. Seamless Borderless Typing Canvas + Kinetic Launch Orb

    private func seamlessWritingCanvas(draftBinding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    composerPlaceholder,
                    text: draftBinding,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1...4)
                .focused($promptFieldFocused)
                .padding(.vertical, 4)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.command) {
                        sendToAntigravityChat()
                    } else {
                        queueCurrentDraft()
                    }
                }

                // Inline kinetic controls flush with text baseline (zero chunky toolbar)
                HStack(spacing: 6) {
                    // Queue button (↵)
                    Button {
                        queueCurrentDraft()
                    } label: {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(trayStore.hasComposableContent ? 0.72 : 0.22))
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(trayStore.hasComposableContent ? 0.065 : 0.025))
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
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(
                                    trayStore.hasComposableContent
                                        ? Color.black.opacity(0.94)
                                        : Color.white.opacity(0.24)
                                )
                                .offset(y: sendLaunchImpulse ? -13 : 0)
                                .opacity(sendLaunchImpulse ? 0 : 1)
                        }
                        .frame(width: 28, height: 28)
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
                .animation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.22), value: trayStore.hasComposableContent)
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
                    .animation(reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.08), value: promptFieldFocused)
            }

            // Whisper keyboard legend (only when empty & no staged items — keeps surface calm)
            if !trayStore.hasComposableContent && trayStore.queuedPrompts.isEmpty {
                HStack(spacing: 10) {
                    Text("Drag any image to the Notch or paste ⌘V")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.28))

                    Spacer(minLength: 4)

                    Text("↵ Queue  ·  ⌘↵ Send")
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.24))
                }
            }
        }
    }

    private var composerPlaceholder: String {
        let imageCount = trayStore.stagedItems.filter(\.isImage).count
        let fileCount = trayStore.stagedItems.count
        if imageCount > 0 {
            return imageCount == 1
                ? "Ask Antigravity about this image…"
                : "Ask Antigravity about these \(imageCount) images…"
        }
        if fileCount > 0 {
            return "Describe what to do with \(fileCount) staged file\(fileCount == 1 ? "" : "s")…"
        }
        if store.state.isActive {
            return "Draft next instruction while Antigravity works…"
        }
        return trayStore.sendTarget == .activeSession
            ? "Message \(activeSessionShortTitle)…"
            : "Start a new Antigravity conversation…"
    }

    // MARK: - 4. Horizontal Tactile Queue Rail (Zero Clunky Vertical Table)

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
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(isHovered ? 0.96 : 0.74))
                .lineLimit(1)
                .frame(maxWidth: 168, alignment: .leading)

            if !item.attachedPaths.isEmpty {
                Image(systemName: "photo")
                    .font(.system(size: 8.5, weight: .medium))
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
        .padding(.vertical, 4.5)
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

    private func handleSwiftUIDrop(_ providers: [NSItemProvider]) -> Bool {
        trayStore.handleDrop(providers: providers) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            onShowToast("Attached to Notch")
            activateNotchPanelForTyping()
        }
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
            onShowToast("Focused active chat · Press ⌘V (or enable Auto-Send)")
        case .openedNewChatDeepLink:
            onShowToast("Opened in new Antigravity chat")
        case .copiedToClipboardFallback:
            onShowToast("Copied · Press ⌘V in Antigravity")
        }
    }

    private func browseLocalFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.title = "Attach images or files to Grav Notch"
        panel.prompt = "Attach"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            let added = trayStore.stageFileURLs(panel.urls)
            if added > 0 {
                onShowToast("Attached \(added) item\(added == 1 ? "" : "s")")
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
