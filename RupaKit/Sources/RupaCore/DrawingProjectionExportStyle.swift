public struct DrawingProjectionExportStyle: Codable, Equatable, Sendable {
    public var visible: DrawingProjectionLayerStyle
    public var hidden: DrawingProjectionLayerStyle
    public var partiallyHidden: DrawingProjectionLayerStyle
    public var unclassified: DrawingProjectionLayerStyle
    public var sectionHatch: DrawingProjectionLayerStyle
    public var sectionContour: DrawingProjectionLayerStyle
    public var annotation: DrawingProjectionLayerStyle

    public init(
        visible: DrawingProjectionLayerStyle,
        hidden: DrawingProjectionLayerStyle,
        partiallyHidden: DrawingProjectionLayerStyle,
        unclassified: DrawingProjectionLayerStyle,
        sectionHatch: DrawingProjectionLayerStyle,
        sectionContour: DrawingProjectionLayerStyle,
        annotation: DrawingProjectionLayerStyle
    ) {
        self.visible = visible
        self.hidden = hidden
        self.partiallyHidden = partiallyHidden
        self.unclassified = unclassified
        self.sectionHatch = sectionHatch
        self.sectionContour = sectionContour
        self.annotation = annotation
    }

    public static func preset(_ preset: DrawingProjectionStylePreset) -> DrawingProjectionExportStyle {
        switch preset {
        case .technical:
            technical()
        case .presentation:
            presentation
        }
    }

    public static func technical(
        visibleStrokeWidth: Double = 1.2,
        hiddenStrokeWidth: Double = 0.8,
        partiallyHiddenStrokeWidth: Double = 1.0,
        unclassifiedStrokeWidth: Double = 0.8,
        sectionHatchStrokeWidth: Double = 0.6,
        sectionContourStrokeWidth: Double = 1.3,
        annotationStrokeWidth: Double = 0.9
    ) -> DrawingProjectionExportStyle {
        DrawingProjectionExportStyle(
            visible: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 17, green: 24, blue: 39),
                strokeWidth: visibleStrokeWidth
            ),
            hidden: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 107, green: 114, blue: 128),
                strokeWidth: hiddenStrokeWidth,
                dashPattern: [6.0, 4.0]
            ),
            partiallyHidden: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 55, green: 65, blue: 81),
                strokeWidth: partiallyHiddenStrokeWidth,
                dashPattern: [10.0, 4.0, 2.0, 4.0]
            ),
            unclassified: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 245, green: 158, blue: 11),
                strokeWidth: unclassifiedStrokeWidth,
                dashPattern: [2.0, 3.0]
            ),
            sectionHatch: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 156, green: 163, blue: 175),
                strokeWidth: sectionHatchStrokeWidth
            ),
            sectionContour: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 17, green: 24, blue: 39),
                strokeWidth: sectionContourStrokeWidth
            ),
            annotation: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 37, green: 99, blue: 235),
                strokeWidth: annotationStrokeWidth
            )
        )
    }

    public static var presentation: DrawingProjectionExportStyle {
        DrawingProjectionExportStyle(
            visible: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 37, green: 99, blue: 235),
                strokeWidth: 1.5
            ),
            hidden: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 100, green: 116, blue: 139),
                strokeWidth: 0.9,
                dashPattern: [4.0, 3.0]
            ),
            partiallyHidden: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 15, green: 118, blue: 110),
                strokeWidth: 1.1,
                dashPattern: [8.0, 3.0, 2.0, 3.0]
            ),
            unclassified: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 217, green: 119, blue: 6),
                strokeWidth: 0.9,
                dashPattern: [2.0, 3.0]
            ),
            sectionHatch: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 148, green: 163, blue: 184),
                strokeWidth: 0.7
            ),
            sectionContour: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 15, green: 23, blue: 42),
                strokeWidth: 1.6
            ),
            annotation: DrawingProjectionLayerStyle(
                color: DrawingProjectionColor(hexRed: 6, green: 182, blue: 212),
                strokeWidth: 1.0
            )
        )
    }

    public func normalized(fallback: DrawingProjectionExportStyle) -> DrawingProjectionExportStyle {
        DrawingProjectionExportStyle(
            visible: visible.normalized(fallback: fallback.visible),
            hidden: hidden.normalized(fallback: fallback.hidden),
            partiallyHidden: partiallyHidden.normalized(fallback: fallback.partiallyHidden),
            unclassified: unclassified.normalized(fallback: fallback.unclassified),
            sectionHatch: sectionHatch.normalized(fallback: fallback.sectionHatch),
            sectionContour: sectionContour.normalized(fallback: fallback.sectionContour),
            annotation: annotation.normalized(fallback: fallback.annotation)
        )
    }
}
