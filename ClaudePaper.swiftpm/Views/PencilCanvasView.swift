import PencilKit
import SwiftUI
import UIKit

/// Canevas Apple Pencil défilant (la page s'allonge au fur et à mesure de l'écriture).
struct PencilCanvasView: UIViewRepresentable {
    var drawing: PKDrawing
    var reloadToken: Int
    var paperStyle: PaperStyle
    var allowFinger: Bool
    var showToolPicker: Bool
    var onChange: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> CanvasContainerView {
        let container = CanvasContainerView()
        container.canvas.delegate = context.coordinator
        container.canvas.drawing = drawing
        context.coordinator.lastToken = reloadToken
        return container
    }

    func updateUIView(_ container: CanvasContainerView, context: Context) {
        context.coordinator.onChange = onChange
        if context.coordinator.lastToken != reloadToken {
            context.coordinator.lastToken = reloadToken
            container.canvas.drawing = drawing
            container.updateContentSize()
            container.canvas.setContentOffset(.zero, animated: false)
        }
        container.canvas.drawingPolicy = allowFinger ? .anyInput : .pencilOnly
        container.paper.style = paperStyle
        container.setToolPickerVisible(showToolPicker)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onChange: (PKDrawing) -> Void
        var lastToken = Int.min

        init(onChange: @escaping (PKDrawing) -> Void) {
            self.onChange = onChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            (canvasView.superview as? CanvasContainerView)?.updateContentSize()
            onChange(canvasView.drawing)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            (scrollView.superview as? CanvasContainerView)?.paper.offset = scrollView.contentOffset
        }
    }
}

/// Conteneur : fond « papier » synchronisé avec le défilement + PKCanvasView transparent au-dessus.
final class CanvasContainerView: UIView {
    static let minimumPageHeight: CGFloat = 1800

    let paper = PaperBackgroundView()
    let canvas = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private var toolPickerVisible = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white

        paper.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        canvas.showsVerticalScrollIndicator = true
        canvas.drawingPolicy = .pencilOnly
        // Encre noire sur papier blanc, même quand l'iPad est en mode sombre.
        canvas.overrideUserInterfaceStyle = .light

        addSubview(paper)
        addSubview(canvas)
        NSLayoutConstraint.activate([
            paper.leadingAnchor.constraint(equalTo: leadingAnchor),
            paper.trailingAnchor.constraint(equalTo: trailingAnchor),
            paper.topAnchor.constraint(equalTo: topAnchor),
            paper.bottomAnchor.constraint(equalTo: bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) non pris en charge")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateContentSize()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, toolPickerVisible {
            toolPicker.setVisible(true, forFirstResponder: canvas)
            toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
        }
    }

    /// Allonge la page quand l'écriture approche du bas.
    func updateContentSize() {
        let width = bounds.width
        guard width > 0 else { return }
        let drawingBottom = canvas.drawing.strokes.isEmpty ? 0 : canvas.drawing.bounds.maxY
        let needed = max(Self.minimumPageHeight, bounds.height * 1.5, drawingBottom + 700)
        let size = CGSize(width: width, height: needed)
        if canvas.contentSize != size {
            canvas.contentSize = size
        }
    }

    func setToolPickerVisible(_ visible: Bool) {
        guard visible != toolPickerVisible else { return }
        toolPickerVisible = visible
        toolPicker.setVisible(visible, forFirstResponder: canvas)
        if visible {
            toolPicker.addObserver(canvas)
            if window != nil { canvas.becomeFirstResponder() }
        } else {
            toolPicker.removeObserver(canvas)
            canvas.resignFirstResponder()
        }
    }
}

/// Fond de page (blanc, lignes ou quadrillage) qui suit le défilement du canevas.
final class PaperBackgroundView: UIView {
    var style: PaperStyle = .lines {
        didSet { if style != oldValue { setNeedsDisplay() } }
    }

    var offset: CGPoint = .zero {
        didSet { if offset != oldValue { setNeedsDisplay() } }
    }

    private let spacing: CGFloat = 36
    private let marginX: CGFloat = 72

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) non pris en charge")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)
        guard style != .blank else { return }

        context.setLineWidth(1)
        context.setStrokeColor(UIColor(red: 0.62, green: 0.75, blue: 0.92, alpha: 0.55).cgColor)
        let phase = offset.y.truncatingRemainder(dividingBy: spacing)
        var y = -phase
        while y < bounds.height + spacing {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
            y += spacing
        }
        if style == .grid {
            var x: CGFloat = 0
            while x < bounds.width + spacing {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: bounds.height))
                x += spacing
            }
        }
        context.strokePath()

        if style == .lines {
            context.setStrokeColor(UIColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 0.6).cgColor)
            context.move(to: CGPoint(x: marginX, y: 0))
            context.addLine(to: CGPoint(x: marginX, y: bounds.height))
            context.strokePath()
        }
    }
}
