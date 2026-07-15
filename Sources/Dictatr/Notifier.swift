import AppKit
import UserNotifications

final class Notifier {
    var soundsEnabled = true
    private let hasBundle = Bundle.main.bundleIdentifier != nil

    func requestPermission() {
        guard hasBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    func playStart() { play("Pop") }
    func playSuccess() { play("Glass") }
    func playError() { play("Basso") }
    func playNote() { play("Submarine") }

    private func play(_ name: String) {
        guard soundsEnabled else { return }
        NSSound(named: name)?.play()
    }

    func notify(title: String, body: String) {
        guard hasBundle else { NSLog("Dictatr: %@ — %@", title, body); return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
