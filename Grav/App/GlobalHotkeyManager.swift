import AppKit
import Carbon.HIToolbox
import Foundation

/// Serializable global keyboard shortcut backed by Carbon virtual key codes & modifiers.
public struct GravHotkeyShortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public static let defaultToggleNotch = GravHotkeyShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey)
    )

    public static let defaultToggleMiniPet = GravHotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_P),
        carbonModifiers: UInt32(optionKey | shiftKey)
    )

    public static let defaultFocusAntigravity = GravHotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_A),
        carbonModifiers: UInt32(optionKey | shiftKey)
    )

    /// Converts AppKit `NSEvent.ModifierFlags` to Carbon modifier flags.
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    /// Individual keycap labels suitable for `SettingsKeycapPlate`.
    public var displayKeys: [String] {
        var keys: [String] = []
        if (carbonModifiers & UInt32(controlKey)) != 0 { keys.append("⌃") }
        if (carbonModifiers & UInt32(optionKey)) != 0 { keys.append("⌥") }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { keys.append("⇧") }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { keys.append("⌘") }
        keys.append(Self.keyLabel(for: keyCode))
        return keys
    }

    public var displayString: String {
        displayKeys.joined()
    }

    public static func keyLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "Esc"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key\(keyCode)"
        }
    }
}

public enum GravHotkeyAction: UInt32, CaseIterable, Sendable {
    case toggleNotch = 1
    case toggleMiniPet = 2
    case focusAntigravity = 3
}

/// System-wide macOS Carbon `RegisterEventHotKey` coordinator (zero Accessibility permission required).
@MainActor
public final class GlobalHotkeyManager {
    public static let shared = GlobalHotkeyManager()

    private static let signature: OSType = 0x4752_4156 // 'GRAV'

    private var eventHandlerRef: EventHandlerRef?
    private var registeredRefs: [GravHotkeyAction: EventHotKeyRef] = [:]

    public var onToggleNotch: (() -> Void)?
    public var onToggleMiniPet: (() -> Void)?
    public var onFocusAntigravity: (() -> Void)?

    private init() {}

    public func install(preferences: PreferencesStore) {
        installEventHandlerIfNeeded()
        sync(with: preferences)
    }

    public func sync(with preferences: PreferencesStore) {
        unregisterAll()
        guard preferences.globalHotkeysEnabled else { return }

        if let s = preferences.hotkeyToggleNotch {
            register(action: .toggleNotch, shortcut: s)
        }
        if let s = preferences.hotkeyToggleMiniPet {
            register(action: .toggleMiniPet, shortcut: s)
        }
        if let s = preferences.hotkeyFocusAntigravity {
            register(action: .focusAntigravity, shortcut: s)
        }
    }

    public func uninstall() {
        unregisterAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    private func register(action: GravHotkeyAction, shortcut: GravHotkeyShortcut) {
        guard shortcut.carbonModifiers != 0 else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            registeredRefs[action] = ref
        }
    }

    private func unregisterAll() {
        for (_, ref) in registeredRefs {
            UnregisterEventHotKey(ref)
        }
        registeredRefs.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard err == noErr, hotKeyID.signature == GlobalHotkeyManager.signature,
                  let action = GravHotkeyAction(rawValue: hotKeyID.id)
            else {
                return noErr
            }
            Task { @MainActor in
                GlobalHotkeyManager.shared.dispatch(action)
            }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )
    }

    private func dispatch(_ action: GravHotkeyAction) {
        switch action {
        case .toggleNotch:
            onToggleNotch?()
        case .toggleMiniPet:
            onToggleMiniPet?()
        case .focusAntigravity:
            onFocusAntigravity?()
        }
    }
}
