import PencilKit
import UIKit

/// Image d'une page manuscrite prête à être envoyée à Claude.
struct PageSnapshot {
    let image: UIImage
    let jpegData: Data
    /// Zone du canevas rendue (coordonnées du dessin) : permet de relier l'image aux traits.
    let sourceRect: CGRect
    let scale: CGFloat
    let mediaType = "image/jpeg"

    var base64: String { jpegData.base64EncodedString() }
}

enum DrawingRenderer {
    /// Rend les traits du dessin (encre noire sur fond blanc), recadrés sur la zone écrite,
    /// avec une dimension maximale adaptée à l'analyse d'image (1568 px conseillés).
    static func snapshot(of drawing: PKDrawing, maxDimension: CGFloat = 1568, padding: CGFloat = 28) -> PageSnapshot? {
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds
        guard bounds.width > 0 || bounds.height > 0 else { return nil }

        var rect = bounds.insetBy(dx: -padding, dy: -padding)
        if rect.width < 480 {
            rect = CGRect(x: rect.midX - 240, y: rect.minY, width: 480, height: rect.height)
        }
        if rect.height < 160 {
            rect = CGRect(x: rect.minX, y: rect.midY - 80, width: rect.width, height: 160)
        }
        let longestSide = max(rect.width, rect.height)
        let scale = min(2.0, maxDimension / longestSide)

        // Force l'apparence claire : l'encre « noire » de PencilKit est dynamique en mode sombre.
        var strokesImage = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            strokesImage = drawing.image(from: rect, scale: scale)
        }

        let composed = render(size: rect.size, scale: scale) { _ in
            strokesImage.draw(in: CGRect(origin: .zero, size: rect.size))
        }
        guard let data = composed.jpegData(compressionQuality: 0.85) else { return nil }
        return PageSnapshot(image: composed, jpegData: data, sourceRect: rect, scale: scale)
    }

    /// Même image avec des cadres rouges numérotés (rectangles en coordonnées du dessin),
    /// pour demander à Claude ce que contient chaque cadre.
    static func annotate(_ snapshot: PageSnapshot, boxes: [(id: Int, rect: CGRect)]) -> PageSnapshot {
        let size = snapshot.sourceRect.size
        let composed = render(size: size, scale: snapshot.scale) { context in
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))
            let red = UIColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)
            context.setStrokeColor(red.cgColor)
            context.setLineWidth(2)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 15),
                .foregroundColor: UIColor.white
            ]
            for box in boxes {
                let frame = box.rect
                    .offsetBy(dx: -snapshot.sourceRect.minX, dy: -snapshot.sourceRect.minY)
                    .insetBy(dx: -6, dy: -6)
                context.stroke(frame)
                let label = "\(box.id)" as NSString
                let labelSize = label.size(withAttributes: attributes)
                let badge = CGRect(x: frame.minX, y: frame.minY - labelSize.height - 4,
                                   width: labelSize.width + 10, height: labelSize.height + 4)
                context.setFillColor(red.cgColor)
                context.fill(badge)
                label.draw(at: CGPoint(x: badge.minX + 5, y: badge.minY + 2), withAttributes: attributes)
            }
        }
        let data = composed.jpegData(compressionQuality: 0.85) ?? snapshot.jpegData
        return PageSnapshot(image: composed, jpegData: data, sourceRect: snapshot.sourceRect, scale: snapshot.scale)
    }

    private static func render(size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw(context.cgContext)
        }
    }
}
