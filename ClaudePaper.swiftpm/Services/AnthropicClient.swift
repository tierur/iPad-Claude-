import Foundation

// MARK: - Format « wire » de l'API Messages (https://api.anthropic.com/v1/messages)

struct SystemBlock: Encodable {
    let type = "text"
    let text: String
}

/// Bloc de contenu d'un message envoyé à l'API.
enum ContentBlock: Encodable {
    case text(String)
    case image(mediaType: String, base64: String)
    case document(mediaType: String, base64: String, title: String?)
    case textDocument(text: String, title: String?)

    private enum CodingKeys: String, CodingKey { case type, text, source, title }
    private enum SourceKeys: String, CodingKey { case type, mediaType = "media_type", data }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let mediaType, let base64):
            try container.encode("image", forKey: .type)
            var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try source.encode("base64", forKey: .type)
            try source.encode(mediaType, forKey: .mediaType)
            try source.encode(base64, forKey: .data)
        case .document(let mediaType, let base64, let title):
            try container.encode("document", forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
            var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try source.encode("base64", forKey: .type)
            try source.encode(mediaType, forKey: .mediaType)
            try source.encode(base64, forKey: .data)
        case .textDocument(let text, let title):
            try container.encode("document", forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
            var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try source.encode("text", forKey: .type)
            try source.encode("text/plain", forKey: .mediaType)
            try source.encode(text, forKey: .data)
        }
    }
}

struct APIMessage: Encodable {
    var role: String
    var content: [ContentBlock]
}

struct ThinkingParam: Encodable {
    var type: String
    var display: String? = nil
    var budgetTokens: Int? = nil

    private enum CodingKeys: String, CodingKey {
        case type, display
        case budgetTokens = "budget_tokens"
    }
}

struct OutputFormat: Encodable {
    let type = "json_schema"
    var schema: JSONValue
}

struct OutputConfig: Encodable {
    var effort: String? = nil
    var format: OutputFormat? = nil
}

struct CacheControl: Encodable {
    let type = "ephemeral"
}

struct MessagesRequest: Encodable {
    var model: String
    var maxTokens: Int
    var system: [SystemBlock]? = nil
    var messages: [APIMessage]
    var stream: Bool = true
    var thinking: ThinkingParam? = nil
    var outputConfig: OutputConfig? = nil
    /// `"default"` : repli serveur automatique en cas de refus (beta `server-side-fallback-2026-07-01`).
    var fallbacks: String? = nil
    /// Mise en cache automatique du préfixe (system + historique).
    var cacheControl: CacheControl? = CacheControl()
    /// En-têtes `anthropic-beta` (non encodés dans le corps).
    var betas: [String] = []

    private enum CodingKeys: String, CodingKey {
        case model, system, messages, stream, thinking, fallbacks
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
        case cacheControl = "cache_control"
    }
}

// MARK: - Flux SSE

struct StopDetails: Decodable, Equatable {
    var type: String?
    var category: String?
    var explanation: String?
}

struct TokenUsage: Equatable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadInputTokens = 0
    var cacheCreationInputTokens = 0

    mutating func merge(_ other: StreamPayload.Usage) {
        if let value = other.inputTokens { inputTokens = value }
        if let value = other.outputTokens { outputTokens = value }
        if let value = other.cacheReadInputTokens { cacheReadInputTokens = value }
        if let value = other.cacheCreationInputTokens { cacheCreationInputTokens = value }
    }
}

struct StreamPayload: Decodable {
    var type: String
    var index: Int?
    var message: MessageHeader?
    var contentBlock: BlockStart?
    var delta: Delta?
    var usage: Usage?
    var error: APIErrorBody?

    struct MessageHeader: Decodable {
        var id: String?
        var model: String?
        var usage: Usage?
    }

    struct BlockStart: Decodable {
        var type: String
        var text: String?
        var thinking: String?
        var from: ModelRef?
        var to: ModelRef?
    }

