import Combine
import Foundation

/// Gabarit d'un symbole manuscrit (nuage de points + étiquette).
struct SymbolTemplate: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var label: String
    var cloud: PointCloud
    var strokeCount: Int
    var isSeed: Bool
    var createdAt: Date = Date()
}

/// Métadonnées d'un symbole : lectures OCR qu'il remplace, et s'il doit être isolé pour remplacer une lettre.
struct SymbolSpec {
    /// Ce que la reconnaissance de texte de l'iPad écrit souvent à la place du symbole.
    var confusions: Set<String>
    /// Symbole ambigu avec une lettre (⊂ / C, ∪ / U…) : ne remplace qu'un jeton isolé.
    var standaloneOnly: Bool
}

enum SymbolCatalog {
    static let specs: [String: SymbolSpec] = [
        "∀": SymbolSpec(confusions: ["A", "V", "Y", "∀", "H", "N", "y"], standaloneOnly: false),
        "∃": SymbolSpec(confusions: ["E", "3", "∃", "Ǝ", "F", "e"], standaloneOnly: false),
        "∃!": SymbolSpec(confusions: ["E!", "3!", "∃!"], standaloneOnly: false),
        "∈": SymbolSpec(confusions: ["E", "€", "e", "C", "c", "∈", "є", "ε", "6", "G"], standaloneOnly: true),
        "∉": SymbolSpec(confusions: ["€", "∉", "E", "e"], standaloneOnly: true),
        "⊂": SymbolSpec(confusions: ["C", "c", "(", "⊂", "<"], standaloneOnly: true),
        "⊃": SymbolSpec(confusions: [")", "⊃", ">", "D"], standaloneOnly: true),
        "⊆": SymbolSpec(confusions: ["C", "c", "⊆", "≤"], standaloneOnly: true),
        "∪": SymbolSpec(confusions: ["U", "u", "∪", "V", "v"], standaloneOnly: true),
        "∩": SymbolSpec(confusions: ["n", "∩", "N", "A"], standaloneOnly: true),
        "∅": SymbolSpec(confusions: ["0", "Ø", "ø", "φ", "∅", "O", "o", "Q", "%"], standaloneOnly: false),
        "⇒": SymbolSpec(confusions: ["=>", "->", "⇒", "=", "-", "–", ">"], standaloneOnly: false),
        "⇔": SymbolSpec(confusions: ["<=>", "⇔", "=", "<>", "<->"], standaloneOnly: false),
        "→": SymbolSpec(confusions: ["->", "→", "-", "–", "—", ">"], standaloneOnly: false),
        "↦": SymbolSpec(confusions: ["->", "↦", "|->", "-"], standaloneOnly: false),
        "≤": SymbolSpec(confusions: ["<", "≤", "<=", "s", "S", "≦"], standaloneOnly: false),
        "≥": SymbolSpec(confusions: [">", "≥", ">=", "2", "≧"], standaloneOnly: false),
        "≠": SymbolSpec(confusions: ["≠", "=", "+", "#", "≢", "≒"], standaloneOnly: false),
        "≈": SymbolSpec(confusions: ["≈", "=", "~", "≃", "~~"], standaloneOnly: false),
        "∞": SymbolSpec(confusions: ["oo", "∞", "co", "00", "8", "x", "∝"], standaloneOnly: false),
        "±": SymbolSpec(confusions: ["+", "±", "+-", "t"], standaloneOnly: false),
        "×": SymbolSpec(confusions: ["*", "×"], standaloneOnly: true),
        "√": SymbolSpec(confusions: ["√", "V", "v", "r", "J"], standaloneOnly: false),
        "∑": SymbolSpec(confusions: ["E", "∑", "Σ", "Z", "5", "S"], standaloneOnly: true),
        "∫": SymbolSpec(confusions: ["∫", "S", "s", "f", "J", "l", "|"], standaloneOnly: true),
        "∧": SymbolSpec(confusions: ["^", "∧", "A", "n"], standaloneOnly: true),
        "∨": SymbolSpec(confusions: ["v", "∨", "V", "u"], standaloneOnly: true),
        "¬": SymbolSpec(confusions: ["¬", "-", "7", "٦", "_"], standaloneOnly: false),
        "ε": SymbolSpec(confusions: ["E", "e", "ε", "€", "ɛ", "3", "£"], standaloneOnly: true),
        "δ": SymbolSpec(confusions: ["d", "δ", "S", "8", "б", "s", "&"], standaloneOnly: true),
        "α": SymbolSpec(confusions: ["a", "α", "x", "d", "∝"], standaloneOnly: true),
        "β": SymbolSpec(confusions: ["B", "β", "b", "ß", "13"], standaloneOnly: true),
        "λ": SymbolSpec(confusions: ["λ", "l", "1", "x", "A", "^"], standaloneOnly: true),
        "μ": SymbolSpec(confusions: ["u", "μ", "µ", "M", "m"], standaloneOnly: true),
        "π": SymbolSpec(confusions: ["π", "n", "TT", "T", "П"], standaloneOnly: true),
        "θ": SymbolSpec(confusions: ["θ", "0", "O", "Q", "e", "ø"], standaloneOnly: true),
        "ω": SymbolSpec(confusions: ["w", "ω", "W"], standaloneOnly: true),
        "φ": SymbolSpec(confusions: ["φ", "0", "Ø", "p", "P", "q"], standaloneOnly: true),
        "ℝ": SymbolSpec(confusions: ["IR", "R", "ℝ", "|R", "1R", "IP"], standaloneOnly: true),
        "ℕ": SymbolSpec(confusions: ["IN", "N", "ℕ", "|N", "1N"], standaloneOnly: true),
        "ℤ": SymbolSpec(confusions: ["Z", "ℤ", "7", "2"], standaloneOnly: true),
        "ℚ": SymbolSpec(confusions: ["Q", "ℚ", "O", "0"], standaloneOnly: true),
        "ℂ": SymbolSpec(confusions: ["C", "ℂ", "(", "c"], standaloneOnly: true),
        "∂": SymbolSpec(confusions: ["∂", "d", "a", "6", "ə"], standaloneOnly: true),
        "∇": SymbolSpec(confusions: ["V", "∇", "v", "7"], standaloneOnly: true),
        "∘": SymbolSpec(confusions: ["o", "∘", "0", "O", "°"], standaloneOnly: true),
        "·": SymbolSpec(confusions: [".", "·", "•", ","], standaloneOnly: true),
        "‖": SymbolSpec(confusions: ["||", "‖", "11", "ll", "II"], standaloneOnly: false),
        "⟶": SymbolSpec(confusions: ["-->", "→", "->", "—"], standaloneOnly: false),
    ]

