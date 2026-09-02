import Foundation

// MARK: - Construction des requêtes

enum RequestBuilder {
    /// Construit une requête Messages adaptée aux capacités du modèle
    /// (réflexion adaptative, effort, sortie structurée, repli serveur).
    static func request(model: ClaudeModel,
                        effort: Effort?,
                        showThinking: Bool,
                        useFallbacks: Bool,
                        system: String,
                        messages: [APIMessage],
                        schema: JSONValue?,
                        maxTokens: Int) -> MessagesRequest {
        var request = MessagesRequest(model: model.id,
                                      maxTokens: min(maxTokens, model.maxOutputTokens),
                                      system: [SystemBlock(text: system)],
                                      messages: messages)
        switch model.thinking {
        case .alwaysOn:
            // Claude Fable 5.1 réfléchit toujours : on ne précise le paramètre que pour afficher le résumé.
            if showThinking {
                request.thinking = ThinkingParam(type: "adaptive", display: "summarized")
            }
        case .adaptive:
            request.thinking = ThinkingParam(type: "adaptive", display: showThinking ? "summarized" : nil)
        case .budget:
            // Claude Haiku 4.5 : pas de réflexion (rapide et économique).
            break
        }

        var outputConfig = OutputConfig()
        if model.supportsEffort, let effort {
            outputConfig.effort = effort.rawValue
        }
        if let schema {
            outputConfig.format = OutputFormat(schema: schema)
        }
        if outputConfig.effort != nil || outputConfig.format != nil {
            request.outputConfig = outputConfig
        }

        if model.supportsServerFallbacks && useFallbacks {
            request.fallbacks = "default"
            request.betas.append("server-side-fallback-2026-07-01")
        }
        return request
    }
}

// MARK: - Réponse structurée du tuteur

struct TutorReply: Decodable {
    var kind: String        // question | feedback | hint | message
    var verdict: String     // correct | partial | incorrect | unreadable | none
    var reading: String
    var message: String
    var question: String
    var needsImage: Bool

    var verdictValue: Verdict { Verdict(rawValue: verdict) ?? .notApplicable }
}

// MARK: - Textes envoyés au tuteur

enum TutorPrompts {
    static func newExercise(subject: String, instructions: String, pageNumber: Int) -> String {
        var text = "[Nouvel exercice — page \(pageNumber)]\n"
        if !subject.isEmpty { text += "Sujet : \(subject)\n" }
        if !instructions.isEmpty { text += "Consignes : \(instructions)\n" }
        text += """
        Pose-moi UNE question (kind = "question") que je résoudrai à la main sur une page. \
        Appuie-toi sur les documents de cours joints à cette discussion s'il y en a. \
        L'énoncé complet, autonome et précis va dans "question" ; "message" peut contenir une courte mise en contexte (ou rester vide).
        """
        return text
    }

    static func nextQuestion(pageNumber: Int) -> String {
        """
        [Question suivante — page \(pageNumber)]
        Pose-moi la question suivante (kind = "question"), dans la continuité de ce que nous avons vu, un peu plus difficile. \
        L'énoncé complet va dans "question".
        """
    }

    static func answer(pageNumber: Int, question: String, transcription: Transcription, imageAttached: Bool) -> String {
        let percent = Int((transcription.confidence * 100).rounded())
        var text = "[Réponse manuscrite — page \(pageNumber)]\n"
        text += "Question posée : \(question)\n\n"
        text += "Transcription automatique de ma réponse (\(transcription.source.label), confiance ≈ \(percent) %) :\n«««\n\(transcription.text)\n»»»\n"
        if imageAttached {
            text += "(L'image de ma page est jointe : lis directement mon écriture si la transcription est douteuse.)\n"
        }
        text += """

        Évalue ma réponse (kind = "feedback") : "verdict" = correct, partial, incorrect ou unreadable ; \
        ton explication pédagogique dans "message" ; ta lecture de ma réponse dans "reading". \
        Sois tolérant aux erreurs évidentes de reconnaissance d'écriture, mais rigoureux sur les mathématiques. \
        Si la transcription est trop ambiguë pour juger et qu'aucune image n'est jointe, mets needs_image = true et dis ce qui est ambigu. \
        Si c'est correct, propose la question suivante (un peu plus difficile) dans "question", sinon laisse "question" vide.
        """
        return text
    }

