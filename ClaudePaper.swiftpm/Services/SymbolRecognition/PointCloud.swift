import CoreGraphics
import Foundation

/// Nuage de points normalisé pour la reconnaissance de symboles manuscrits
/// (algorithme $P — Vatavu, Anthony & Wobbrock, 2012 : indépendant du nombre,
/// de l'ordre et du sens des traits).
struct PointCloud: Codable, Equatable {
    static let sampleCount = 32

    /// Points rééchantillonnés, centrés sur leur barycentre, plus grande dimension = 1.
    var points: [CGPoint]
    /// Largeur / hauteur d'origine (sert à pénaliser les formes de proportions très différentes).
    var aspect: Double

    init?(strokes: [[CGPoint]]) {
        let cleaned = strokes.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        let resampled = Self.resample(cleaned, count: Self.sampleCount)
        guard resampled.count == Self.sampleCount else { return nil }
        let (scaled, aspect) = Self.scale(resampled)
        points = Self.translateToCentroid(scaled)
        self.aspect = aspect
    }

    // MARK: - Comparaison

    /// Score de similarité dans [0, 1] (1 = identique).
    func similarity(to other: PointCloud) -> Double {
        let distance = Self.greedyCloudMatch(points, other.points)
        var score = max(0, 1 - distance / 2)
        // Proportions très différentes (par exemple « − » et « | ») : pénalité.
        let ratio = abs(log(max(aspect, 0.05) / max(other.aspect, 0.05)))
        if ratio > log(2.2) {
            score -= 0.2
        } else if ratio > log(1.6) {
            score -= 0.08
        }
        return max(0, score)
    }

    private static func greedyCloudMatch(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        let n = a.count
        guard n > 0, b.count == n else { return .infinity }
        let step = max(1, Int(pow(Double(n), 0.5).rounded(.down)))
        var minimum = Double.infinity
        var start = 0
        while start < n {
            minimum = min(minimum, cloudDistance(a, b, start: start))
            minimum = min(minimum, cloudDistance(b, a, start: start))
            start += step
        }
        return minimum
    }

    private static func cloudDistance(_ a: [CGPoint], _ b: [CGPoint], start: Int) -> Double {
        let n = a.count
        var matched = [Bool](repeating: false, count: n)
        var sum = 0.0
        var i = start
        repeat {
            var index = -1
            var minDistance = Double.infinity
            for j in 0..<n where !matched[j] {
                let d = distance(a[i], b[j])
                if d < minDistance {
                    minDistance = d
                    index = j
                }
            }
            if index >= 0 { matched[index] = true }
            let weight = 1 - Double((i - start + n) % n) / Double(n)
            sum += weight * minDistance
            i = (i + 1) % n
        } while i != start
        return sum
    }

    // MARK: - Normalisation

    static func distance(_ p: CGPoint, _ q: CGPoint) -> Double {
        let dx = Double(p.x - q.x)
        let dy = Double(p.y - q.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func pathLength(_ points: [CGPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            total += distance(points[i - 1], points[i])
        }
        return total
    }

    /// Rééchantillonne l'ensemble des traits en `count` points, répartis proportionnellement à leur longueur.
    static func resample(_ strokes: [[CGPoint]], count: Int) -> [CGPoint] {
        let lengths = strokes.map { pathLength($0) }
        let total = lengths.reduce(0, +)
        var result: [CGPoint] = []
        if total < 0.001 {
            // Uniquement des points (tirets minuscules, points) : on répète les positions.
            let per = max(1, count / strokes.count)
            for stroke in strokes {
                result.append(contentsOf: Array(repeating: stroke[0], count: per))
            }
            while result.count < count { result.append(strokes[0][0]) }
            return Array(result.prefix(count))
        }
        var counts = lengths.map { max(1, Int(($0 / total * Double(count)).rounded())) }
        var difference = count - counts.reduce(0, +)
        while difference != 0 {
            if difference > 0 {
                let index = lengths.indices.max { lengths[$0] < lengths[$1] } ?? 0
                counts[index] += 1
                difference -= 1
            } else {
                let index = counts.indices.max { counts[$0] < counts[$1] } ?? 0
                if counts[index] > 1 {
                    counts[index] -= 1
                    difference += 1
                } else {
                    break
                }
            }
        }
        for (stroke, n) in zip(strokes, counts) {
            result.append(contentsOf: resampleStroke(stroke, count: n))
        }
        while result.count < count { result.append(result.last ?? strokes[0][0]) }
        return Array(result.prefix(count))
    }

    static func resampleStroke(_ original: [CGPoint], count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        guard original.count > 1, count > 1 else {
            return Array(repeating: original[0], count: count)
        }
        let interval = pathLength(original) / Double(count - 1)
        guard interval > 0 else { return Array(repeating: original[0], count: count) }
        var points = original
        var result = [points[0]]
        var accumulated = 0.0
        var i = 1
        while i < points.count {
            let d = distance(points[i - 1], points[i])
            if accumulated + d >= interval, d > 0 {
                let t = CGFloat((interval - accumulated) / d)
                let q = CGPoint(x: points[i - 1].x + t * (points[i].x - points[i - 1].x),
                                y: points[i - 1].y + t * (points[i].y - points[i - 1].y))
                result.append(q)
                points.insert(q, at: i)
                accumulated = 0
            } else {
                accumulated += d
            }
            i += 1
        }
        while result.count < count { result.append(original[original.count - 1]) }
        return Array(result.prefix(count))
    }

    private static func scale(_ points: [CGPoint]) -> ([CGPoint], Double) {
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        let width = maxX - minX
        let height = maxY - minY
        let size = max(width, height)
        let aspect = height > 0.001 ? Double(width / height) : (width > 0.001 ? 20 : 1)
        guard size > 0.001 else { return (points, aspect) }
        return (points.map { CGPoint(x: ($0.x - minX) / size, y: ($0.y - minY) / size) }, aspect)
    }

    private static func translateToCentroid(_ points: [CGPoint]) -> [CGPoint] {
        guard !points.isEmpty else { return points }
        let n = CGFloat(points.count)
        let cx = points.reduce(0) { $0 + $1.x } / n
        let cy = points.reduce(0) { $0 + $1.y } / n
        return points.map { CGPoint(x: $0.x - cx, y: $0.y - cy) }
    }
}
