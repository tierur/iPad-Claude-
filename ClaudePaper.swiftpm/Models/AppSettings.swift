import Foundation
import SwiftUI

/// Stratégie de transcription de l'écriture manuscrite.
enum TranscriptionMode: String, CaseIterable, Codable, Identifiable {
    /// Reconnaissance sur l'iPad, puis analyse de l'image par Claude si le résultat est douteux
    /// ou si la page contient des mathématiques.
    case auto
    /// Toujours analyser l'image avec Claude (le plus fiable pour les quantificateurs).
    case alwaysClaude
    /// Uniquement la reconnaissance sur l'iPad (gratuit, mais sans symboles mathématiques).
    case onDeviceOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatique (iPad puis Claude si besoin)"
        case .alwaysClaude: return "Toujours analyser l'image avec Claude"
        case .onDeviceOnly: return "Seulement la reconnaissance de l'iPad"
        }
    }
}

enum PaperStyle: String, CaseIterable, Codable, Identifiable {
    case blank, lines, grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blank: return "Blanc"
        case .lines: return "Lignes"
        case .grid: return "Quadrillé"
        }
    }
}

/// Réglages de l'app (UserDefaults) + clé API (trousseau).
final class AppSettings: ObservableObject {
    private static let apiKeyAccount = "anthropic-api-key"
    private let defaults = UserDefaults.standard

    @Published var apiKey: String {
        didSet {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                KeychainStore.delete(account: Self.apiKeyAccount)
            } else {
                do {
                    try KeychainStore.save(trimmed, account: Self.apiKeyAccount)
                } catch {
                    keychainError = error.localizedDescription
                }
            }
        }
    }
    @Published var keychainError: String?

    @Published var tutorModelID: String { didSet { defaults.set(tutorModelID, forKey: "tutorModelID") } }
    @Published var chatModelID: String { didSet { defaults.set(chatModelID, forKey: "chatModelID") } }
    @Published var transcriptionModelID: String { didSet { defaults.set(transcriptionModelID, forKey: "transcriptionModelID") } }
    @Published var effort: Effort { didSet { defaults.set(effort.rawValue, forKey: "effort") } }
    @Published var showThinking: Bool { didSet { defaults.set(showThinking, forKey: "showThinking") } }
    @Published var transcriptionMode: TranscriptionMode { didSet { defaults.set(transcriptionMode.rawValue, forKey: "transcriptionMode") } }
    @Published var allowFingerDrawing: Bool { didSet { defaults.set(allowFingerDrawing, forKey: "allowFingerDrawing") } }
    @Published var attachImageWithAnswer: Bool { didSet { defaults.set(attachImageWithAnswer, forKey: "attachImageWithAnswer") } }
    @Published var useServerFallbacks: Bool { didSet { defaults.set(useServerFallbacks, forKey: "useServerFallbacks") } }
    @Published var paperStyle: PaperStyle { didSet { defaults.set(paperStyle.rawValue, forKey: "paperStyle") } }
    @Published var reviewTranscriptionBeforeSending: Bool { didSet { defaults.set(reviewTranscriptionBeforeSending, forKey: "reviewTranscriptionBeforeSending") } }

    init() {
        let defaults = UserDefaults.standard
        apiKey = KeychainStore.read(account: Self.apiKeyAccount) ?? ""
        tutorModelID = defaults.string(forKey: "tutorModelID") ?? ClaudeModel.opus5.id
        chatModelID = defaults.string(forKey: "chatModelID") ?? ClaudeModel.opus5.id
        transcriptionModelID = defaults.string(forKey: "transcriptionModelID") ?? ClaudeModel.sonnet5.id
        effort = Effort(rawValue: defaults.string(forKey: "effort") ?? "") ?? .high
        showThinking = defaults.object(forKey: "showThinking") as? Bool ?? false
        transcriptionMode = TranscriptionMode(rawValue: defaults.string(forKey: "transcriptionMode") ?? "") ?? .auto
        allowFingerDrawing = defaults.object(forKey: "allowFingerDrawing") as? Bool ?? false
        attachImageWithAnswer = defaults.object(forKey: "attachImageWithAnswer") as? Bool ?? false
        useServerFallbacks = defaults.object(forKey: "useServerFallbacks") as? Bool ?? true
        paperStyle = PaperStyle(rawValue: defaults.string(forKey: "paperStyle") ?? "") ?? .lines
        reviewTranscriptionBeforeSending = defaults.object(forKey: "reviewTranscriptionBeforeSending") as? Bool ?? true
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var tutorModel: ClaudeModel { ClaudeModel.named(tutorModelID) }
    var chatModel: ClaudeModel { ClaudeModel.named(chatModelID) }
    var transcriptionModel: ClaudeModel { ClaudeModel.named(transcriptionModelID) }
}
