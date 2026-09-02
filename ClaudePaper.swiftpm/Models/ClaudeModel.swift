import Foundation

/// Comment un modèle gère la réflexion (« thinking »).
enum ThinkingSupport: String, Codable {
    /// Réflexion toujours active (Claude Fable 5.1) : on ne peut pas la désactiver.
    case alwaysOn
    /// Réflexion adaptative (Claude Opus 5, Claude Sonnet 5).
    case adaptive
    /// Ancien mécanisme à budget de jetons (Claude Haiku 4.5).
    case budget
}

/// Niveau d'effort (`output_config.effort`).
enum Effort: String, CaseIterable, Codable, Identifiable {
    case low, medium, high, xhigh, max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Faible (rapide, économique)"
        case .medium: return "Moyen"
        case .high: return "Élevé (recommandé)"
        case .xhigh: return "Très élevé"
        case .max: return "Maximum (le plus lent, le plus cher)"
        }
    }
}

/// Description d'un modèle Claude utilisable dans l'app.
struct ClaudeModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let summary: String
    let contextTokens: Int
    let inputPricePerMillion: Double
    let outputPricePerMillion: Double
    let thinking: ThinkingSupport
    let supportsEffort: Bool
    /// Repli serveur (`fallbacks: "default"`) en cas de refus par les classifieurs de sécurité.
    let supportsServerFallbacks: Bool
    let maxOutputTokens: Int

    var priceLabel: String {
        "\(Self.format(inputPricePerMillion)) $ / \(Self.format(outputPricePerMillion)) $ par million de jetons (entrée / sortie)"
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}

extension ClaudeModel {
    static let fable51 = ClaudeModel(
        id: "claude-fable-5-1",
        displayName: "Claude Fable 5.1",
        summary: "Le plus intelligent. Réflexion toujours active, réponses parfois longues à venir.",
        contextTokens: 1_000_000,
        inputPricePerMillion: 10,
        outputPricePerMillion: 50,
        thinking: .alwaysOn,
        supportsEffort: true,
        supportsServerFallbacks: true,
        maxOutputTokens: 128_000
    )

    static let opus5 = ClaudeModel(
        id: "claude-opus-5",
        displayName: "Claude Opus 5",
        summary: "Recommandé comme tuteur : très rigoureux en mathématiques, réflexion adaptative.",
        contextTokens: 1_000_000,
        inputPricePerMillion: 5,
        outputPricePerMillion: 25,
        thinking: .adaptive,
        supportsEffort: true,
        supportsServerFallbacks: true,
        maxOutputTokens: 128_000
    )

    static let sonnet5 = ClaudeModel(
        id: "claude-sonnet-5",
        displayName: "Claude Sonnet 5",
        summary: "Rapide et précis. Idéal pour lire l'écriture manuscrite et pour la discussion courante.",
        contextTokens: 1_000_000,
        inputPricePerMillion: 2,
        outputPricePerMillion: 10,
        thinking: .adaptive,
        supportsEffort: true,
        supportsServerFallbacks: false,
        maxOutputTokens: 128_000
    )

    static let haiku45 = ClaudeModel(
        id: "claude-haiku-4-5",
        displayName: "Claude Haiku 4.5",
        summary: "Le plus économique. Suffisant pour transcrire une page, moins fiable comme tuteur.",
        contextTokens: 200_000,
        inputPricePerMillion: 1,
        outputPricePerMillion: 5,
        thinking: .budget,
        supportsEffort: false,
        supportsServerFallbacks: false,
        maxOutputTokens: 64_000
    )

    static let catalog: [ClaudeModel] = [fable51, opus5, sonnet5, haiku45]

    static func named(_ id: String) -> ClaudeModel {
        catalog.first { $0.id == id } ?? .opus5
    }
}
