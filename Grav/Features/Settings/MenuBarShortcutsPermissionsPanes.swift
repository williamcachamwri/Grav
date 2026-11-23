import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Menu Bar Settings Pane

/// Native grouped-form Menu Bar pane with a 1:1 authentic macOS menu bar & dropdown mockup
/// rendered over macOS's real Pro Black dark wallpaper, plus rich live Menu Bar customization controls.
struct MenuBarSettingsPane: View {
    @Bindable var preferences: PreferencesStore
    let store: AntigravityTelemetryStore
    var petsStore: CodexPetsStore = .shared

    var body: some View {
        SettingsPageCanvas(
            tab: .menuBar,
            subtitle: "Customize Grav's macOS status bar presence, Liquid Glass dropdown, and quick controls."
        ) {
            SettingsCardGroup(
                title: "Live 1:1 macOS Preview",
                badge: "LIQUID GLASS",
                staggerIndex: 0,
                contentPadding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
            ) {
                GravMenuBarPreviewCard(
                    preferences: preferences,
                    store: store,
                    petsStore: petsStore
                )
            }

            SettingsCardGroup(title: "Status Item", staggerIndex: 1) {
                SettingRow(
                    title: "Show Menu Bar Icon",
                    description: "Display Grav's orbital telemetry icon and quick controls in the macOS menu bar."
                ) {
                    Toggle("", isOn: $preferences.showMenuBarIcon)
                        .labelsHidden()
                }
            }

            SettingsCardGroup(title: "Menu Content", staggerIndex: 2) {
                SettingRow(
                    title: "Show Mini Pet in Header",
                    description: "Display your equipped Codex Mini Pet inside the top status header of the menu bar dropdown."
                ) {
                    Toggle("", isOn: $preferences.menuBarShowPetInHeader)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Show Token & Context Metrics",
                    description: "Include live session token totals and context window percentage beneath the status headline."
                ) {
                    Toggle("", isOn: $preferences.menuBarShowLiveMetrics)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Show Quick HUD Toggles",
                    description: "Keep Pin Notch, Hover to Expand, Auto-Peek, and Sound toggles one click away in the dropdown."
                ) {
                    Toggle("", isOn: $preferences.menuBarShowQuickToggles)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Show Mini Pet Submenu",
                    description: "Add quick controls to switch pets, snap desktop position, wave/jump, or tuck away your pet."
                ) {
                    Toggle("", isOn: $preferences.menuBarShowMiniPetSubmenu)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Show Active Sessions Submenu",
                    description: "Switch discovered Antigravity conversations or reveal transcripts directly from the menu bar."
                ) {
                    Toggle("", isOn: $preferences.menuBarShowSessionsSubmenu)
                        .labelsHidden()
                }
            }
            .disabled(!preferences.showMenuBarIcon)
            .opacity(preferences.showMenuBarIcon ? 1.0 : 0.45)
        }
    }
}

/// 1:1 pixel-faithful macOS menu bar & frosted-glass dropdown mockup over macOS's real dark wallpaper.
private struct GravMenuBarPreviewCard: View {
    let preferences: PreferencesStore
    let store: AntigravityTelemetryStore
    let petsStore: CodexPetsStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredRow: String?

    private var isPaused: Bool {
        store.isPaused || preferences.isTelemetryPaused
    }

    private var activePet: InstalledCodexPet? {
        guard preferences.miniPetEnabled && preferences.menuBarShowPetInHeader else { return nil }
        return petsStore.pet(withID: preferences.activeMiniPetID)
    }

