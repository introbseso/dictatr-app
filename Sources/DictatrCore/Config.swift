import Foundation

public struct DictatrPaths {
    public let root: URL
    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dictatr")) {
        self.root = root
    }
    public var configFile: URL { root.appendingPathComponent("config.json") }
    public var dictionaryFile: URL { root.appendingPathComponent("dictionary.txt") }
    public var historyFile: URL { root.appendingPathComponent("history.jsonl") }
    public var failedDir: URL { root.appendingPathComponent("failed") }
    public var tmpDir: URL { root.appendingPathComponent("tmp") }
}

public struct Config {
    public var groqApiKey: String = ""
    public var sounds: Bool = true
    public var language: String? = nil   // nil = autodetección
    public var hotkey: String = "fn"     // fn | right_command | right_option
    public var appTones: [String: String] = [:]   // bundle ID → tono
    public var rewriteHotkey: String = "right_option"
    public var historyDays: Int = 30     // rotación de historial y failed/; 0 = sin rotación
    public var rewriteModel: String = "llama-3.3-70b-versatile"

    public static func decode(_ data: Data) -> Config {
        var c = Config()
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return c }
        c.groqApiKey = obj["groq_api_key"] as? String ?? ""
        c.sounds = obj["sounds"] as? Bool ?? true
        c.language = obj["language"] as? String
        c.hotkey = obj["hotkey"] as? String ?? "fn"
        c.appTones = obj["app_tones"] as? [String: String] ?? [:]
        c.rewriteHotkey = obj["rewrite_hotkey"] as? String ?? "right_option"
        c.historyDays = obj["history_days"] as? Int ?? 30
        c.rewriteModel = obj["rewrite_model"] as? String ?? "llama-3.3-70b-versatile"
        return c
    }

    public static let defaults: [String: Any] = [
        "groq_api_key": "",
        "sounds": true,
        "language": NSNull(),
        "hotkey": "fn",
        "app_tones": [String: String](),
        "rewrite_hotkey": "right_option",
        "history_days": 30,
        "rewrite_model": "llama-3.3-70b-versatile",
    ]

    // Añade claves ausentes con defaults; preserva valores existentes y claves desconocidas
    public static func migrate(paths: DictatrPaths) {
        let existing = (try? Data(contentsOf: paths.configFile)).flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
        var obj = existing ?? [:]
        var changed = existing == nil
        for (k, v) in defaults where obj[k] == nil {
            obj[k] = v
            changed = true
        }
        if changed { saveRaw(obj, paths: paths) }
    }

    public static func saveRaw(_ obj: [String: Any], paths: DictatrPaths) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: paths.configFile)
        // Contiene la API key: solo legible por el usuario
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.configFile.path)
    }

    public static func setValue(_ key: String, _ value: Any, paths: DictatrPaths) {
        var obj = (try? Data(contentsOf: paths.configFile)).flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        } ?? [:]
        obj[key] = value
        saveRaw(obj, paths: paths)
    }

    public static func load(paths: DictatrPaths) -> Config {
        guard let data = try? Data(contentsOf: paths.configFile) else { return Config() }
        return decode(data)
    }

    // Crea ~/.dictatr con plantillas si no existen. Nunca sobreescribe.
    public static func bootstrap(paths: DictatrPaths) {
        let fm = FileManager.default
        for dir in [paths.root, paths.failedDir, paths.tmpDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        migrate(paths: paths)
        if !fm.fileExists(atPath: paths.dictionaryFile.path) {
            let template = "# Un término por línea (nombres propios, siglas, jerga técnica).\n# Whisper y la limpieza los escribirán tal cual. Ejemplos comentados:\n# GitHub\n# Kubernetes\n"
            try? template.write(to: paths.dictionaryFile, atomically: true, encoding: .utf8)
        }
        // Config e historial contienen datos sensibles: forzar 0600 también en ficheros previos
        for f in [paths.configFile, paths.historyFile] where fm.fileExists(atPath: f.path) {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
        }
    }

    public static func loadDictionary(paths: DictatrPaths) -> [String] {
        guard let text = try? String(contentsOf: paths.dictionaryFile, encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
