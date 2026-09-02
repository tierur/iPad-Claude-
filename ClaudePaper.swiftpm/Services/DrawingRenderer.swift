import PencilKit
import UIKit

/// Image d'une page manuscrite prête à être envoyée à Claude.
struct PageSnapshot {
    let image: UIImage
    let jpegData: Data
    let mediaType = "image/jpeg"

    var base64: String { jpegData.base64EncodedString() }
}

enum DrawingRenderer {
    /// Rend les traits du dessin (encre noire sur fond blanc), recadrés sur la zone écrite,
    /// avec une dimension maximale adaptée à l'analyse d'image (1568 px conseillés).
    static func snapshot(of drawing: PKDrawing, maxDimension: CGFloat = 1568, padding: CGFloat = 28) -> PageSnapshot? {
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }

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

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let composed = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))
            strokesImage.draw(in: CGRect(origin: .zero, size: rect.size))
        }
        guard let data = composed.jpegData(compressionQuality: 0.85) else { return nil }
        return PageSnapshot(image: composed, jpegData: data)
    }
}