    static func imageFollowUp(pageNumber: Int) -> String {
        """
        [Image de la page \(pageNumber) jointe]
        Voici l'image de ma page. Lis directement mon écriture (indique ta lecture dans "reading") et évalue ma réponse (kind = "feedback", needs_image = false).
        """
    }

    static func hint(pageNumber: Int, question: String, progress: String?, imageAttached: Bool) -> String {
        var text = "[Indice — page \(pageNumber)]\n"
        text += "Question : \(question)\n"
        if let progress, !progress.isEmpty {
            text += "Où j'en suis (transcription automatique) :\n«««\n\(progress)\n»»»\n"
        }
        if imageAttached {
            text += "(L'image de ma page en cours est jointe.)\n"
        }
        text += "Donne-moi un indice (kind = \"hint\") qui me débloque sans donner la réponse. Adapte-le à ce que j'ai déjà écrit."
        return text
    }

    static func help(pageNumber: Int, question: String?, transcription: String?) -> String {
        var text = "J'ai besoin d'aide sur la page \(pageNumber)."
        if let question, !question.isEmpty { text += "\nQuestion : \(question)" }
        if let transcription, !transcription.isEmpty { text += "\nCe que j'ai écrit (transcription automatique) :\n«««\n\(transcription)\n»»»" }
        text += "\nL'image de ma page est jointe. Explique-moi où je bloque et comment avancer, sans faire tout l'exercice à ma place."
        return text
    }
}

// MARK: - Service tuteur

/// Prépare les échanges avec le tuteur (questions, évaluations, indices) et la discussion libre.
final class TutorService {
    let client: AnthropicClient
    let attachments: AttachmentStore

    init(client: AnthropicClient, attachments: AttachmentStore) {
        self.client = client
        self.attachments = attachments
    }

    /// Consigne système, figée pour toute la session (stable pour le cache et l'historique).
    static let systemPrompt = """
    Tu es un tuteur de mathématiques (et de sciences) patient, précis et exigeant, intégré dans une application iPad \
    où l'étudiant écrit ses réponses à la main avec l'Apple Pencil.

    Règles :
    - Réponds toujours en français, en tutoyant l'étudiant.
    - Écris les mathématiques en Unicode lisible (∀, ∃, ∈, ∉, ⊂, ⊆, ∪, ∩, ∅, ℝ, ℕ, ℤ, ℚ, ℂ, ⇒, ⇔, ¬, ∧, ∨, ≤, ≥, ≠, →, ε, δ, ∑, ∫, √, ∞, \
    indices et exposants Unicode comme x₁ ou x²). N'utilise jamais LaTeX ($…$, \\forall, \\frac…) : l'application ne le rend pas.
    - Les réponses de l'étudiant arrivent sous forme de transcription automatique de son écriture manuscrite, parfois avec des erreurs \
    de reconnaissance (symboles confondus, lettres manquantes, quantificateurs mal lus). Tolère les fautes de reconnaissance évidentes, \
    reste rigoureux sur les mathématiques, et si la transcription est trop ambiguë pour juger, demande l'image plutôt que de deviner.
    - Quand une image de la page est fournie, lis l'écriture manuscrite directement et indique ta lecture.
    - Mode exercice (messages entre crochets [Nouvel exercice], [Réponse manuscrite], [Indice], [Question suivante]) : tu réponds au format \
    JSON demandé. Une question doit être autonome, précise, adaptée au niveau et tenir sur une page manuscrite. Un indice ne donne pas la réponse. \
    Un retour dit clairement si c'est correct, partiellement correct ou incorrect, explique l'erreur, propose la correction, \
    puis (si c'est correct) pose la question suivante, un peu plus difficile.
    - Discussion libre : réponds en Markdown simple (titres, listes, gras), de façon concise et structurée.
    - Utilise les documents de cours joints (PDF, texte, images) comme référence pour les définitions, notations et le niveau attendu.
    """

