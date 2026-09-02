import Foundation
import PencilKit
import UIKit

/// Résultat complet du pipeline de transcription d'une page.
struct TranscriptionOutcome {
    var transcription: Transcription
    var snapshot: PageSnapshot?
    var local: LocalRecognition?
}

enum TranscriptionStage {
    case rendering
    case onDevice
    case claude

    var label: String {
        switch self {
        case .rendering: return "Capture de la page…"
        case .onDevice: return "Reconnaissance locale (texte + symboles)…"
        case .claude: return "Lecture des symboles incertains par Claude…"
        }
    }
}

enum TranscriptionError: LocalizedError {
    case emptyPage

    var errorDescription: String? { "La page est vide : écrivez votre réponse avec le Pencil avant de terminer." }
}

/// Pipeline : rendu de la page → reconnaissance locale (Vision + symboles $P) → si doute,
/// lecture par Claude des cadres incertains, dont les réponses enrichissent la bibliothèque locale.
final class TranscriptionService {
    private let client: AnthropicClient
    private let library: SymbolLibrary

    init(client: AnthropicClient, library: SymbolLibrary) {
        self.client = client
        self.library = library
    }

    // MARK: - Pipeline

    func transcribe(drawing: PKDrawing,
                    mode: TranscriptionMode,
                    model: ClaudeModel,
                    useFallbacks: Bool,
                    learnFromClaude: Bool,
                    mathMode: Bool = true,
                    progress: @escaping @MainActor (TranscriptionStage) -> Void) async throws -> TranscriptionOutcome {
        await progress(.rendering)
        guard let snapshot = DrawingRenderer.snapshot(of: drawing) else {
            throw TranscriptionError.emptyPage
        }

        await progress(.onDevice)
        let ocr = try? await HandwritingRecognizer.recognize(snapshot.image, mathMode: mathMode)
        let templates = await library.all
        let local = await Task.detached(priority: .userInitiated) {
            LocalHandwritingEngine.recognize(drawing: drawing, snapshot: snapshot, ocr: ocr, templates: templates)
        }.value
        let draft = MathNormalizer.normalize(local.text)

        let escalate: Bool
        switch mode {
        case .onDeviceOnly: escalate = false
        case .alwaysClaude: escalate = true
        case .auto: escalate = Self.shouldEscalate(local: local, draft: draft)
        }

        if !escalate {
            let transcription = Transcription(text: draft,
                                              source: .onDevice,
                                              confidence: Self.localConfidence(local),
                                              onDeviceDraft: draft,
                                              localSymbolCount: local.matches.count,
                                              uncertainSymbolCount: local.uncertain.count,
                                              learnedSymbolCount: 0)
            return TranscriptionOutcome(transcription: transcription, snapshot: snapshot, local: local)
        }

        await progress(.claude)
        var transcription = try await transcribeWithClaude(snapshot: snapshot, draft: draft, local: local,
                                                           model: model, useFallbacks: useFallbacks, learn: learnFromClaude)
        transcription.onDeviceDraft = draft.isEmpty ? nil : draft
        return TranscriptionOutcome(transcription: transcription, snapshot: snapshot, local: local)
    }

    /// La lecture locale suffit-elle ? Sinon on demande à Claude (mode automatique).
    static func shouldEscalate(local: LocalRecognition, draft: String) -> Bool {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !local.uncertain.isEmpty { return true }
        if local.ocrConfidence < 0.5 { return true }
        return false
    }

    static func localConfidence(_ local: LocalRecognition) -> Double {
        let symbolScore = local.matches.isEmpty ? 1 : local.matches.map(\.score).reduce(0, +) / Double(local.matches.count)
        let base = 0.6 * local.ocrConfidence + 0.4 * symbolScore
        return min(max(base - 0.1 * Double(local.uncertain.count), 0.1), 1)
    }

    // MARK: - Lecture par Claude (image + cadres numérotés)

