import Foundation
import PencilKit
import UIKit

/// Résultat complet du pipeline de transcription d'une page.
struct TranscriptionOutcome {
    var transcription: Transcription
    var snapshot: PageSnapshot?
    var onDevice: RecognitionResult?
}

enum TranscriptionStage {
    case rendering
    case onDevice
    case claude

    var label: String {
        switch self {
        case .rendering: return "Capture de la page…"
        case .onDevice: return "Reconnaissance de l'écriture sur l'iPad…"
        case .claude: return "Analyse de l'image par Claude…"
        }
    }
}

enum TranscriptionError: LocalizedError {
    case emptyPage

    var errorDescription: String? { "La page est vide : écrivez votre réponse avec le Pencil avant de terminer." }
}

/// Pipeline : rendu de la page → reconnaissance sur l'iPad (Vision) → si besoin, analyse de l'image par Claude.
final class TranscriptionService {
    private let client: AnthropicClient

    init(client: AnthropicClient) {
        self.client = client
    }

    // MARK: - Pipeline

    func transcribe(drawing: PKDrawing,
                    mode: TranscriptionMode,
                    model: ClaudeModel,
                    useFallbacks: Bool,
                    mathMode: Bool = true,
                    progress: @escaping @MainActor (TranscriptionStage) -> Void) async throws -> TranscriptionOutcome {
        await progress(.rendering)
        guard let snapshot = DrawingRenderer.snapshot(of: drawing) else {
            throw TranscriptionError.emptyPage
        }

        await progress(.onDevice)
        var onDevice: RecognitionResult? = nil
        do {
            onDevice = try await HandwritingRecognizer.recognize(snapshot.image, mathMode: mathMode)
        } catch {
            onDevice = nil
        }
        let draft = onDevice.map { MathNormalizer.normalize($0.text) } ?? ""
        let draftConfidence = onDevice?.meanConfidence ?? 0

        let escalate: Bool
        switch mode {
        case .onDeviceOnly: escalate = false
        case .alwaysClaude: escalate = true
        case .auto: escalate = Self.shouldEscalate(text: draft, confidence: draftConfidence, mathMode: mathMode)
        }

        if !escalate {
            let transcription = Transcription(text: draft, source: .onDevice, confidence: draftConfidence, onDeviceDraft: draft)
            return TranscriptionOutcome(transcription: transcription, snapshot: snapshot, onDevice: onDevice)
        }

        await progress(.claude)
        let claude = try await transcribeWithClaude(snapshot: snapshot, draft: draft, model: model, useFallbacks: useFallbacks)
        var transcription = claude
        transcription.onDeviceDraft = draft.isEmpty ? nil : draft
        return TranscriptionOutcome(transcription: transcription, snapshot: snapshot, onDevice: onDevice)
    }