    private var cleanSessionSubtitle: String {
        var parts: [String] = []
        if let raw = store.activeSession?.title, !raw.isEmpty {
            let clean = raw
                .replacingOccurrences(of: "<USER_REQUEST>", with: "")
                .replacingOccurrences(of: "</USER_REQUEST>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { parts.append(clean) }
        } else {
            parts.append("Connected to Antigravity")
        }
        if preferences.menuBarShowLiveMetrics {
            if store.tokenMetrics.totalTokens > 0 {
                parts.append("\(TokenMetrics.formatCompact(store.tokenMetrics.totalTokens)) tok")
            }
            if store.tokenMetrics.latestContextTokens > 0 {
                let pct = Int((store.tokenMetrics.contextFillRatio * 100.0).rounded())
                parts.append("\(pct)% ctx")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var formattedClock: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm EEE d MMM"
        return formatter.string(from: Date())
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Authentic Apple Pro Black macOS dark desktop wallpaper (same engine as Onboarding!)
            GravMockWallpaper(app: .settings).equatable()

            VStack(alignment: .trailing, spacing: 6) {
                // 1:1 Authentic macOS Tahoe Liquid Glass Menu Bar Strip
                HStack(spacing: 11) {
                    Spacer(minLength: 0)

                    if preferences.showMenuBarIcon {
                        GravOrbitalMark(size: 13.5, tint: .white)
                            .frame(width: 30, height: 20)
                            .liquidGlassSurface(
                                shape: Capsule(style: .continuous),
                                substrate: 0.16,
                                tint: 0.22,
                                highlight: .custom(top: 0.36, bottom: 0.10),
                                layer: .control,
                                isInteractive: true,
                                nativeGlassTint: Color.white.opacity(0.16),
                                nativeHighlight: .custom(top: 0.34, bottom: 0.10),
                                nativeVariant: .clear
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }

                    Image(systemName: "switch.2")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.90))

                    Image(systemName: "wifi")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.90))

                    Image(systemName: "battery.100percent")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.90))

                    Text(formattedClock)
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.95))
                }
                .padding(.horizontal, 12)
                .frame(height: 27)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.18))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 0.5)
                }

                // 1:1 Authentic macOS Tahoe Liquid Glass Status Menu Dropdown
                if preferences.showMenuBarIcon {
                    VStack(alignment: .leading, spacing: 1) {
                        // Live Status Header (matches real MenuBarController header 1:1!)
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isPaused ? Color.secondary : (store.connectionStatus.isAppRunning ? GravPalette.emerald : GravPalette.fileEdit))
                                .frame(width: 6, height: 6)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(isPaused ? "Telemetry Paused" : (store.state.isActive ? store.state.label : "Antigravity Idle"))
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.96))
                                    .lineLimit(1)

                                Text(cleanSessionSubtitle)
                                    .font(.system(size: 9.8))
                                    .foregroundStyle(.white.opacity(0.58))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            if let pet = activePet {
                                CodexPetSpriteView(
                                    pet: pet,
                                    state: .idle,
                                    size: 22,
                                    speed: preferences.miniPetSpeed,
                                    reduceMotion: reduceMotion,
                                    petsStore: petsStore
                                )
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)

                        menuDivider

                        previewRow(id: "toggle", title: "Toggle Notch HUD", checkmark: false, hasSubmenu: false, shortcut: nil)

                        if preferences.menuBarShowQuickToggles {
                            previewRow(id: "pin", title: "Pin Notch Open", checkmark: preferences.isNotchPinned, hasSubmenu: false, shortcut: nil)
                            previewRow(id: "hover", title: "Hover to Expand", checkmark: preferences.hoverToExpand, hasSubmenu: false, shortcut: nil)
                            previewRow(id: "peek", title: "Auto-Peek on Events", checkmark: preferences.autoPeekOnEvents, hasSubmenu: false, shortcut: nil)
                            previewRow(id: "sound", title: "Play Sounds", checkmark: preferences.playSounds, hasSubmenu: false, shortcut: nil)
                        }

                        previewRow(
                            id: "pause",
                            title: isPaused ? "Resume Telemetry" : "Pause Telemetry",
                            checkmark: false,
                            hasSubmenu: false,
                            shortcut: nil
                        )

                        if preferences.menuBarShowMiniPetSubmenu || preferences.menuBarShowSessionsSubmenu {
                            menuDivider
                            if preferences.menuBarShowMiniPetSubmenu {
                                previewRow(id: "pet", title: "Mini Pet", checkmark: false, hasSubmenu: true, shortcut: nil)
                            }
                            if preferences.menuBarShowSessionsSubmenu {
                                previewRow(id: "session", title: "Active Session", checkmark: false, hasSubmenu: true, shortcut: nil)
                            }
                        }

                        menuDivider
                        previewRow(id: "prefs", title: "Preferences…", checkmark: false, hasSubmenu: false, shortcut: "⌘,")
                        previewRow(id: "quit", title: "Quit Grav", checkmark: false, hasSubmenu: false, shortcut: "⌘Q")
                    }
                    .padding(6)
                    .frame(width: 242)
                    .liquidGlassSurface(
                        shape: RoundedRectangle(cornerRadius: 15, style: .continuous),
                        substrate: 0.26,
                        tint: 0.14,
                        highlight: .custom(top: 0.34, bottom: 0.10),
                        layer: .control,
                        withRimLighting: true,
                        isInteractive: false,
                        nativeGlassTint: Color(white: 0.08).opacity(0.32),
                        nativeHighlight: .custom(top: 0.30, bottom: 0.08),
                        nativeVariant: .clear
                    )
                    .shadow(color: .black.opacity(0.42), radius: 24, y: 12)
                    .padding(.trailing, 84)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    HStack {
                        Spacer()
                        Text("Menu bar icon hidden — Grav remains accessible via the Notch HUD.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.68))
                        Spacer()
                    }
                    .padding(.top, 96)
                }

                Spacer(minLength: 0)
            }
        }
        .environment(\.colorScheme, .dark)
        .frame(height: 326)
        .clipShape(Radius.rect(Radius.card))
        .overlay(
            Radius.rect(Radius.card)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6)
        )
        .animation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.12), value: preferences.showMenuBarIcon)
        .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.10), value: preferences.menuBarShowQuickToggles)
        .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.10), value: preferences.menuBarShowMiniPetSubmenu)
        .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.10), value: preferences.menuBarShowSessionsSubmenu)
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
    }

    private func previewRow(
        id: String,
        title: String,
        checkmark: Bool,
        hasSubmenu: Bool,
        shortcut: String?
    ) -> some View {
        let isHovered = hoveredRow == id
        return HStack(spacing: 5) {
            Group {
                if checkmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                } else {
                    Color.clear
                }
            }
            .frame(width: 12, height: 12)

            Text(title)
                .font(.system(size: 11.5, weight: .regular))
                .lineLimit(1)

            Spacer(minLength: 8)

            if hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isHovered ? .white.opacity(0.92) : .white.opacity(0.55))
            } else if let shortcut {
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundStyle(isHovered ? .white.opacity(0.88) : .white.opacity(0.45))
            }
        }
        .foregroundStyle(isHovered ? .white : .white.opacity(0.90))
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredRow = id
            } else if hoveredRow == id {
                hoveredRow = nil
            }
        }
    }
}

