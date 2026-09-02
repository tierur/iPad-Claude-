import CoreGraphics
import Foundation
import PencilKit

/// Groupe de traits formant (probablement) un symbole ou un fragment de mot.
struct StrokeCluster: Identifiable {
    let id: Int
    /// Points de chaque trait, en coordonnées du canevas.
    var strokes: [[CGPoint]]
    var bounds: CGRect
    /// Ordre de création du premier trait.
    var order: Int

    var cloud: PointCloud? { PointCloud(strokes: strokes) }
}

/// Découpe le dessin en groupes de traits proches (tracés consécutivement).
enum StrokeSegmenter {
    struct SampledStroke {
        let points: [CGPoint]
        let bounds: CGRect
        let order: Int
    }

    static func strokes(from drawing: PKDrawing) -> [SampledStroke] {
        var result: [SampledStroke] = []
        for (index, stroke) in drawing.strokes.enumerated() {
            let transform = stroke.transform
            var points: [CGPoint] = []
            for point in stroke.path.interpolatedPoints(by: .distance(2)) {
                points.append(point.location.applying(transform))
            }
            if points.isEmpty, let first = stroke.path.first {
                points = [first.location.applying(transform)]
            }
            guard !points.isEmpty else { continue }
            result.append(SampledStroke(points: points, bounds: stroke.renderBounds, order: index))
        }
        return result
    }

    /// Hauteur de référence d'un caractère (médiane des hauteurs de traits), bornée.
    static func unit(for strokes: [SampledStroke]) -> CGFloat {
        let heights = strokes.map { max($0.bounds.height, $0.bounds.width * 0.6) }.filter { $0 > 4 }.sorted()
        guard !heights.isEmpty else { return 30 }
        let median = heights[heights.count / 2]
        return min(max(median, 14), 90)
    }

    static func clusters(from drawing: PKDrawing) -> (clusters: [StrokeCluster], unit: CGFloat) {
        let sampled = strokes(from: drawing)
        let unit = unit(for: sampled)
        var clusters: [StrokeCluster] = []
        for stroke in sampled {
            if let lastIndex = clusters.indices.last, shouldMerge(stroke, into: clusters[lastIndex], unit: unit) {
                clusters[lastIndex].strokes.append(stroke.points)
                clusters[lastIndex].bounds = clusters[lastIndex].bounds.union(stroke.bounds)
            } else if clusters.count >= 2,
                      stroke.bounds.intersects(clusters[clusters.count - 2].bounds.insetBy(dx: -0.05 * unit, dy: -0.05 * unit)),
                      stroke.order - clusters[clusters.count - 1].order <= 2 {
                // Trait ajouté après coup sur le symbole précédent (barre d'un ∀, point d'un i…).
                let index = clusters.count - 2
                clusters[index].strokes.append(stroke.points)
                clusters[index].bounds = clusters[index].bounds.union(stroke.bounds)
            } else {
                clusters.append(StrokeCluster(id: clusters.count, strokes: [stroke.points], bounds: stroke.bounds, order: stroke.order))
            }
        }
        return (clusters, unit)
    }

    private static func shouldMerge(_ stroke: SampledStroke, into cluster: StrokeCluster, unit: CGFloat) -> Bool {
        let horizontalGap = max(stroke.bounds.minX - cluster.bounds.maxX, cluster.bounds.minX - stroke.bounds.maxX)
        let verticalGap = max(stroke.bounds.minY - cluster.bounds.maxY, cluster.bounds.minY - stroke.bounds.maxY)
        // Traits qui se chevauchent ou presque horizontalement, et sur la même hauteur.
        return horizontalGap < 0.12 * unit && verticalGap < 0.45 * unit
    }
}
