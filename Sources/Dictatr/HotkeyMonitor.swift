import AppKit

// Tecla de dictado: modificadores que llegan por flagsChanged con keyCode propio.
// fn NO funciona en teclados externos (Logitech la procesa en firmware y nunca llega a macOS).
struct HotkeySpec {
    let keyCode: UInt16
    let flag: NSEvent.ModifierFlags
    let label: String

    static func from(_ name: String) -> HotkeySpec {
        // "code:NN" — keyCode arbitrario, para teclados que reportan códigos no estándar
        if name.hasPrefix("code:"), let code = UInt16(name.dropFirst(5)) {
            return HotkeySpec(keyCode: code, flag: flagFor(keyCode: code), label: "tecla \(code)")
        }
        switch name {
        case "right_command": return HotkeySpec(keyCode: 54, flag: .command, label: "⌘ derecha")
        case "right_option": return HotkeySpec(keyCode: 61, flag: .option, label: "⌥ derecha")
        case "right_shift": return HotkeySpec(keyCode: 60, flag: .shift, label: "⇧ derecha")
        case "right_control": return HotkeySpec(keyCode: 62, flag: .control, label: "⌃ derecha")
        default: return HotkeySpec(keyCode: 63, flag: .function, label: "fn")
        }
    }

    // Flag de modificador según keyCode (pares izquierda/derecha)
    static func flagFor(keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        default: return .function
        }
    }
}

// Push-to-talk sobre la tecla primaria, con acorde opcional: el modificador
// `chord` no hace nada por sí solo — solo modifica el gesto cuando acompaña
// a la primaria (⌘der = dictar, ⌘der+⇧der = reescribir).
final class HotkeyMonitor {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onOtherKeyWhileDown: (() -> Void)?
    var onChordDown: (() -> Void)?   // el acorde se une con la primaria ya abajo

    private let spec: HotkeySpec
    private let chord: HotkeySpec?
    private var keyIsDown = false
    private(set) var chordIsDown = false
    private var monitor: Any?

    init(spec: HotkeySpec, chord: HotkeySpec? = nil) {
        self.spec = spec
        self.chord = chord
    }

    static func ensureAccessibilityPermission() -> Bool {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self else { return }
            if event.type == .flagsChanged {
                if let chord = self.chord, event.keyCode == chord.keyCode {
                    // Estado del acorde por flags puros: inmune a resets por combo-cancel
                    let down = event.modifierFlags.contains(chord.flag)
                    let was = self.chordIsDown
                    self.chordIsDown = down
                    if down && !was && self.keyIsDown { self.onChordDown?() }
                } else if event.keyCode == self.spec.keyCode {
                    let down = event.modifierFlags.contains(self.spec.flag)
                    if down && !self.keyIsDown {
                        self.keyIsDown = true
                        self.onKeyDown?()
                    } else if !down && self.keyIsDown {
                        self.keyIsDown = false
                        self.onKeyUp?()
                    }
                }
            } else if event.type == .keyDown && self.keyIsDown {
                // hotkey+tecla normal = atajo del sistema, no dictado
                self.keyIsDown = false
                self.onOtherKeyWhileDown?()
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
