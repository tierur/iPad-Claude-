import CoreGraphics
import Foundation
import PencilKit

/// Symbole reconnu localement et appliqué au texte.
struct SymbolMatch {
    let clusterID: Int
    let label: String
    let score: Double
    let fromSeed: Bool
}

/// Groupe de traits que la reconnaissance locale n'a pas su lire avec certitude.
struct UncertainCluster {
    let cluster: StrokeCluster
    /// Meilleure hypothèse locale, si elle est plausible.
    let guess: String?
}

/// Résultat de la reconnaissance locale (texte de l'iPad + symboles).
struct LocalRecognition {
    var text: String
    var ocrConfidence: Double
    var matches: [SymbolMatch]
    var uncertain: [UncertainCluster]
    var clusters: [StrokeCluster]
    var unit: CGFloat
    var candidateCount: Int

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Fusionne la reconnaissance de texte de l'iPad (mots, chiffres) avec la reconnaissance de symboles
/// par nuages de points (quantificateurs, ensembles, flèches, lettres grecques…).
enum LocalHandwritingEngine {
    /// Seuils d'acceptation d'un symbole (score $P dans [0, 1]).
    static let seedThreshold = 0.80
    static let learnedThreshold = 0.72
    static let margin = 0.05
    static let guessThreshold = 0.5

    private struct Cell {
        var text: String
        var frame: CGRect
        var confidence: Double
        var tokenText: String
        var tokenLength: Int
        /// Position dans la ligne OCR ; -1 pour une cellule insérée par la reconnaissance de symboles.
        var order: Int
    }

    private struct Line {
        var cells: [Cell]
        var frame: CGRect
        var isOCR: Bool
    }

    static func recognize(drawing: PKDrawing, snapshot: PageSnapshot, ocr: RecognitionResult?, templates: [SymbolTemplate]) -> LocalRecognition {
        let (clusters, unit) = StrokeSegmenter.clusters(from: drawing)
        var lines = ocrLines(from: ocr, snapshot: snapshot)
        var matches: [SymbolMatch] = []
        var uncertain: [UncertainCluster] = []
        var candidateCount = 0

        for cluster in clusters {
            // Points, accents, virgules : trop petits pour être des symboles.
            if cluster.bounds.width < 0.12 * unit, cluster.bounds.height < 0.12 * unit { continue }

            let coverage = coveringCells(for: cluster, in: lines)
            let covered = coverage.map { lines[$0.line].cells[$0.cell] }
            let coveredText = covered.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            let lowConfidence = !covered.isEmpty && covered.allSatisfy { $0.confidence < 0.5 }
            let shortToken = !covered.isEmpty && covered.allSatisfy { $0.tokenLength <= 2 }
            // Un fragment de mot bien lu par l'iPad n'est pas un candidat symbole.
            guard covered.isEmpty || lowConfidence || shortToken else { continue }
            candidateCount += 1

            guard let cloud = cluster.cloud else { continue }
            let (best, runnerUp) = classify(cloud, templates: templates)
            var accepted: SymbolMatch? = nil
            if let best {
                let threshold = best.fromSeed ? seedThreshold : learnedThreshold
                if best.score >= threshold, best.score - runnerUp >= margin {
                    let spec = SymbolCatalog.spec(for: best.label)
                    let standalone = covered.first.map { $0.tokenText == coveredText } ?? true
                    let gateOpen: Bool
                    if covered.isEmpty || lowConfidence {
                        gateOpen = true
                    } else {
                        gateOpen = spec.confusions.contains(coveredText) && (!spec.standaloneOnly || standalone)
                    }
                    if gateOpen {
                        accepted = SymbolMatch(clusterID: cluster.id, label: best.label, score: best.score, fromSeed: best.fromSeed)
                    }
                }
            }

            if let accepted {
                matches.append(accepted)
                apply(text: accepted.label, coverage: coverage, cluster: cluster, to: &lines, unit: unit)
            } else {
                let guess = (best?.score ?? 0) >= guessThreshold ? best?.label : nil
                uncertain.append(UncertainCluster(cluster: cluster, guess: guess))
                if covered.isEmpty {
                    apply(text: "[?]", coverage: [], cluster: cluster, to: &lines, unit: unit)
                }
            }
        }

        return LocalRecognition(text: assemble(lines, unit: unit),
                                ocrConfidence: ocr?.meanConfidence ?? 0,
                                matches: matches,
                                uncertain: uncertain,
                                clusters: clusters,
                                unit: unit,
                                candidateCount: candidateCount)
    }

    // MARK: - Classification

    private static func classify(_ cloud: PointCloud, templates: [SymbolTemplate]) -> (best: SymbolMatch?, runnerUp: Double) {
        var bestByLabel: [String: (score: Double, fromSeed: Bool)] = [:]
        for template in templates {
            let score = cloud.similarity(to: template.cloud)
            if let existing = bestByLabel[template.label], existing.score >= score { continue }
            bestByLabel[template.label] = (score, template.isSeed)
        }
        let ranked = bestByLabel.sorted { $0.value.score > $1.value.score }
        guard let top = ranked.first else { return (nil, 0) }
        let runnerUp = ranked.count > 1 ? ranked[1].value.score : 0
        return (SymbolMatch(clusterID: -1, label: top.key, score: top.value.score, fromSeed: top.value.fromSeed), runnerUp)
    }

    // MARK: - Lignes OCR en coordonnées du dessin

