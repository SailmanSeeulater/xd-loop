import AppKit
import Carbon.HIToolbox

// A system-wide shortcut that covers the screen from any app. Uses the classic Carbon hot key API,
// which works inside the app sandbox and needs no permissions
enum GlobalHotKey {
    // The shortcut we managed to get, e.g. "⌃⌥↓", or nil if both choices were taken
    private(set) static var label: String?
    private(set) static var modifiers: NSEvent.ModifierFlags = []
    private static var ref: EventHotKeyRef?
    private static var pressed: (() -> Void)?

    // Control + Option + ↓ by default. Rectangle uses that for "Bottom Half", so the menu can switch
    // to Control + Option + ⌘ + ↓ instead (saved as "hotkeyAddsCommand")
    static var addsCommand: Bool {
        get { UserDefaults.standard.bool(forKey: "hotkeyAddsCommand") }
        set {
            UserDefaults.standard.set(newValue, forKey: "hotkeyAddsCommand")
            registerKeys()
        }
    }

    static func register(onPress: @escaping () -> Void) {
        pressed = onPress
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { GlobalHotKey.pressed?() }
            return noErr
        }, 1, &spec, nil, nil)
        registerKeys()
    }

    // Tries the preferred shortcut first, then the other one if some app has already claimed it
    private static func registerKeys() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        label = nil

        var choices: [(UInt32, NSEvent.ModifierFlags, String)] = [
            (UInt32(controlKey | optionKey), [.control, .option], "⌃⌥↓"),
            (UInt32(controlKey | optionKey | cmdKey), [.control, .option, .command], "⌃⌥⌘↓"),
        ]
        if addsCommand { choices.reverse() }
        for (carbonModifiers, flags, name) in choices {
            var hotKey: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x78646C70), id: 1)   // "xdlp"
            let status = RegisterEventHotKey(UInt32(kVK_DownArrow), carbonModifiers, id, GetApplicationEventTarget(),
                                             OptionBits(kEventHotKeyExclusive), &hotKey)
            if status == noErr {
                ref = hotKey
                label = name
                modifiers = flags
                return
            }
        }
    }
}