// MARK: - Shortcuts Settings Pane

/// Precision macOS Craft Shortcuts pane with live system-wide Global Hotkey recorders (Carbon)
/// plus Notch HUD and Settings Window shortcut reference tables.
struct ShortcutsSettingsPane: View {
    @Bindable var preferences: PreferencesStore

    var body: some View {
        SettingsPageCanvas(
            tab: .shortcuts,
            subtitle: "System-wide Carbon hotkeys, Notch HUD navigation, and Settings shortcuts.",
            trailing: {
                SettingsActionPill(title: "Reset Defaults", systemImage: "arrow.counterclockwise") {
                    preferences.resetGlobalHotkeysToDefaults()
                }
                .disabled(!preferences.globalHotkeysEnabled)
                .opacity(preferences.globalHotkeysEnabled ? 1 : 0.45)
            }
        ) {
            SettingsCardGroup(title: "Global Hotkeys", badge: "SYSTEM-WIDE", staggerIndex: 0) {
                SettingRow(
                    title: "Enable Global Hotkeys",
                    description: "Trigger Grav actions from any app on macOS without requiring Accessibility permission."
                ) {
                    Toggle("", isOn: $preferences.globalHotkeysEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Toggle Notch HUD",
                    description: "Expand or collapse the Notch HUD from anywhere on macOS."
                ) {
                    HotkeyRecorderControl(shortcut: $preferences.hotkeyToggleNotch)
                }
                .disabled(!preferences.globalHotkeysEnabled)
                .opacity(preferences.globalHotkeysEnabled ? 1 : 0.45)

                SettingsRowDivider()

                SettingRow(
                    title: "Toggle Desktop Mini Pet",
                    description: "Show or tuck away your floating desktop Codex Mini Pet."
                ) {
                    HotkeyRecorderControl(shortcut: $preferences.hotkeyToggleMiniPet)
                }
                .disabled(!preferences.globalHotkeysEnabled)
                .opacity(preferences.globalHotkeysEnabled ? 1 : 0.45)

                SettingsRowDivider()

                SettingRow(
                    title: "Focus Antigravity",
                    description: "Bring Google Antigravity straight to the front from any Space."
                ) {
                    HotkeyRecorderControl(shortcut: $preferences.hotkeyFocusAntigravity)
                }
                .disabled(!preferences.globalHotkeysEnabled)
                .opacity(preferences.globalHotkeysEnabled ? 1 : 0.45)
            }

            SettingsCardGroup(title: "Notch HUD", badge: "EXPANDED", staggerIndex: 1) {
                SettingRow(
                    title: "Switch Tabs (Live / Reply / Files / Terminal / Specs)",
                    description: "Jump straight to any inspector tab while the Notch HUD is focused."
                ) {
                    SettingsKeycapPlate(keys: ["1", "–", "5"])
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Switch Parallel Session",
                    description: "Cycle across active Antigravity agent sessions directly inside the Notch."
                ) {
                    HStack(spacing: 6) {
                        SettingsKeycapPlate(keys: ["⌘", "["])
                        SettingsKeycapPlate(keys: ["⌘", "]"])
                    }
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Spotlight Search History",
                    description: "Full-text FTS5 search across all Antigravity chats, prompts, and replies."
                ) {
                    SettingsKeycapPlate(keys: ["⌘", "K"])
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Copy Log or Diff",
                    description: "Copy the active command log or selected file diff to the clipboard."
                ) {
                    SettingsKeycapPlate(keys: ["⌘", "C"])
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Pin / Collapse Notch",
                    description: "Pin the Notch HUD open (`⌘P`) or dismiss it back to its compact pill (`Esc`)."
                ) {
                    HStack(spacing: 6) {
                        SettingsKeycapPlate(keys: ["⌘", "P"])
                        SettingsKeycapPlate(keys: ["Esc"])
                    }
                }
            }

            SettingsCardGroup(title: "Settings Window", staggerIndex: 2) {
                SettingRow(
                    title: "Search Settings",
                    description: "Focus the sidebar search field from anywhere inside Settings."
                ) {
                    SettingsKeycapPlate(keys: ["⌘", "F"])
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Navigate Back & Forward",
                    description: "Move through your Settings pane navigation history."
                ) {
                    HStack(spacing: 6) {
                        SettingsKeycapPlate(keys: ["⌘", "["])
                        SettingsKeycapPlate(keys: ["⌘", "]"])
                    }
                }
            }
        }
    }
}

/// Renders `GravKeycapChip` / `GravKeycapRow` with high contrast in both Light and Dark appearances.
private struct SettingsKeycapPlate: View {
    @Environment(\.colorScheme) private var colorScheme
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                GravKeycapChip(label: key, emphasis: true)
                    .background {
                        if colorScheme == .light {
                            Radius.rect(Radius.ornament)
                                .fill(Color(white: 0.16))
                        }
                    }
            }
        }
    }
}

