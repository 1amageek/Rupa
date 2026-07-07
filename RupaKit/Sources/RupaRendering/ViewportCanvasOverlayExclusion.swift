import CoreGraphics

public struct ViewportCanvasFittingEdges: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let top = ViewportCanvasFittingEdges(rawValue: 1 << 0)
    public static let leading = ViewportCanvasFittingEdges(rawValue: 1 << 1)
    public static let bottom = ViewportCanvasFittingEdges(rawValue: 1 << 2)
    public static let trailing = ViewportCanvasFittingEdges(rawValue: 1 << 3)
}

public struct ViewportCanvasOverlayExclusion: Equatable, Sendable {
    public var rect: CGRect
    public var fittingEdges: ViewportCanvasFittingEdges

    public init(
        rect: CGRect,
        fittingEdges: ViewportCanvasFittingEdges = []
    ) {
        self.rect = rect
        self.fittingEdges = fittingEdges
    }
}

extension ViewportCanvasOverlayExclusion {
    var hasFiniteRect: Bool {
        rect.hasFiniteComponents
    }

    func clamped(to viewportSize: CGSize, padding: CGFloat) -> ViewportCanvasOverlayExclusion? {
        guard hasFiniteRect,
              viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              viewportSize.width > 0.0,
              viewportSize.height > 0.0 else {
            return nil
        }

        let paddedRect = rect.insetBy(dx: -padding, dy: -padding)
        guard paddedRect.hasFiniteComponents else {
            return nil
        }

        let bounds = CGRect(origin: .zero, size: viewportSize)
        let intersection = paddedRect.intersection(bounds)
        guard intersection.hasFiniteComponents,
              intersection.isNull == false,
              intersection.isEmpty == false else {
            return nil
        }

        return ViewportCanvasOverlayExclusion(
            rect: intersection,
            fittingEdges: fittingEdges
        )
    }
}

extension CGRect {
    var hasFiniteComponents: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
    }
}
