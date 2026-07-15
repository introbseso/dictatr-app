import Foundation
import DictatrCore

enum GroqError: Error, LocalizedError {
    case noApiKey
    case http(Int, String)
    case emptyTranscription
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "Falta la API key de Groq en ~/.dictatr/config.json"
        case .http(let code, let body): return "Groq HTTP \(code): \(String(body.prefix(200)))"
        case .emptyTranscription: return "No se entendió nada en el audio"
        case .network(let e): return "Sin conexión: \(e.localizedDescription)"
        }
    }
}

struct GroqClient {
    let apiKey: String

    // Ejecuta un request con un reintento en errores transitorios (red o 429/5xx)
    private func send(_ req: URLRequest) async throws -> Data {
        var lastError: GroqError = .network(URLError(.unknown))
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 800_000_000) }
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 { return data }
                lastError = .http(status, String(decoding: data, as: UTF8.self))
                if !GroqAPI.isRetryable(status: status) { throw lastError }
            } catch let e as GroqError {
                throw e
            } catch {
                lastError = .network(error)
            }
        }
        throw lastError
    }

    func transcribe(wav: Data, dictionary: [String], language: String?) async throws -> String {
        guard !apiKey.isEmpty else { throw GroqError.noApiKey }
        let data = try await send(GroqAPI.transcriptionRequest(apiKey: apiKey, wav: wav, dictionary: dictionary, language: language))
        guard let text = GroqAPI.parseTranscription(data), !text.isEmpty else { throw GroqError.emptyTranscription }
        return text
    }

    // Reescritura de selección. nil en text = descartado (guardarraíl o rechazo RLHF);
    // rejected lleva la salida descartada
    func rewrite(text: String, instruction: String, model: String) async throws -> (text: String?, rejected: String?) {
        guard !apiKey.isEmpty else { throw GroqError.noApiKey }
        let data = try await send(GroqAPI.rewriteRequest(apiKey: apiKey, text: text, instruction: instruction, model: model))
        guard let result = GroqAPI.parseChat(data) else { throw GroqError.http(200, "respuesta vacía del modelo") }
        guard !GroqAPI.looksLikeRefusal(result),
              GroqAPI.acceptableRewrite(selection: text, result: result) else { return (nil, result) }
        return (result, nil)
    }

    // Si la limpieza falla o el guardarraíl la rechaza, devolvemos el crudo.
    // rejected = salida del LLM descartada por el guardarraíl (para diagnóstico en historial).
    func cleanup(text: String, dictionary: [String], tone: String = "neutral") async -> (text: String, rejected: String?) {
        guard !apiKey.isEmpty else { return (text, nil) }
        guard let data = try? await send(GroqAPI.cleanupRequest(apiKey: apiKey, text: text, dictionary: dictionary, tone: tone)),
              let clean = GroqAPI.parseChat(data) else { return (text, nil) }
        guard !GroqAPI.looksLikeRefusal(clean),
              GroqAPI.acceptableCleanup(raw: text, clean: clean) else { return (text, clean) }
        return (clean, nil)
    }
}