// MARK: - Interactive Global Hotkey Recorder Control

private struct HotkeyRecorderControl: View {
    @Binding var shortcut: GravHotkeyShortcut?
    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                if isRecording {
                    Text("Press keys…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                                )
                        )
                } else if let shortcut {
                    SettingsKeycapPlate(keys: shortcut.displayKeys)
                } else {
                    Text("Record…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                                )
                        )
                }
            }
            .buttonStyle(.plain)

            if shortcut != nil && !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels recording
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let carbonMods = GravHotkeyShortcut.carbonModifiers(from: flags)
            guard carbonMods != 0 else {
                NSSound.beep()
                return nil
            }
            shortcut = GravHotkeyShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isRecording = false
    }
}

// MARK: - Permissions Settings Pane

/// Precision macOS Craft Permissions pane inspecting real brain directory readability and `SMAppService` status.
struct PermissionsSettingsPane: View {
    @Bindable var preferences: PreferencesStore
    let store: AntigravityTelemetryStore

    @Environment(\.preferencesHighlightedSetting) private var highlightedSetting
    @State private var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status
    @State private var hasAppeared = false

    private static let loginItemsSettingsURL =
        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

    var body: some View {
        let status = store.connectionStatus
        let brainReadable = status.isBrainAccessible && !status.needsFolderAccess

        SettingsPageCanvas(
            tab: .permissions,
            subtitle: "Grav reads local Antigravity transcripts directly on disk — zero cloud relays or Accessibility hooks.",
            trailing: {
                SettingsActionPill(title: "Refresh Status", systemImage: "arrow.clockwise") {
                    refreshPermissions()
                }
            }
        ) {
            SettingsCardGroup(
                title: "Access & Privacy",
                badge: brainReadable ? "ALL READY" : "ACTION NEEDED",
                staggerIndex: 0
            ) {
                permissionRow(
                    anchorTitle: "Antigravity Brain Directory",
                    icon: "folder.fill",
                    name: "Antigravity Brain Directory",
                    description: brainReadable
                        ? abbreviatedPath(status.brainDirectoryURL)
                        : "Required to read local Antigravity transcripts at ~/.gemini/antigravity/brain.",
                    statusLabel: brainReadable ? "Granted" : "Access Needed",
                    statusDotColor: brainReadable ? .green : .orange,
                    isRequired: true,
                    actionTitle: brainReadable ? "Reveal" : "Grant Access",
                    actionProminent: !brainReadable
                ) {
                    if brainReadable {
                        revealBrainFolder(status.brainDirectoryURL)
                    } else {
                        store.requestBrainFolderAccess()
                    }
                }

                SettingsRowDivider()

                permissionRow(
                    anchorTitle: "Launch at Login",
                    icon: "power.circle.fill",
                    name: "Launch at Login",
                    description: loginItemDescription,
                    statusLabel: loginItemStatusLabel,
                    statusDotColor: loginItemDotColor,
                    isRequired: false,
                    actionTitle: "Login Items",
                    actionProminent: false
                ) {
                    openLoginItemsSettings()
                }
            }

            SettingsCardGroup(title: "Security Posture", badge: "LOCAL-ONLY", staggerIndex: 1) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.055))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Zero Accessibility or Screen Recording permissions required")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Global hotkeys use Carbon RegisterEventHotKey, and telemetry streams purely from local Antigravity JSONL files via FSEvents.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .onAppear {
            hasAppeared = true
            refreshPermissions()
        }
        .onDisappear {
            hasAppeared = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard hasAppeared else { return }
            refreshPermissions()
        }
    }

    private func permissionRow(
        anchorTitle: String,
        icon: String,
        name: String,
        description: String,
        statusLabel: String,
        statusDotColor: Color,
        isRequired: Bool,
        actionTitle: String,
        actionProminent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color.primary.opacity(0.055))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                )

            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                    if isRequired {
                        Text("REQUIRED")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                }
                Text(description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)
                Text(statusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            SettingsActionPill(title: actionTitle, prominent: actionProminent, action: action)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .id(anchorTitle)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(highlightedSetting == anchorTitle ? 0.14 : 0))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .animation(.easeInOut(duration: 0.35), value: highlightedSetting == anchorTitle)
        }
    }

    // MARK: - Helpers

    private func refreshPermissions() {
        store.refreshConnectionStatus()
        preferences.refreshLaunchAtLoginStatus()
        loginItemStatus = SMAppService.mainApp.status
    }

    private var loginItemStatusLabel: String {
        switch loginItemStatus {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Needs Approval"
        case .notRegistered, .notFound: return "Not Enabled"
        @unknown default: return "Unknown"
        }
    }

    private var loginItemDotColor: Color {
        switch loginItemStatus {
        case .enabled: return .green
        case .requiresApproval: return .orange
        case .notRegistered, .notFound: return .secondary
        @unknown default: return .secondary
        }
    }

    private var loginItemDescription: String {
        switch loginItemStatus {
        case .enabled:
            return "Registered with macOS Service Management to start automatically at sign-in."
        case .requiresApproval:
            return "Approve Grav in System Settings → General → Login Items."
        case .notRegistered, .notFound:
            return "Optional. Enable Launch at Login in General settings to start with macOS."
        @unknown default:
            return "Managed via macOS Service Management (SMAppService)."
        }
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: Self.loginItemsSettingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func abbreviatedPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func revealBrainFolder(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parent = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) {
                NSWorkspace.shared.activateFileViewerSelecting([parent])
            } else {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
            }
        }
    }
}