    private static func ocrLines(from ocr: RecognitionResult?, snapshot: PageSnapshot) -> [Line] {
        guard let ocr else { return [] }
        return ocr.lines.map { line in
            let tokens = tokenInfo(for: line.text)
            var cells: [Cell] = []
            for (index, character) in line.characters.enumerated() {
                let info = index < tokens.count ? tokens[index] : (text: "", length: 0)
                cells.append(Cell(text: character.text,
                                  frame: toDrawing(character.box, snapshot: snapshot),
                                  confidence: line.confidence,
                                  tokenText: info.text,
                                  tokenLength: info.length,
                                  order: index))
            }
            return Line(cells: cells, frame: toDrawing(line.box, snapshot: snapshot), isOCR: true)
        }
    }

    /// Pour chaque caractère de la ligne : le jeton (mot) auquel il appartient et sa longueur (0 pour un espace).
    private static func tokenInfo(for text: String) -> [(text: String, length: Int)] {
        var result: [(text: String, length: Int)] = []
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            if characters[index].isWhitespace {
                result.append((text: "", length: 0))
                index += 1
                continue
            }
            var end = index
            while end < characters.count, !characters[end].isWhitespace { end += 1 }
            let token = String(characters[index..<end])
            for _ in index..<end { result.append((text: token, length: token.count)) }
            index = end
        }
        return result
    }

    /// Convertit un rectangle normalisé Vision (origine en bas à gauche) en coordonnées du dessin.
    private static func toDrawing(_ box: CGRect, snapshot: PageSnapshot) -> CGRect {
        let source = snapshot.sourceRect
        return CGRect(x: source.minX + box.minX * source.width,
                      y: source.minY + (1 - box.maxY) * source.height,
                      width: box.width * source.width,
                      height: box.height * source.height)
    }

    // MARK: - Couverture et fusion

    private static func coveringCells(for cluster: StrokeCluster, in lines: [Line]) -> [(line: Int, cell: Int)] {
        var result: [(line: Int, cell: Int)] = []
        for (lineIndex, line) in lines.enumerated() where line.isOCR {
            guard line.frame.insetBy(dx: -4, dy: -4).intersects(cluster.bounds) else { continue }
            for (cellIndex, cell) in line.cells.enumerated() {
                guard cell.order >= 0, cell.text != " ", !cell.text.isEmpty else { continue }
                let horizontal = min(cell.frame.maxX, cluster.bounds.maxX) - max(cell.frame.minX, cluster.bounds.minX)
                let vertical = min(cell.frame.maxY, cluster.bounds.maxY) - max(cell.frame.minY, cluster.bounds.minY)
                let minWidth = max(1, min(cell.frame.width, cluster.bounds.width))
                let minHeight = max(1, min(cell.frame.height, cluster.bounds.height))
                if horizontal > 0.3 * minWidth, vertical > 0.3 * minHeight {
                    result.append((line: lineIndex, cell: cellIndex))
                }
            }
        }
        return result
    }

    private static func apply(text: String, coverage: [(line: Int, cell: Int)], cluster: StrokeCluster, to lines: inout [Line], unit: CGFloat) {
        if let first = coverage.first {
            lines[first.line].cells[first.cell].text = text
            lines[first.line].cells[first.cell].frame = lines[first.line].cells[first.cell].frame.union(cluster.bounds)
            for entry in coverage.dropFirst() {
                lines[entry.line].cells[entry.cell].text = ""
            }
            return
        }
        let cell = Cell(text: text, frame: cluster.bounds, confidence: 1, tokenText: text, tokenLength: text.count, order: -1)
        let centerY = cluster.bounds.midY
        // Ligne (OCR ou déjà créée) qui contient verticalement le symbole.
        var bestIndex: Int? = nil
        var bestOverlap: CGFloat = 0
        for (index, line) in lines.enumerated() {
            let overlap = min(line.frame.maxY, cluster.bounds.maxY) - max(line.frame.minY, cluster.bounds.minY)
            let contains = line.frame.minY - 0.3 * unit <= centerY && centerY <= line.frame.maxY + 0.3 * unit
            if contains, overlap > bestOverlap {
                bestOverlap = overlap
                bestIndex = index
            }
        }
        if let index = bestIndex {
            lines[index].cells.append(cell)
            lines[index].frame = lines[index].frame.union(cluster.bounds)
        } else {
            lines.append(Line(cells: [cell], frame: cluster.bounds, isOCR: false))
        }
    }

    private static func assemble(_ lines: [Line], unit: CGFloat) -> String {
        let ordered = lines.sorted { $0.frame.midY < $1.frame.midY }
        var output: [String] = []
        for line in ordered {
            let ocrCells = line.cells.filter { $0.order >= 0 }.sorted { $0.order < $1.order }
            let inserted = line.cells.filter { $0.order < 0 }.sorted { $0.frame.minX < $1.frame.minX }
            var merged: [Cell] = []
            var insertIndex = 0
            for cell in ocrCells {
                while insertIndex < inserted.count, inserted[insertIndex].frame.midX < cell.frame.midX {
                    merged.append(inserted[insertIndex])
                    insertIndex += 1
                }
                merged.append(cell)
            }
            while insertIndex < inserted.count {
                merged.append(inserted[insertIndex])
                insertIndex += 1
            }

            var text = ""
            var previous: Cell? = nil
            for cell in merged where !cell.text.isEmpty {
                if let previous, cell.text != " ", previous.text != " " {
                    let gap = cell.frame.minX - previous.frame.maxX
                    if gap > 0.25 * unit || cell.order < 0 || previous.order < 0 {
                        if gap > 0.12 * unit { text += " " }
                    }
                }
                text += cell.text
                previous = cell
            }
            let cleaned = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty { output.append(cleaned) }
        }
        return output.joined(separator: "\n")
    }
}