    struct ModelRef: Decodable {
        var model: String?
    }

    struct Delta: Decodable {
        var type: String?
        var text: String?
        var thinking: String?
        var stopReason: String?
        var stopDetails: StopDetails?
    }

    struct Usage: Decodable {
        var inputTokens: Int?
        var outputTokens: Int?
        var cacheReadInputTokens: Int?
        var cacheCreationInputTokens: Int?
    }
}

struct APIErrorBody: Decodable {
    var type: String?
    var message: String?
}

struct APIErrorEnvelope: Decodable {
    var type: String?
    var error: APIErrorBody?
    var requestId: String?
}

enum ClaudeEvent {
    case started(model: String)
    case text(String)
    case thinking(String)
    case fallback(from: String, to: String)
    case finished(stopReason: String?, stopDetails: StopDetails?, usage: TokenUsage)
}

struct ClaudeResponse {
    var text = ""
    var thinking = ""
    var model = ""
    var stopReason: String? = nil
    var stopDetails: StopDetails? = nil
    var usage = TokenUsage()
    var usedFallback = false

    var wasTruncated: Bool { stopReason == "max_tokens" }
}

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case http(status: Int, type: String, message: String)
    case network(String)
    case streamError(String)
    case refused(category: String?, explanation: String?)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Aucune clé API. Ajoutez votre clé Anthropic dans les réglages (console.anthropic.com)."
        case .http(let status, let type, let message):
            switch status {
            case 401: return "Clé API refusée (401). Vérifiez la clé dans les réglages."
            case 403: return "Accès refusé (403) : \(message)"
            case 404: return "Modèle ou point d'accès introuvable (404) : \(message)"
            case 413: return "Requête trop volumineuse (413). Réduisez la taille des documents joints."
            case 429: return "Limite de débit atteinte (429). Réessayez dans quelques secondes."
            case 529: return "L'API est surchargée (529). Réessayez dans un instant."
            default: return "Erreur API \(status) (\(type)) : \(message)"
            }
        case .network(let message):
            return "Problème réseau : \(message)"
        case .streamError(let message):
            return "Erreur pendant la réponse : \(message)"
        case .refused(let category, let explanation):
            var text = "Claude a refusé cette requête"
            if let category, !category.isEmpty { text += " (catégorie : \(category))" }
            if let explanation, !explanation.isEmpty { text += " : \(explanation)" }
            return text + "."
        case .invalidResponse(let message):
            return "Réponse inattendue : \(message)"
        }
    }
}

extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

// MARK: - Client

