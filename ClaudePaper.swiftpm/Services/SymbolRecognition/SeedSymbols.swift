import CoreGraphics
import Foundation

/// Gabarits de départ, dessinés « à la règle » dans un carré unité (y vers le bas).
/// Ils amorcent la reconnaissance ; les vrais exemples de l'utilisateur, étiquetés par Claude,
/// les complètent ensuite (voir `SymbolLibrary.learn`).
enum SeedSymbols {
    static let templates: [SymbolTemplate] = {
        var result: [SymbolTemplate] = []
        for (label, variants) in shapes {
            for strokes in variants {
                if let cloud = PointCloud(strokes: strokes) {
                    result.append(SymbolTemplate(label: label, cloud: cloud, strokeCount: strokes.count, isSeed: true))
                }
            }
        }
        return result
    }()

    // MARK: - Primitives

    private static func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private static func line(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] { [a, b] }

    private static func poly(_ points: CGPoint...) -> [CGPoint] { points }

    /// Arc d'ellipse centré en (cx, cy), angles en degrés (0° à droite, 90° en bas car y descend).
    private static func arc(cx: Double, cy: Double, rx: Double, ry: Double, from: Double, to: Double, steps: Int = 14) -> [CGPoint] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let angle = (from + (to - from) * t) * Double.pi / 180
            return CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle))
        }
    }

    private static func circle(cx: Double, cy: Double, r: Double) -> [CGPoint] {
        arc(cx: cx, cy: cy, rx: r, ry: r, from: 0, to: 360, steps: 24)
    }

    /// Lemniscate (∞).
    private static func lemniscate() -> [CGPoint] {
        (0...40).map { i in
            let t = Double(i) / 40 * 2 * Double.pi
            let denominator = 1 + sin(t) * sin(t)
            return CGPoint(x: 0.5 + 0.5 * cos(t) / denominator, y: 0.5 + 0.5 * sin(t) * cos(t) / denominator)
        }
    }

    // MARK: - Formes (chaque symbole peut avoir plusieurs variantes de tracé)

    private static let shapes: [(String, [[[CGPoint]]])] = [
        ("∀", [
            [poly(p(0, 0), p(0.45, 1), p(0.9, 0)), line(p(0.18, 0.4), p(0.72, 0.4))],
            [line(p(0, 0), p(0.45, 1)), line(p(0.45, 1), p(0.9, 0)), line(p(0.18, 0.4), p(0.72, 0.4))],
        ]),
        ("∃", [
            [poly(p(0, 0), p(0.8, 0), p(0.8, 1), p(0, 1)), line(p(0.15, 0.5), p(0.8, 0.5))],
            [line(p(0, 0), p(0.8, 0)), line(p(0.8, 0), p(0.8, 1)), line(p(0.8, 1), p(0, 1)), line(p(0.15, 0.5), p(0.8, 0.5))],
        ]),
        ("∈", [
            [arc(cx: 0.55, cy: 0.5, rx: 0.5, ry: 0.5, from: 70, to: 290, steps: 16), line(p(0.1, 0.5), p(1, 0.5))],
            [poly(p(1, 0), p(0.1, 0), p(0, 0.5), p(0.1, 1), p(1, 1)), line(p(0.05, 0.5), p(1, 0.5))],
        ]),
        ("∉", [
            [arc(cx: 0.55, cy: 0.5, rx: 0.5, ry: 0.5, from: 70, to: 290, steps: 16), line(p(0.1, 0.5), p(1, 0.5)), line(p(0.75, 0), p(0.3, 1))],
        ]),
        ("⊂", [
            [arc(cx: 0.6, cy: 0.5, rx: 0.55, ry: 0.5, from: 80, to: 280, steps: 18)],
        ]),
        ("⊃", [
            [arc(cx: 0.4, cy: 0.5, rx: 0.55, ry: 0.5, from: -100, to: 100, steps: 18)],
        ]),
        ("⊆", [
            [arc(cx: 0.6, cy: 0.4, rx: 0.5, ry: 0.4, from: 80, to: 280, steps: 18), line(p(0.15, 1), p(1, 1))],
        ]),
        ("∪", [
            [Array([p(0, 0)] + arc(cx: 0.5, cy: 0.6, rx: 0.5, ry: 0.4, from: 180, to: 0, steps: 12) + [p(1, 0)])],
        ]),
        ("∩", [
            [Array([p(0, 1)] + arc(cx: 0.5, cy: 0.4, rx: 0.5, ry: 0.4, from: 180, to: 360, steps: 12) + [p(1, 1)])],
        ]),
        ("∅", [
            [circle(cx: 0.5, cy: 0.5, r: 0.42), line(p(0.85, 0), p(0.15, 1))],
        ]),
        ("⇒", [
            [line(p(0, 0.35), p(0.8, 0.35)), line(p(0, 0.65), p(0.8, 0.65)), poly(p(0.6, 0.1), p(1, 0.5), p(0.6, 0.9))],
            [line(p(0, 0.35), p(0.8, 0.35)), line(p(0, 0.65), p(0.8, 0.65)), line(p(0.6, 0.1), p(1, 0.5)), line(p(1, 0.5), p(0.6, 0.9))],
        ]),
        ("⇔", [
            [line(p(0.15, 0.35), p(0.85, 0.35)), line(p(0.15, 0.65), p(0.85, 0.65)), poly(p(0.35, 0.1), p(0, 0.5), p(0.35, 0.9)), poly(p(0.65, 0.1), p(1, 0.5), p(0.65, 0.9))],
        ]),
        ("→", [
            [line(p(0, 0.5), p(1, 0.5)), poly(p(0.7, 0.15), p(1, 0.5), p(0.7, 0.85))],
            [poly(p(0, 0.5), p(1, 0.5), p(0.7, 0.15)), line(p(1, 0.5), p(0.7, 0.85))],
        ]),
        ("↦", [
            [line(p(0, 0.5), p(1, 0.5)), poly(p(0.7, 0.15), p(1, 0.5), p(0.7, 0.85)), line(p(0, 0.1), p(0, 0.9))],
        ]),
        ("≤", [
            [poly(p(1, 0.05), p(0.05, 0.42), p(1, 0.78)), line(p(0.05, 1), p(1, 1))],
        ]),
        ("≥", [
            [poly(p(0, 0.05), p(0.95, 0.42), p(0, 0.78)), line(p(0, 1), p(0.95, 1))],
        ]),
        ("≠", [
            [line(p(0, 0.35), p(1, 0.35)), line(p(0, 0.65), p(1, 0.65)), line(p(0.7, 0), p(0.3, 1))],
        ]),
        ("≈", [
            [Array(arc(cx: 0.25, cy: 0.35, rx: 0.25, ry: 0.12, from: 180, to: 360, steps: 8) + arc(cx: 0.75, cy: 0.35, rx: 0.25, ry: 0.12, from: 180, to: 0, steps: 8)),
             Array(arc(cx: 0.25, cy: 0.7, rx: 0.25, ry: 0.12, from: 180, to: 360, steps: 8) + arc(cx: 0.75, cy: 0.7, rx: 0.25, ry: 0.12, from: 180, to: 0, steps: 8))],
        ]),
        ("∞", [
            [lemniscate()],
        ]),
        ("±", [
            [line(p(0.5, 0), p(0.5, 0.7)), line(p(0, 0.35), p(1, 0.35)), line(p(0, 1), p(1, 1))],
        ]),
        ("√", [
            [poly(p(0, 0.6), p(0.28, 1), p(0.55, 0), p(1, 0))],
        ]),
        ("∑", [
            [poly(p(1, 0), p(0, 0), p(0.55, 0.5), p(0, 1), p(1, 1))],
        ]),
        ("∫", [
            [poly(p(0.9, 0.1), p(0.75, 0), p(0.6, 0.05), p(0.5, 0.2), p(0.5, 0.8), p(0.4, 0.95), p(0.25, 1), p(0.1, 0.9))],
        ]),
        ("∧", [
            [poly(p(0, 1), p(0.5, 0), p(1, 1))],
        ]),
        ("∨", [
            [poly(p(0, 0), p(0.5, 1), p(1, 0))],
        ]),
        ("¬", [
            [poly(p(0, 0.3), p(1, 0.3), p(1, 0.9))],
        ]),
        ("ε", [
            [poly(p(1, 0.1), p(0.55, 0), p(0.1, 0.25), p(0.55, 0.5), p(0.1, 0.75), p(0.55, 1), p(1, 0.9))],
            [Array(arc(cx: 0.55, cy: 0.25, rx: 0.45, ry: 0.25, from: -40, to: 180, steps: 8) + arc(cx: 0.55, cy: 0.75, rx: 0.45, ry: 0.25, from: 180, to: 400, steps: 8))],
        ]),
        ("δ", [
            [Array(poly(p(0.9, 0), p(0.55, 0.05), p(0.4, 0.3), p(0.55, 0.45)) + circle(cx: 0.5, cy: 0.72, r: 0.28))],
        ]),
        ("α", [
            [poly(p(1, 0.15), p(0.6, 0.5), p(0.35, 0.85), p(0.15, 0.85), p(0.05, 0.55), p(0.15, 0.2), p(0.35, 0.15), p(0.6, 0.5), p(1, 0.85))],
        ]),
        ("β", [
            [poly(p(0.05, 1), p(0.1, 0.1), p(0.45, 0), p(0.7, 0.15), p(0.6, 0.4), p(0.35, 0.45), p(0.75, 0.55), p(0.85, 0.8), p(0.6, 0.95), p(0.3, 0.85))],
        ]),
        ("λ", [
            [poly(p(0.1, 0), p(0.45, 0.35), p(1, 1)), line(p(0.55, 0.5), p(0, 1))],
        ]),
        ("μ", [
            [poly(p(0.1, 1), p(0.15, 0.3), p(0.15, 0.75), p(0.5, 0.85), p(0.8, 0.6), p(0.85, 0.3), p(0.9, 0.85))],
        ]),
        ("π", [
            [line(p(0, 0.25), p(1, 0.2)), line(p(0.25, 0.25), p(0.2, 1)), poly(p(0.7, 0.25), p(0.7, 0.9), p(0.9, 1))],
        ]),
        ("θ", [
            [arc(cx: 0.5, cy: 0.5, rx: 0.35, ry: 0.5, from: 0, to: 360, steps: 20), line(p(0.15, 0.5), p(0.85, 0.5))],
        ]),
        ("ω", [
            [poly(p(0, 0.3), p(0.05, 0.9), p(0.3, 1), p(0.5, 0.6), p(0.7, 1), p(0.95, 0.9), p(1, 0.3))],
        ]),
        ("φ", [
            [arc(cx: 0.5, cy: 0.5, rx: 0.4, ry: 0.3, from: 0, to: 360, steps: 16), line(p(0.5, 0), p(0.5, 1))],
        ]),
        ("∂", [
            [Array(arc(cx: 0.5, cy: 0.65, rx: 0.4, ry: 0.35, from: -60, to: 300, steps: 14) + poly(p(0.85, 0.3), p(0.7, 0.05), p(0.3, 0)))],
        ]),
        ("∘", [
            [circle(cx: 0.5, cy: 0.5, r: 0.5)],
        ]),
        ("×", [
            [line(p(0, 0), p(1, 1)), line(p(1, 0), p(0, 1))],
        ]),
    ]
}
