import Foundation
import UIKit
import Vision

struct RecognizedCharacter {
    let text: String
    /// Rectangle normalisé (origine en bas à gauche, convention Vision).
    let box: CGRect
}

struct RecognizedLine {
    let text: String
    let confidence: Double
    /// Rectangle normalisé de la ligne (convention Vision).
    let box: CGRect
    /// Caractères avec leur position (même ordre que `text`).
    let characters: [RecognizedCharacter]
}

struct RecognitionResult {
    let lines: [RecognizedLine]

    var text: String { lines.map(\.text).joined(separator: "\n") }

    var meanConfidence: Double {
        guard !lines.isEmpty else { return 0 }
        return lines.map(\.confidence).reduce(0, +) / Double(lines.count)
    }
}

enum RecognitionError: LocalizedError {
    case invalidImage

    var errorDescription: String? { "Image illisible pour la reconnaissance." }
}

/// Reconnaissance de texte manuscrit sur l'iPad (framework Vision), français puis anglais.
enum HandwritingRecognizer {
    static func recognize(_ image: UIImage, mathMode: Bool) async throws -> RecognitionResult {
        guard let cgImage = image.cgImage else { throw RecognitionError.invalidImage }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // La correction linguistique « répare » les formules en mots : on la coupe pour les maths.
            request.usesLanguageCorrection = !mathMode
            request.automaticallyDetectsLanguage = false
            let wanted = ["fr-FR", "en-US"]
            if let supported = try? request.supportedRecognitionLanguages() {
                let filtered = wanted.filter { supported.contains($0) }
                request.recognitionLanguages = filtered.isEmpty ? wanted : filtered
            } else {
                request.recognitionLanguages = wanted
            }
            if mathMode {
                request.customWords = ["lim", "sup", "inf", "sin", "cos", "exp", "ln", "ouvert", "fermé", "compact", "voisinage", "borné", "continue"]
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            var lines: [RecognizedLine] = []
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let string = candidate.string
                var characters: [RecognizedCharacter] = []
                var index = string.startIndex
                var previousBox = observation.boundingBox
                while index < string.endIndex {
                    let next = string.index(after: index)
                    let range = index..<next
                    let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? previousBox
                    characters.append(RecognizedCharacter(text: String(string[range]), box: box))
                    previousBox = box
                    index = next
                }
                lines.append(RecognizedLine(text: string,
                                            confidence: Double(candidate.confidence),
                                            box: observation.boundingBox,
                                            characters: characters))
            }
            // Ordre de lecture : de haut en bas (Vision a l'origine en bas), puis de gauche à droite.
            let sorted = lines.sorted { lhs, rhs in
                let sameRow = abs(lhs.box.midY - rhs.box.midY) < min(lhs.box.height, rhs.box.height) * 0.6
                if sameRow { return lhs.box.minX < rhs.box.minX }
                return lhs.box.midY > rhs.box.midY
            }
            return RecognitionResult(lines: sorted)
        }.value
    }
}