    static let transcriptionSchema: JSONValue = [
        "type": "object",
        "properties": [
            "text": ["type": "string", "description": "Transcription fidèle, en Unicode, avec les retours à la ligne."],
            "confidence": ["type": "number", "description": "Confiance globale entre 0 et 1."],
            "notes": ["type": "string", "description": "Passages douteux ou illisibles (vide si aucun)."],
            "symbols": [
                "type": "array",
                "description": "Contenu exact de chaque cadre rouge numéroté (vide si aucun cadre).",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "integer"],
                        "symbol": ["type": "string"]
                    ],
                    "required": ["id", "symbol"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["text", "confidence", "notes", "symbols"],
        "additionalProperties": false
    ]

    static let transcriptionSystemPrompt = """
    Tu es un système de transcription d'écriture manuscrite pour un étudiant francophone en mathématiques.
    Tu reçois l'image d'une page écrite à l'Apple Pencil. Transcris fidèlement TOUT ce qui est écrit, dans l'ordre de lecture, en texte Unicode :
    - quantificateurs et logique : ∀ ∃ ∃! ⇒ ⇔ ¬ ∧ ∨ ∴
    - ensembles : ∈ ∉ ⊂ ⊆ ⊄ ∪ ∩ ∅ ℝ ℕ ℤ ℚ ℂ, {x ∈ E | P(x)}, intervalles ]a, b[ et [a, b]
    - comparaisons et flèches : ≤ ≥ ≠ ≈ ≡ → ↦ ⟶
    - lettres grecques : ε δ α β γ λ μ ν η θ π σ τ φ ω Ω
    - indices et exposants : x₁ x₂ xₙ, x² xⁿ, sinon x_1 et x^n ; fractions a/b ; racines √ ; sommes ∑ ; produits ∏ ; intégrales ∫ ; limites lim ; normes ‖x‖ ; valeurs absolues |x| ; boules B(a, r), adhérence Ā, intérieur Å, complémentaire Aᶜ.
    Règles :
    - Respecte les retours à la ligne et l'ordre des lignes. Sépare les blocs distincts par une ligne vide.
    - Ne corrige jamais les mathématiques de l'étudiant, ne complète pas, n'interprète pas : tu transcris.
    - Un mot ou symbole illisible s'écrit [?]. Une rature s'ignore.
    - Le texte courant est en français : respecte les accents.
    - Une lecture locale faite par l'iPad peut t'être fournie : elle est peu fiable (symboles mathématiques souvent remplacés par des lettres) et ne sert que d'aide.
    - Des cadres rouges numérotés peuvent être dessinés sur l'image : ils ne font pas partie de l'écriture. Ils servent à demander ce que contient exactement chaque cadre, pour que l'iPad apprenne l'écriture de l'étudiant.
    """

    private struct SymbolReading: Decodable {
        var id: Int
        var symbol: String
    }

    private struct Reply: Decodable {
        var text: String
        var confidence: Double
        var notes: String
        var symbols: [SymbolReading]
    }

    /// Demande à Claude la transcription de la page et le contenu des cadres incertains ; apprend les symboles.
    func transcribeWithClaude(snapshot: PageSnapshot,
                              draft: String,
                              local: LocalRecognition?,
                              model: ClaudeModel,
                              useFallbacks: Bool,
                              learn: Bool) async throws -> Transcription {
        var boxes: [(id: Int, rect: CGRect)] = []
        var boxClusters: [Int: StrokeCluster] = [:]
        var boxGuesses: [Int: String] = [:]
        if let local {
            var nextID = 1
            for item in local.uncertain where nextID <= 24 {
                boxes.append((id: nextID, rect: item.cluster.bounds))
                boxClusters[nextID] = item.cluster
                if let guess = item.guess { boxGuesses[nextID] = guess }
                nextID += 1
            }
            for match in local.matches where nextID <= 24 {
                guard let cluster = local.clusters.first(where: { $0.id == match.clusterID }) else { continue }
                boxes.append((id: nextID, rect: cluster.bounds))
                boxClusters[nextID] = cluster
                boxGuesses[nextID] = match.label
                nextID += 1
            }
        }
        let imageToSend = boxes.isEmpty ? snapshot : DrawingRenderer.annotate(snapshot, boxes: boxes)

        var prompt = "Transcris cette page manuscrite."
        if !draft.isEmpty {
            prompt += "\n\nLecture locale de l'iPad (peu fiable, aide seulement) :\n«««\n\(draft)\n»»»"
        }
        if !boxes.isEmpty {
            prompt += """


            Les cadres rouges numérotés (1 à \(boxes.count)) entourent des symboles que l'iPad n'a pas su lire ou dont il n'est pas sûr. \
            Pour chaque numéro, indique dans « symbols » le symbole ou le très court jeton exactement écrit dans le cadre \
            (par exemple ∀, ∃, ∈, ⊂, ⇒, ⇔, ≤, ≠, ∅, ∞, ε, δ, lim, une lettre ou un chiffre). \
            Si un cadre contient une rature ou seulement un morceau de mot, mets une chaîne vide.
            """
            let guesses = boxGuesses.sorted { $0.key < $1.key }.map { "\($0.key) : « \($0.value) »" }
            if !guesses.isEmpty {
                prompt += "\nLectures locales à confirmer ou corriger : " + guesses.joined(separator: " ; ") + "."
            }
        }

        let message = APIMessage(role: "user", content: [
            .image(mediaType: imageToSend.mediaType, base64: imageToSend.base64),
            .text(prompt)
        ])
        var request = RequestBuilder.request(model: model,
                                             effort: .medium,
                                             showThinking: false,
                                             useFallbacks: useFallbacks,
                                             system: Self.transcriptionSystemPrompt,
                                             messages: [message],
                                             schema: Self.transcriptionSchema,
                                             maxTokens: 8_000)
        request.cacheControl = nil
        let response = try await client.complete(request)

        let json = TutorService.extractJSON(from: response.text)
        guard let data = json.data(using: .utf8), let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            // Réponse hors schéma : on garde le texte brut plutôt que de perdre le travail.
            return Transcription(text: response.text, source: .claudeVision, confidence: 0.5, modelID: response.model,
                                 localSymbolCount: local?.matches.count, uncertainSymbolCount: local?.uncertain.count, learnedSymbolCount: 0)
        }

        var learned = 0
        if learn {
            for reading in reply.symbols {
                let label = reading.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let cluster = boxClusters[reading.id], SymbolLibrary.isLearnable(label), let cloud = cluster.cloud else { continue }
                await library.learn(label: label, cloud: cloud, strokeCount: cluster.strokes.count)
                learned += 1
            }
        }

        var text = reply.text
        if !reply.notes.trimmingCharacters(in: .whitespaces).isEmpty {
            text += "\n\n[Passages douteux : \(reply.notes)]"
        }
        return Transcription(text: text,
                             source: .claudeVision,
                             confidence: min(max(reply.confidence, 0), 1),
                             modelID: response.model.isEmpty ? model.id : response.model,
                             localSymbolCount: local?.matches.count,
                             uncertainSymbolCount: local?.uncertain.count,
                             learnedSymbolCount: learned)
    }
}

/// Corrige les confusions courantes de la reconnaissance de texte dans un contexte mathématique.
enum MathNormalizer {
    /// Remplacements littéraux (sans risque pour les mots).
    private static let literal: [(String, String)] = [
        ("<=>", "⇔"), ("-->", "⟶"), ("=>", "⇒"), ("->", "→"),
        ("<=", "≤"), (">=", "≥"), ("!=", "≠"), ("=/=", "≠"), ("+-", "±"), ("...", "…"), ("|R", "ℝ"), ("|N", "ℕ")
    ]
    /// Remplacements sur des jetons isolés (évite « coordonnées » → « c∞rdonnées »).
    private static let tokens: [(String, String)] = [
        ("oo", "∞"), ("IR", "ℝ"), ("IN", "ℕ"), ("sqrt", "√"), ("€", "∈"), ("inf", "inf")
    ]

    static func normalize(_ text: String) -> String {
        var result = text
        for (from, to) in literal {
            result = result.replacingOccurrences(of: from, with: to)
        }
        for (from, to) in tokens where from != to {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: from) + "(?![\\p{L}\\p{N}])"
            result = result.replacingOccurrences(of: pattern, with: to, options: .regularExpression)
        }
        return result
    }
}
