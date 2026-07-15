import Foundation

public struct HistoryLog {
    let file: URL
    public init(file: URL) { self.file = file }

    public func append(raw: String, clean: String, app: String? = nil, tone: String? = nil, rejected: String? = nil, selection: String? = nil) {
        var entry: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "raw": raw,
            "clean": clean,
        ]
        if let app { entry["app"] = app }
        if let tone { entry["tone"] = tone }
        if let selection { entry["selection"] = String(selection.prefix(2000)) }
        if let rejected {
            // El guardarraíl descartó la salida del LLM; se conserva para diagnóstico
            entry["guard_rejected"] = true
            entry["rejected"] = String(rejected.prefix(500))
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entry) else { return }
        var line = data
        line.append(Data("\n".utf8))
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: file)
            // Contiene todo lo dictado: solo legible por el usuario
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    // Rotación: elimina entradas y WAVs de failed/ más antiguos que days (0 = desactivada)
    public func prune(olderThanDays days: Int, failedDir: URL?, now: Date = Date()) {
        guard days > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        let fmt = ISO8601DateFormatter()
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            let kept = text.split(separator: "\n").filter { line in
                guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                      let ts = obj["ts"] as? String, let d = fmt.date(from: ts) else { return true }
                return d >= cutoff
            }
            let joined = kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n"
            try? joined.write(to: file, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        if let failedDir {
            let fm = FileManager.default
            for f in (try? fm.contentsOfDirectory(at: failedDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                let mod = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let mod, mod < cutoff { try? fm.removeItem(at: f) }
            }
        }
    }
}
