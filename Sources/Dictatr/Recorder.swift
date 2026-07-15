import AVFoundation
import Foundation

final class Recorder {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private let fileURL: URL

    init(tmpDir: URL) {
        fileURL = tmpDir.appendingPathComponent("current.wav")
    }

    static func requestMicPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: completion(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { completion(ok) } }
        default: completion(false)
        }
    }

    func start() -> Bool {
        try? FileManager.default.removeItem(at: fileURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        guard let r = try? AVAudioRecorder(url: fileURL, settings: settings) else { return false }
        recorder = r
        guard r.record() else { recorder = nil; return false }
        startedAt = Date()
        return true
    }

    // Devuelve (wav, duración) o nil si no había grabación
    func stop() -> (data: Data, duration: TimeInterval)? {
        guard let r = recorder, let t0 = startedAt else { return nil }
        r.stop()
        recorder = nil
        startedAt = nil
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return (data, Date().timeIntervalSince(t0))
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        startedAt = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    // El WAV temporal contiene la voz del último dictado: borrarlo al terminar
    func removeTempFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // Conserva el WAV de un dictado fallido para no perderlo
    func preserveFailed(in failedDir: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? FileManager.default.copyItem(at: fileURL, to: failedDir.appendingPathComponent("\(stamp).wav"))
    }
}