    static let defaultSpec = SymbolSpec(confusions: [], standaloneOnly: true)

    static func spec(for label: String) -> SymbolSpec {
        specs[label] ?? defaultSpec
    }
}

/// Bibliothèque de gabarits : symboles de départ (synthétiques) + symboles appris à partir des lectures de Claude.
@MainActor
final class SymbolLibrary: ObservableObject {
    static let maxTemplatesPerLabel = 20

    @Published private(set) var learned: [SymbolTemplate] = []
    let seeds: [SymbolTemplate]

    private let fileURL: URL
    private var saveTask: Task<Void, Never>? = nil

    var all: [SymbolTemplate] { seeds + learned }

    /// Étiquettes apprises avec leur nombre d'exemples, les plus fréquentes d'abord.
    var learnedCounts: [(label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for template in learned { counts[template.label, default: 0] += 1 }
        return counts.map { (label: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }
    }

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = documents.appendingPathComponent("ClaudePaper/Symbols", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("learned.json")
        seeds = SeedSymbols.templates
        load()
    }

    /// Ajoute un exemple manuscrit pour `label` (au plus `maxTemplatesPerLabel`, les plus anciens sont remplacés).
    func learn(label: String, cloud: PointCloud, strokeCount: Int) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isLearnable(trimmed) else { return }
        var forLabel = learned.filter { $0.label == trimmed }
        if forLabel.count >= Self.maxTemplatesPerLabel {
            forLabel.sort { $0.createdAt < $1.createdAt }
            let oldest = forLabel[0]
            learned.removeAll { $0.id == oldest.id }
        }
        learned.append(SymbolTemplate(label: trimmed, cloud: cloud, strokeCount: strokeCount, isSeed: false))
        scheduleSave()
    }

    func reset() {
        learned = []
        scheduleSave()
    }

    /// Une étiquette apprenable : un symbole ou un très court jeton, sans espace ni marqueur d'incertitude.
    static func isLearnable(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 4 else { return false }
        guard !label.contains(where: { $0.isWhitespace || $0.isNewline }) else { return false }
        guard !label.contains("?"), !label.contains("["), !label.contains("]") else { return false }
        return true
    }

    // MARK: - Persistance

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let templates = try? decoder.decode([SymbolTemplate].self, from: data) {
            learned = templates
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = learned
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
