import AppKit
import Carbon.HIToolbox

struct FlowHotkey: Equatable {
    var keyCode: UInt32
    var code: String
    var modifiers: [String]

    static let `default` = FlowHotkey(keyCode: 49, code: "Space", modifiers: ["Option"])

    var display: String {
        (modifiers + [code]).joined(separator: " + ")
    }

    var carbonModifiers: UInt32 {
        var out: UInt32 = 0
        for modifier in modifiers {
            switch modifier {
            case "Control": out |= UInt32(controlKey)
            case "Option": out |= UInt32(optionKey)
            case "Shift": out |= UInt32(shiftKey)
            case "Command": out |= UInt32(cmdKey)
            default: break
            }
        }
        return out
    }

    static func load() -> FlowHotkey {
        let defaults = UserDefaults.standard
        let keyCode = UInt32(defaults.integer(forKey: "flowHotkeyKeyCode"))
        let code = defaults.string(forKey: "flowHotkeyCode") ?? FlowHotkey.default.code
        let modifiers = defaults.stringArray(forKey: "flowHotkeyModifiers") ?? FlowHotkey.default.modifiers
        guard keyCode > 0 || code == "A" else { return .default }
        return FlowHotkey(keyCode: keyCode == 0 ? FlowHotkey.default.keyCode : keyCode, code: code, modifiers: modifiers)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: "flowHotkeyKeyCode")
        defaults.set(code, forKey: "flowHotkeyCode")
        defaults.set(modifiers, forKey: "flowHotkeyModifiers")
        defaults.set(display, forKey: "flowHotkey")
    }

    static func from(event: NSEvent) -> FlowHotkey? {
        var modifiers: [String] = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { modifiers.append("Control") }
        if flags.contains(.option) { modifiers.append("Option") }
        if flags.contains(.shift) { modifiers.append("Shift") }
        if flags.contains(.command) { modifiers.append("Command") }

        let keyCode = UInt32(event.keyCode)
        guard !modifierOnlyKeyCodes.contains(keyCode) else { return nil }
        let code = displayName(for: keyCode, characters: event.charactersIgnoringModifiers)
        return FlowHotkey(keyCode: keyCode, code: code, modifiers: modifiers)
    }

    private static let modifierOnlyKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static func displayName(for keyCode: UInt32, characters: String?) -> String {
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            let text = characters?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "Key \(keyCode)" : text.uppercased()
        }
    }
}

@MainActor
final class FlowHotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var hotkey: FlowHotkey = .default
    private var active = false

    func activate(_ hotkey: FlowHotkey) throws {
        deactivate()
        self.hotkey = hotkey
        installCarbonHandlerIfNeeded()

        let hotkeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "macOS rechazó ese hotkey. Puede estar en uso por otra app."
            ])
        }

        installReleaseTap()
        active = true
    }

    func deactivate() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
        }
        hotkeyRef = nil

        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        eventTapSource = nil
        eventTap = nil
        active = false
    }

    func handleCarbonPress() {
        guard active else { return }
        onPress?()
    }

    func handleCGEvent(type: CGEventType, keyCode: UInt32) {
        guard active, type == .keyUp, keyCode == hotkey.keyCode else { return }
        onRelease?()
    }

    private func installCarbonHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            flowHotkeyCarbonHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    private func installReleaseTap() {
        let mask = (1 << CGEventType.keyUp.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: flowHotkeyEventTapHandler,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private static let signature: OSType = {
        let chars = Array("MFLW".utf8)
        return OSType(chars.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) })
    }()
}

private func flowHotkeyCarbonHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let rawPointer = UInt(bitPattern: userData)
    Task { @MainActor in
        guard let pointer = UnsafeMutableRawPointer(bitPattern: rawPointer) else { return }
        Unmanaged<FlowHotkeyManager>.fromOpaque(pointer).takeUnretainedValue().handleCarbonPress()
    }
    return noErr
}

private func flowHotkeyEventTapHandler(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
    let rawPointer = UInt(bitPattern: userInfo)
    let rawType = type.rawValue
    Task { @MainActor in
        guard let pointer = UnsafeMutableRawPointer(bitPattern: rawPointer),
              let eventType = CGEventType(rawValue: rawType) else { return }
        Unmanaged<FlowHotkeyManager>.fromOpaque(pointer).takeUnretainedValue().handleCGEvent(type: eventType, keyCode: keyCode)
    }
    return Unmanaged.passUnretained(event)
}
