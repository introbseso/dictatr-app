import AppKit

enum SelectionGrabber {
    // Copia la selección actual con Cmd+C simulado; nil si no había selección
    static func grab() async -> String? {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        let source = CGEventSource(stateID: .combinedSessionState)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)   // kVK_ANSI_C
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand
        cDown?.post(tap: .cghidEventTap)
        cUp?.post(tap: .cghidEventTap)
        for _ in 0..<12 {   // hasta ~600 ms sin bloquear el main thread
            try? await Task.sleep(nanoseconds: 50_000_000)
            if pb.changeCount != before { break }
        }
        guard pb.changeCount != before else { return nil }
        return pb.string(forType: .string)
    }
}
