import Foundation

// MARK: - Session d'étude (une discussion + ses pages)

struct StudySession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var subject: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var messages: [ChatMessage] = []
    var pages: [Page] = [Page(number: 1)]
    var currentPageIndex: Int = 0
    var attachments: [Attachment] = []
    /// Modèle tuteur propre à cette session (sinon celui des réglages).
    var tutorModelID: String? = nil
    /// Nombre de bonnes réponses / réponses évaluées.
    var correctCount: Int = 0
    var answeredCount: Int = 0

    var currentPage: Page {
        get { pages[min(max(currentPageIndex, 0), pages.count - 1)] }
        set { pages[min(max(currentPageIndex, 0), pages.count - 1)] = newValue }
    }
}

// MARK: - Page de papier

enum PageStatus: String, Codable {
    case blank        // pas de question, page libre
    case drafting     // question posée, réponse en cours
    case evaluating   // envoyée à Claude
    case correct
    case partial
    case incorrect
    case unreadable
}

struct Page: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var number: Int
    /// Énoncé (Markdown + Unicode) affiché en haut de la page. `nil` = page libre.
    var question: String? = nil
    var drawingData: Data = Data()
    var transcription: Transcription? = nil
    var feedback: Feedback? = nil
    var hints: [String] = []
    var status: PageStatus = .blank
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var hasQuestion: Bool { !(question ?? "").isEmpty }
    var isAnswered: Bool { feedback != nil }
}

// MARK: - Transcription de l'écriture manuscrite

enum TranscriptionSource: String, Codable {
    case onDevice      // Vision (sur l'iPad)
    case claudeVision  // analyse de l'image par un modèle Claude
    case manual        // corrigée à la main

    var label: String {
        switch self {
        case .onDevice: return "reconnaissance locale sur l'iPad"
        case .claudeVision: return "analyse de l'image par Claude"
        case .manual: return "corrigée à la main"
        }
    }
}

struct Transcription: Codable, Equatable {
    var text: String
    var source: TranscriptionSource
    var confidence: Double
    var onDeviceDraft: String? = nil
    var modelID: String? = nil
    var createdAt: Date = Date()
    /// Symboles reconnus localement (quantificateurs, ensembles, flèches…).
    var localSymbolCount: Int? = nil
    /// Symboles que la reconnaissance locale a laissés à Claude.
    var uncertainSymbolCount: Int? = nil
    /// Symboles appris (ajoutés à la bibliothèque locale) grâce à la lecture de Claude.
    var learnedSymbolCount: Int? = nil
}

// MARK: - Retour du tuteur

enum Verdict: String, Codable {
    case correct, partial, incorrect, unreadable
    case notApplicable = "none"

    var label: String {
        switch self {
        case .correct: return "Bonne réponse"
        case .partial: return "Partiellement correct"
        case .incorrect: return "Incorrect"
        case .unreadable: return "Illisible"
        case .notApplicable: return "Réponse"
        }
    }

    var pageStatus: PageStatus {
        switch self {
        case .correct: return .correct
        case .partial: return .partial
        case .incorrect: return .incorrect
        case .unreadable: return .unreadable
        case .notApplicable: return .drafting
        }
    }
}

struct Feedback: Codable, Equatable {
    var verdict: Verdict
    var message: String
    /// Comment Claude a lu la réponse (utile quand l'image a été analysée).
    var reading: String? = nil
    /// Question suivante proposée par le tuteur (si bonne réponse).
    var nextQuestion: String? = nil
    var usedImage: Bool = false
    var modelID: String
    var createdAt: Date = Date()
}

// MARK: - Messages de la discussion

enum MessageRole: String, Codable {
    case user, assistant
}

enum MessageKind: String, Codable {
    case chat       // discussion libre
    case question   // question posée par le tuteur
    case answer     // réponse manuscrite transcrite
    case feedback   // évaluation
    case hint       // indice
    case help       // demande d'aide sur la page
    case note       // note locale (erreur, information) jamais envoyée à l'API
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var role: MessageRole
    var kind: MessageKind = .chat
    /// Texte affiché à l'utilisateur.
    var text: String
    /// Texte exact échangé avec l'API quand il diffère de `text` (JSON structuré, consignes).
    var apiText: String? = nil
    var attachmentIDs: [UUID] = []
    var pageID: UUID? = nil
    var modelID: String? = nil
    var createdAt: Date = Date()
    var isError: Bool = false

    var textForAPI: String { apiText ?? text }
}

// MARK: - Pièces jointes (cours PDF, images, pages manuscrites)

enum AttachmentKind: String, Codable {
    case pdf, image, text

    static func from(filename: String) -> AttachmentKind? {
        switch (filename as NSString).pathExtension.lowercased() {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp": return .image
        case "txt", "md", "markdown", "tex", "csv": return .text
        default: return nil
        }
    }
}

struct Attachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var filename: String
    var kind: AttachmentKind
    var mediaType: String
    var byteCount: Int
    var createdAt: Date = Date()
    /// `true` pour les images de pages manuscrites générées par l'app.
    var isPageSnapshot: Bool = false
}
