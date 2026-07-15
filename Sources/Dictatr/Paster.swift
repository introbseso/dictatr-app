import AppKit
import CoreGraphics

enum Paster {
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    static func paste(_ text: String) {
        paste(text, restoring: NSPasteboard.general.string(forType: .string))
    }

    // Pega text sobre la selección/cursor y restaura después el clipboard indicado.
    // ConcealedType hace que los gestores de portapapeles ignoren el dictado.
    static func paste(_ text: String, restoring previous: String?) {
        let pb = NSPasteboard.general
        pb.declareTypes([.string, concealed], owner: nil)
        pb.setString(text, forType: .string)
        pb.setString("", forType: concealed)

        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)   // kVK_ANSI_V
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                pb.clearContents()
                pb.setString(previous, forType: .string)
            }
        }
    }
}