    /// Décide si le résultat de l'iPad est assez fiable pour se passer de l'analyse d'image.
    static func shouldEscalate(text: String, confidence: Double, mathMode: Bool) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if confidence < 0.9 { return true }
        let words = trimmed.split { $0.isWhitespace || $0.isNewline }
        if words.count < 3 { return true }
        if mathMode && Self.looksMathematical(trimmed) { return true }
        return false
    }

    static func looksMathematical(_ text: String) -> Bool {
        let mathCharacters = CharacterSet(charactersIn: "0123456789=+-*/^_<>()[]{}|∀∃∈⊂⊆∪∩∅ℝℕℤℚℂ⇒⇔¬∧∨≤≥≠→∞∑∫√εδαβγλμπ")
        let count = text.unicodeScalars.filter { mathCharacters.contains($0) }.count
        return count >= 2
    }

    // MARK: - Analyse de l'image par Claude

    static let transcriptionSchema: JSONValue = [
        "type": "object",
        "properties": [
            "text": ["type": "string", "description": "Transcription fidèle, en Unicode, avec les retours à la ligne."],
            "confidence": ["type": "number", "description": "Confiance globale entre 0 et 1."],
            "notes": ["type": "string", "description": "Passages douteux ou illisibles (vide si aucun)."]
        ],
        "required": ["text", "confidence", "notes"],
        "additionalProperties": false
    ]

    static let transcriptionSystemPrompt = """
    Tu es un système de transcription d'écriture manuscrite pour un étudiant francophone en mathématiques.
    Tu reçois l'image d'une page écrite à l'Apple Pencil. Transcris fidèlement TOUT ce qui est écrit, dans l'ordre de lecture, en texte Unicode :
    - quantificateurs et logique : ∀ ∃ ∃! ⇒ ⇔ ¬ ∧ ∨ ∴
    - ensembles : ∈ ∉ ⊂ ⊆ ⊄ ∪ ∩ ∅ ℝ ℕ ℤ ℚ ℂ, {x ∈ E | P(x)}, intervalles ]a, b[ et [a, b]
    - comparaisons et flèches : ≤ ≥ ≠ ≈ ≡ → ↦ ⟶
    - lettres grecques : ε δ α β γ λ μ ν η θ π σ τ φ ω Ω
    - indices et exposants : x₁ x₂ xₙ, x² xⁿ, sinon x_1 et x^n ; fractions a/b ; racines √ ; sommes ∑ ; produits ∏ ; intégrales ∫ ; limites lim ; normes ‖x‖ ; valeurs absolues |x| ; barres B(a, r), boules B̄, adhérence Ā, intérieur Å, complémentaire Aᶜ.
    Règles :
    - Respecte les retours à la ligne et l'ordre des lignes. Sépare les colonnes ou blocs distincts par une ligne vide.
    - Ne corrige jamais les mathématiques de l'étudiant, ne complète pas, n'interprète pas : tu transcris.
    - Un mot ou symbole illisible s'écrit [?]. Une rature s'ignore.
    - Le texte courant est en français : respecte les accents.
    - Un brouillon issu de la reconnaissance de l'iPad peut t'être fourni : il est peu fiable (les symboles mathématiques y sont souvent remplacés par des lettres) et ne sert que d'aide.
    """

    func transcribeWithClaude(snapshot: PageSnapshot, draft: String, model: ClaudeModel, useFallbacks: Bool) async throws -> Transcription {
        var prompt = "Transcris cette page manuscrite."
        if !draft.isEmpty {
            prompt += "\n\nBrouillon de la reconnaissance de l'iPad (peu fiable) :\n«««\n\(draft)\n»»»"
        }
        let message = APIMessage(role: "user", content: [
            .image(mediaType: snapshot.mediaType, base64: snapshot.base64),
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

        struct Reply: Decodable {
            var text: String
            var confidence: Double
            var notes: String
        }
        let json = TutorService.extractJSON(from: response.text)
        guard let data = json.data(using: .utf8), let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            // Réponse hors schéma : on garde le texte brut plutôt que de perdre le travail.
            return Transcription(text: response.text, source: .claudeVision, confidence: 0.5, modelID: response.model)
        }
        var text = reply.text
        if !reply.notes.trimmingCharacters(in: .whitespaces).isEmpty {
            text += "\n\n[Passages douteux : \(reply.notes)]"
        }
        return Transcription(text: text,
                             source: .claudeVision,
                             confidence: min(max(reply.confidence, 0), 1),
                             modelID: response.model.isEmpty ? model.id : response.model)
    }
}

/// Corrige les confusions courantes de la reconnaissance sur l'iPad dans un contexte mathématique.
enum MathNormalizer {
    private static let replacements: [(String, String)] = [
        ("<=>", "⇔"), ("=>", "⇒"), ("->", "→"), ("-->", "⟶"),
        ("<=", "≤"), (">=", "≥"), ("!=", "≠"), ("=/=", "≠"),
        ("+-", "±"), ("...", "…"), ("|R", "ℝ"), ("IR", "ℝ"), ("|N", "ℕ"), ("IN", "ℕ"),
        ("€", "∈"), ("sqrt", "√"), ("inf.", "inf"), ("oo", "∞")
    ]

    static func normalize(_ text: String) -> String {
        var result = text
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }
}