/// Client HTTP minimal pour l'API Messages d'Anthropic (streaming SSE).
final class AnthropicClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private let session: URLSession
    private let apiKeyProvider: @MainActor () -> String

    init(apiKeyProvider: @escaping @MainActor () -> String) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600      // délai entre deux paquets (le flux envoie des « ping »)
        configuration.timeoutIntervalForResource = 3600
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
        self.apiKeyProvider = apiKeyProvider
    }

    /// Envoie la requête et renvoie les événements au fur et à mesure.
    func stream(_ request: MessagesRequest) -> AsyncThrowingStream<ClaudeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(request, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Envoie la requête (en streaming) et accumule la réponse complète.
    func complete(_ request: MessagesRequest, onEvent: ((ClaudeEvent) -> Void)? = nil) async throws -> ClaudeResponse {
        var response = ClaudeResponse()
        for try await event in stream(request) {
            onEvent?(event)
            switch event {
            case .started(let model):
                response.model = model
            case .text(let text):
                response.text += text
            case .thinking(let text):
                response.thinking += text
            case .fallback(_, let to):
                response.usedFallback = true
                response.model = to
            case .finished(let stopReason, let stopDetails, let usage):
                response.stopReason = stopReason
                response.stopDetails = stopDetails
                response.usage = usage
            }
        }
        if response.stopReason == "refusal" {
            throw ClaudeError.refused(category: response.stopDetails?.category, explanation: response.stopDetails?.explanation)
        }
        return response
    }

    // MARK: Requête HTTP

    private func run(_ request: MessagesRequest, continuation: AsyncThrowingStream<ClaudeEvent, Error>.Continuation) async throws {
        let key = await apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ClaudeError.missingAPIKey }

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !request.betas.isEmpty {
            urlRequest.setValue(request.betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        var streamingRequest = request
        streamingRequest.stream = true
        urlRequest.httpBody = try JSONEncoder().encode(streamingRequest)

        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()
            let bytes: URLSession.AsyncBytes
            let response: URLResponse
            do {
                (bytes, response) = try await session.bytes(for: urlRequest)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt <= 3 {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                    continue
                }
                throw ClaudeError.network(error.localizedDescription)
            }
            guard let http = response as? HTTPURLResponse else {
                throw ClaudeError.invalidResponse("réponse non HTTP")
            }
            if http.statusCode != 200 {
                var data = Data()
                for try await byte in bytes { data.append(byte) }
                let envelope = try? JSONDecoder.snakeCase.decode(APIErrorEnvelope.self, from: data)
                let type = envelope?.error?.type ?? "http_error"
                let message = envelope?.error?.message ?? (String(data: data, encoding: .utf8) ?? "erreur HTTP \(http.statusCode)")
                if [429, 500, 502, 503, 529].contains(http.statusCode), attempt <= 3 {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 3_000_000_000)
                    continue
                }
                throw ClaudeError.http(status: http.statusCode, type: type, message: message)
            }
            try await parse(bytes, continuation: continuation)
            return
        }
    }

    // MARK: Analyse du flux SSE

    private func parse(_ bytes: URLSession.AsyncBytes, continuation: AsyncThrowingStream<ClaudeEvent, Error>.Continuation) async throws {
        let decoder = JSONDecoder.snakeCase
        var usage = TokenUsage()
        var stopReason: String? = nil
        var stopDetails: StopDetails? = nil
        var finishedSent = false

        // Chaque événement de l'API tient sur une seule ligne « data: {...} ».
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard !jsonString.isEmpty, let data = jsonString.data(using: .utf8) else { continue }
            guard let payload = try? decoder.decode(StreamPayload.self, from: data) else { continue }

            switch payload.type {
            case "message_start":
                if let messageUsage = payload.message?.usage { usage.merge(messageUsage) }
                continuation.yield(.started(model: payload.message?.model ?? ""))

            case "content_block_start":
                let blockType = payload.contentBlock?.type ?? ""
                if blockType == "fallback" {
                    continuation.yield(.fallback(from: payload.contentBlock?.from?.model ?? "?",
                                                 to: payload.contentBlock?.to?.model ?? "?"))
                } else if blockType == "text", let text = payload.contentBlock?.text, !text.isEmpty {
                    continuation.yield(.text(text))
                }

            case "content_block_delta":
                let deltaType = payload.delta?.type ?? ""
                if deltaType == "text_delta", let text = payload.delta?.text {
                    continuation.yield(.text(text))
                } else if deltaType == "thinking_delta", let text = payload.delta?.thinking, !text.isEmpty {
                    continuation.yield(.thinking(text))
                }

            case "message_delta":
                if let deltaUsage = payload.usage { usage.merge(deltaUsage) }
                if let reason = payload.delta?.stopReason { stopReason = reason }
                if let details = payload.delta?.stopDetails { stopDetails = details }

            case "message_stop":
                continuation.yield(.finished(stopReason: stopReason, stopDetails: stopDetails, usage: usage))
                finishedSent = true

            case "error":
                throw ClaudeError.streamError(payload.error?.message ?? "erreur inconnue")

            default:
                break // ping, content_block_stop, …
            }
        }
        if !finishedSent {
            continuation.yield(.finished(stopReason: stopReason, stopDetails: stopDetails, usage: usage))
        }
    }
}