    static let replySchema: JSONValue = [
        "type": "object",
        "properties": [
            "kind": ["type": "string", "enum": ["question", "feedback", "hint", "message"]],
            "verdict": ["type": "string", "enum": ["correct", "partial", "incorrect", "unreadable", "none"],
                        "description": "Uniquement pour kind = feedback ; sinon none."],
            "reading": ["type": "string", "description": "Ta lecture de la réponse de l'étudiant (vide si sans objet)."],
            "message": ["type": "string", "description": "Explication, retour ou indice, en Markdown simple avec mathématiques Unicode."],
            "question": ["type": "string", "description": "Énoncé complet de la (prochaine) question, vide s'il n'y en a pas."],
            "needs_image": ["type": "boolean", "description": "true si tu as besoin de l'image de la page pour interpréter la réponse."]
        ],
        "required": ["kind", "verdict", "reading", "message", "question", "needs_image"],
        "additionalProperties": false
    ]

    // MARK: Historique

    /// Convertit l'historique de la session au format de l'API (fusion des tours consécutifs de même rôle).
    func history(for session: StudySession) -> [APIMessage] {
        var result: [APIMessage] = []
        for message in session.messages where message.kind != .note && !message.isError {
            var blocks: [ContentBlock] = []
            if message.role == .user {
                for id in message.attachmentIDs {
                    guard let attachment = session.attachments.first(where: { $0.id == id }),
                          let data = attachments.data(for: attachment) else { continue }
                    switch attachment.kind {
                    case .pdf:
                        blocks.append(.document(mediaType: "application/pdf", base64: data.base64EncodedString(), title: attachment.filename))
                    case .image:
                        blocks.append(.image(mediaType: attachment.mediaType, base64: data.base64EncodedString()))
                    case .text:
                        if let text = String(data: data, encoding: .utf8) {
                            blocks.append(.textDocument(text: text, title: attachment.filename))
                        }
                    }
                }
            }
            let text = message.textForAPI.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.text(text))
            }
            guard !blocks.isEmpty else { continue }
            let role = message.role == .user ? "user" : "assistant"
            if let last = result.last, last.role == role {
                result[result.count - 1].content.append(contentsOf: blocks)
            } else {
                result.append(APIMessage(role: role, content: blocks))
            }
        }
        while let first = result.first, first.role != "user" {
            result.removeFirst()
        }
        return result
    }

    // MARK: Mode exercice (JSON structuré)

    func askStructured(session: StudySession,
                       model: ClaudeModel,
                       effort: Effort,
                       showThinking: Bool,
                       useFallbacks: Bool,
                       onEvent: ((ClaudeEvent) -> Void)? = nil) async throws -> (reply: TutorReply, response: ClaudeResponse) {
        let request = RequestBuilder.request(model: model,
                                             effort: effort,
                                             showThinking: showThinking,
                                             useFallbacks: useFallbacks,
                                             system: Self.systemPrompt,
                                             messages: history(for: session),
                                             schema: Self.replySchema,
                                             maxTokens: 16_000)
        let response = try await client.complete(request, onEvent: onEvent)
        return (Self.parseReply(response.text), response)
    }

    static func parseReply(_ text: String) -> TutorReply {
        let json = extractJSON(from: text)
        if let data = json.data(using: .utf8),
           let reply = try? JSONDecoder.snakeCase.decode(TutorReply.self, from: data) {
            return reply
        }
        // Réponse hors format : on garde le texte comme message.
        return TutorReply(kind: "message", verdict: "none", reading: "", message: text, question: "", needsImage: false)
    }

    /// Extrait le premier objet JSON d'un texte (en ignorant d'éventuelles barrières ```).
    static func extractJSON(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else {
            return text
        }
        return String(text[start...end])
    }

    // MARK: Discussion libre (streaming)

    func streamChat(session: StudySession,
                    model: ClaudeModel,
                    effort: Effort,
                    showThinking: Bool,
                    useFallbacks: Bool) -> AsyncThrowingStream<ClaudeEvent, Error> {
        let request = RequestBuilder.request(model: model,
                                             effort: effort,
                                             showThinking: showThinking,
                                             useFallbacks: useFallbacks,
                                             system: Self.systemPrompt,
                                             messages: history(for: session),
                                             schema: nil,
                                             maxTokens: 32_000)
        return client.stream(request)
    }
}
