import Foundation

public enum Tones {
    public static let valid = ["neutral", "casual", "profesional", "tecnico", "verbatim"]

    public static func toneFor(bundleId: String?, appTones: [String: String]) -> String {
        guard let id = bundleId, let t = appTones[id], valid.contains(t) else { return "neutral" }
        return t
    }

    // Sección de registro que se añade al prompt base según el tono
    public static func registerRules(_ tone: String) -> String {
        switch tone {
        case "casual":
            return "\n\nRegistro (mensajería informal):\n- Conserva interjecciones y coloquialismos tal cual (jaja, buah, va, ostras).\n- No formalices: puntuación ligera, tono hablado."
        case "profesional":
            return "\n\nRegistro (email profesional):\n- Puntuación completa y registro cuidado.\n- NO inventes saludos ni despedidas que no se dijeron."
        case "tecnico":
            return "\n\nRegistro (texto técnico / prompts):\n- Conserva términos técnicos, comandos, rutas de fichero y anglicismos EXACTAMENTE como se dijeron.\n- No añadas cortesías ni suavices instrucciones."
        default:
            return ""
        }
    }
}
