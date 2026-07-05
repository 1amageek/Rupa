import Foundation
import SwiftCAD

public struct DrawingProjectionSVGExporter: Sendable {
    public struct Options: Codable, Equatable, Sendable {
        public var width: Double
        public var height: Double
        public var padding: Double
        public var visibleStrokeWidth: Double
        public var hiddenStrokeWidth: Double
        public var partiallyHiddenStrokeWidth: Double
        public var unclassifiedStrokeWidth: Double
        public var sectionHatchStrokeWidth: Double
        public var sectionContourStrokeWidth: Double
        public var annotationStrokeWidth: Double
        public var pagePreset: DrawingProjectionPagePreset?
        public var style: DrawingProjectionExportStyle

        public init(
            width: Double = 1024.0,
            height: Double = 1024.0,
            padding: Double = 32.0,
            pagePreset: DrawingProjectionPagePreset? = nil,
            visibleStrokeWidth: Double = 1.45,
            hiddenStrokeWidth: Double = 1.0,
            partiallyHiddenStrokeWidth: Double = 1.2,
            unclassifiedStrokeWidth: Double = 1.0,
            sectionHatchStrokeWidth: Double = 0.85,
            sectionContourStrokeWidth: Double = 1.6,
            annotationStrokeWidth: Double = 1.0,
            style: DrawingProjectionExportStyle? = nil
        ) {
            if let pagePreset {
                let page = pagePreset.page
                self.width = page.width
                self.height = page.height
            } else {
                self.width = width
                self.height = height
            }
            self.padding = padding
            self.visibleStrokeWidth = visibleStrokeWidth
            self.hiddenStrokeWidth = hiddenStrokeWidth
            self.partiallyHiddenStrokeWidth = partiallyHiddenStrokeWidth
            self.unclassifiedStrokeWidth = unclassifiedStrokeWidth
            self.sectionHatchStrokeWidth = sectionHatchStrokeWidth
            self.sectionContourStrokeWidth = sectionContourStrokeWidth
            self.annotationStrokeWidth = annotationStrokeWidth
            self.pagePreset = pagePreset
            self.style = style ?? .technical(
                visibleStrokeWidth: visibleStrokeWidth,
                hiddenStrokeWidth: hiddenStrokeWidth,
                partiallyHiddenStrokeWidth: partiallyHiddenStrokeWidth,
                unclassifiedStrokeWidth: unclassifiedStrokeWidth,
                sectionHatchStrokeWidth: sectionHatchStrokeWidth,
                sectionContourStrokeWidth: sectionContourStrokeWidth,
                annotationStrokeWidth: annotationStrokeWidth
            )
        }
    }

    private struct RenderableSegment {
        var strokeID: String
        var bodyID: String
        var kind: DrawingProjectionResult.StrokeKind
        var visibility: DrawingProjectionResult.Visibility
        var start: Point2D
        var end: Point2D
    }

    private struct Bounds {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double

        var width: Double {
            maxX - minX
        }

        var height: Double {
            maxY - minY
        }

        mutating func include(_ point: Point2D) {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
    }

    private struct Transform {
        var canvasWidth: Double
        var canvasHeight: Double
        var bounds: Bounds
        var scale: Double
        var offsetX: Double
        var offsetY: Double

        func point(_ point: Point2D) -> Point2D {
            let x: Double
            if abs(bounds.width) <= Self.minimumSpan {
                x = canvasWidth / 2.0
            } else {
                x = offsetX + (point.x - bounds.minX) * scale
            }

            let y: Double
            if abs(bounds.height) <= Self.minimumSpan {
                y = canvasHeight / 2.0
            } else {
                y = offsetY + (bounds.maxY - point.y) * scale
            }

            return Point2D(x: x, y: y)
        }

        private static let minimumSpan = 1.0e-12
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func svg(for result: DrawingProjectionResult) -> String {
        let options = normalizedOptions()
        let segments = renderableSegments(from: result)
        let bounds = normalizedBounds(
            reportedBounds: result.bounds,
            segments: segments,
            sectionContours: result.sectionContours,
            sectionHatches: result.sectionHatches,
            annotations: result.annotations
        )
        let transform = transform(
            options: options,
            bounds: bounds
        )

        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="\#(format(options.width))" height="\#(format(options.height))" viewBox="0 0 \#(format(options.width)) \#(format(options.height))" fill="none">"#,
            #"  <title>\#(escaped(result.savedViewName))</title>"#,
            #"  <desc>Rupa drawing projection, \#(result.projectionMode.rawValue), \#(result.strokeCount) strokes, \#(result.visibilitySegmentCount) visibility segments.</desc>"#,
            #"  <g id="drawing-projection" data-saved-view-id="\#(escaped(result.savedViewID.description))" data-display-unit="\#(escaped(result.displayUnit.symbol))" data-body-count="\#(result.bodyCount)" data-triangle-count="\#(result.triangleCount)" data-candidate-edge-count="\#(result.candidateEdgeCount)" data-truncated="\#(result.truncatedStrokes)">"#,
        ]

        appendSectionHatchLayer(
            hatches: result.sectionHatches,
            transform: transform,
            style: options.style.sectionHatch,
            to: &lines
        )
        appendLayer(
            visibility: .hidden,
            segments: segments,
            transform: transform,
            style: options.style.hidden,
            to: &lines
        )
        appendLayer(
            visibility: .partiallyHidden,
            segments: segments,
            transform: transform,
            style: options.style.partiallyHidden,
            to: &lines
        )
        appendLayer(
            visibility: .unclassified,
            segments: segments,
            transform: transform,
            style: options.style.unclassified,
            to: &lines
        )
        appendLayer(
            visibility: .visible,
            segments: segments,
            transform: transform,
            style: options.style.visible,
            to: &lines
        )
        appendSectionContourLayer(
            contours: result.sectionContours,
            transform: transform,
            style: options.style.sectionContour,
            to: &lines
        )
        appendAnnotationLayer(
            annotations: result.annotations,
            transform: transform,
            style: options.style.annotation,
            to: &lines
        )

        lines.append("  </g>")
        lines.append("</svg>")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func appendSectionHatchLayer(
        hatches: [DrawingProjectionResult.SectionHatchSegment],
        transform: Transform,
        style: DrawingProjectionLayerStyle,
        to lines: inout [String]
    ) {
        lines.append(
            #"    <g id="section-hatches" data-kind="sectionHatch" stroke="\#(style.color.hexString)" stroke-width="\#(format(style.strokeWidth))" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke">"#
        )
        for hatch in hatches {
            let start = transform.point(hatch.start2D)
            let end = transform.point(hatch.end2D)
            lines.append(
                #"      <path d="M \#(format(start.x)) \#(format(start.y)) L \#(format(end.x)) \#(format(end.y))" data-hatch-id="\#(escaped(hatch.id))" data-contour-id="\#(escaped(hatch.contourID))" data-body-id="\#(escaped(hatch.bodyID))"\#(sectionSourceAttributes(id: hatch.sectionSourceID, name: hatch.sectionSourceName)) data-spacing-meters="\#(format(hatch.spacingMeters))" data-angle-degrees="\#(format(hatch.angleDegrees))" />"#
            )
        }
        lines.append("    </g>")
    }

    private func appendSectionContourLayer(
        contours: [DrawingProjectionResult.SectionContour],
        transform: Transform,
        style: DrawingProjectionLayerStyle,
        to lines: inout [String]
    ) {
        lines.append(
            #"    <g id="section-contours" data-kind="sectionContour" stroke="\#(style.color.hexString)" stroke-width="\#(format(style.strokeWidth))" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke">"#
        )
        for contour in contours where contour.projectedPoints2D.count >= 2 {
            let path = pathData(
                points: contour.projectedPoints2D,
                closes: contour.projectedPoints2D.count >= 3,
                transform: transform
            )
            lines.append(
                #"      <path d="\#(path)" data-contour-id="\#(escaped(contour.id))" data-body-id="\#(escaped(contour.bodyID))"\#(sectionSourceAttributes(id: contour.sectionSourceID, name: contour.sectionSourceName)) data-segment-count="\#(contour.segmentCount)" />"#
            )
        }
        lines.append("    </g>")
    }

    private func appendLayer(
        visibility: DrawingProjectionResult.Visibility,
        segments: [RenderableSegment],
        transform: Transform,
        style: DrawingProjectionLayerStyle,
        to lines: inout [String]
    ) {
        let layerSegments = segments.filter { $0.visibility == visibility }
        let dashAttribute = svgDashAttribute(style.dashPattern)
        lines.append(
            #"    <g id="\#(visibility.rawValue)-segments" data-visibility="\#(visibility.rawValue)" stroke="\#(style.color.hexString)" stroke-width="\#(format(style.strokeWidth))" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"\#(dashAttribute)>"#
        )
        for segment in layerSegments {
            let start = transform.point(segment.start)
            let end = transform.point(segment.end)
            lines.append(
                #"      <path d="M \#(format(start.x)) \#(format(start.y)) L \#(format(end.x)) \#(format(end.y))" data-stroke-id="\#(escaped(segment.strokeID))" data-body-id="\#(escaped(segment.bodyID))" data-kind="\#(segment.kind.rawValue)" />"#
            )
        }
        lines.append("    </g>")
    }

    private func appendAnnotationLayer(
        annotations: [DrawingProjectionResult.Annotation],
        transform: Transform,
        style: DrawingProjectionLayerStyle,
        to lines: inout [String]
    ) {
        lines.append(
            #"    <g id="drawing-annotations" data-kind="drawingAnnotation" stroke="\#(style.color.hexString)" stroke-width="\#(format(style.strokeWidth))" fill="\#(style.color.hexString)" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke">"#
        )
        for annotation in annotations {
            appendAnnotation(annotation, transform: transform, to: &lines)
        }
        lines.append("    </g>")
    }

    private func appendAnnotation(
        _ annotation: DrawingProjectionResult.Annotation,
        transform: Transform,
        to lines: inout [String]
    ) {
        let points = annotation.anchors.map { transform.point($0.point2D) }
        if points.count >= 2 {
            let path = points.map { point in
                "\(format(point.x)) \(format(point.y))"
            }.joined(separator: " L ")
            lines.append(
                #"      <path d="M \#(path)" data-annotation-id="\#(escaped(annotation.id))" data-measurement-id="\#(escaped(annotation.measurementID.description))" data-kind="\#(annotation.kind.rawValue)" />"#
            )
        }
        if let leaderStart = annotation.labelLayout?.leaderStart2D,
           let leaderEnd = annotation.labelLayout?.leaderEnd2D {
            let start = transform.point(leaderStart)
            let end = transform.point(leaderEnd)
            lines.append(
                #"      <path d="M \#(format(start.x)) \#(format(start.y)) L \#(format(end.x)) \#(format(end.y))" data-annotation-id="\#(escaped(annotation.id))" data-kind="annotationLeader" data-label-placement="\#(annotation.labelLayout?.placement.rawValue ?? "automatic")" />"#
            )
        }
        for (index, point) in points.enumerated() {
            lines.append(
                #"      <circle cx="\#(format(point.x))" cy="\#(format(point.y))" r="2.500000" data-annotation-id="\#(escaped(annotation.id))" data-anchor-index="\#(index)" />"#
            )
        }
        let label = transform.point(annotation.labelPoint2D)
        lines.append(
            #"      <text x="\#(format(label.x))" y="\#(format(label.y))" font-family="SFMono-Regular, Menlo, monospace" font-size="11" text-anchor="middle" dominant-baseline="middle" data-annotation-id="\#(escaped(annotation.id))" data-label-placement="\#(annotation.labelLayout?.placement.rawValue ?? "automatic")">\#(escaped(annotation.displayText))</text>"#
        )
    }

    private func renderableSegments(
        from result: DrawingProjectionResult
    ) -> [RenderableSegment] {
        result.strokes.flatMap { stroke in
            if stroke.visibilitySegments.isEmpty {
                return [
                    RenderableSegment(
                        strokeID: stroke.id,
                        bodyID: stroke.bodyID,
                        kind: stroke.kind,
                        visibility: stroke.visibility,
                        start: stroke.start2D,
                        end: stroke.end2D
                    ),
                ]
            }

            return stroke.visibilitySegments.map { segment in
                RenderableSegment(
                    strokeID: stroke.id,
                    bodyID: stroke.bodyID,
                    kind: stroke.kind,
                    visibility: segment.visibility,
                    start: segment.start2D,
                    end: segment.end2D
                )
            }
        }
    }

    private func normalizedBounds(
        reportedBounds: DrawingProjectionResult.Bounds2D?,
        segments: [RenderableSegment],
        sectionContours: [DrawingProjectionResult.SectionContour],
        sectionHatches: [DrawingProjectionResult.SectionHatchSegment],
        annotations: [DrawingProjectionResult.Annotation]
    ) -> Bounds {
        if let reportedBounds,
           reportedBounds.minX.isFinite,
           reportedBounds.minY.isFinite,
           reportedBounds.maxX.isFinite,
           reportedBounds.maxY.isFinite,
           reportedBounds.maxX >= reportedBounds.minX,
           reportedBounds.maxY >= reportedBounds.minY {
            return Bounds(
                minX: reportedBounds.minX,
                minY: reportedBounds.minY,
                maxX: reportedBounds.maxX,
                maxY: reportedBounds.maxY
            )
        }

        var bounds = Bounds(
            minX: Double.infinity,
            minY: Double.infinity,
            maxX: -Double.infinity,
            maxY: -Double.infinity
        )
        for segment in segments {
            bounds.include(segment.start)
            bounds.include(segment.end)
        }
        for contour in sectionContours {
            for point in contour.projectedPoints2D {
                bounds.include(point)
            }
        }
        for hatch in sectionHatches {
            bounds.include(hatch.start2D)
            bounds.include(hatch.end2D)
        }
        for annotation in annotations {
            bounds.include(annotation.labelPoint2D)
            for anchor in annotation.anchors {
                bounds.include(anchor.point2D)
            }
        }

        guard bounds.minX.isFinite,
              bounds.minY.isFinite,
              bounds.maxX.isFinite,
              bounds.maxY.isFinite else {
            return Bounds(minX: -0.5, minY: -0.5, maxX: 0.5, maxY: 0.5)
        }
        return bounds
    }

    private func transform(
        options: Options,
        bounds: Bounds
    ) -> Transform {
        let availableWidth = max(1.0, options.width - options.padding * 2.0)
        let availableHeight = max(1.0, options.height - options.padding * 2.0)
        let boundedWidth = max(abs(bounds.width), 1.0e-12)
        let boundedHeight = max(abs(bounds.height), 1.0e-12)
        let scale = min(
            availableWidth / boundedWidth,
            availableHeight / boundedHeight
        )
        let contentWidth = abs(bounds.width) <= 1.0e-12 ? 0.0 : bounds.width * scale
        let contentHeight = abs(bounds.height) <= 1.0e-12 ? 0.0 : bounds.height * scale
        return Transform(
            canvasWidth: options.width,
            canvasHeight: options.height,
            bounds: bounds,
            scale: scale,
            offsetX: (options.width - contentWidth) / 2.0,
            offsetY: (options.height - contentHeight) / 2.0
        )
    }

    private func normalizedOptions() -> Options {
        let visibleStrokeWidth = finitePositive(options.visibleStrokeWidth, fallback: 1.45)
        let hiddenStrokeWidth = finitePositive(options.hiddenStrokeWidth, fallback: 1.0)
        let partiallyHiddenStrokeWidth = finitePositive(options.partiallyHiddenStrokeWidth, fallback: 1.2)
        let unclassifiedStrokeWidth = finitePositive(options.unclassifiedStrokeWidth, fallback: 1.0)
        let sectionHatchStrokeWidth = finitePositive(options.sectionHatchStrokeWidth, fallback: 0.85)
        let sectionContourStrokeWidth = finitePositive(options.sectionContourStrokeWidth, fallback: 1.6)
        let annotationStrokeWidth = finitePositive(options.annotationStrokeWidth, fallback: 1.0)
        let fallbackStyle = DrawingProjectionExportStyle.technical(
            visibleStrokeWidth: visibleStrokeWidth,
            hiddenStrokeWidth: hiddenStrokeWidth,
            partiallyHiddenStrokeWidth: partiallyHiddenStrokeWidth,
            unclassifiedStrokeWidth: unclassifiedStrokeWidth,
            sectionHatchStrokeWidth: sectionHatchStrokeWidth,
            sectionContourStrokeWidth: sectionContourStrokeWidth,
            annotationStrokeWidth: annotationStrokeWidth
        )
        return Options(
            width: finitePositive(options.width, fallback: 1024.0),
            height: finitePositive(options.height, fallback: 1024.0),
            padding: finiteNonnegative(options.padding, fallback: 32.0),
            pagePreset: options.pagePreset,
            visibleStrokeWidth: visibleStrokeWidth,
            hiddenStrokeWidth: hiddenStrokeWidth,
            partiallyHiddenStrokeWidth: partiallyHiddenStrokeWidth,
            unclassifiedStrokeWidth: unclassifiedStrokeWidth,
            sectionHatchStrokeWidth: sectionHatchStrokeWidth,
            sectionContourStrokeWidth: sectionContourStrokeWidth,
            annotationStrokeWidth: annotationStrokeWidth,
            style: options.style.normalized(fallback: fallbackStyle)
        )
    }

    private func finitePositive(
        _ value: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite,
              value > 0.0 else {
            return fallback
        }
        return value
    }

    private func finiteNonnegative(
        _ value: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite,
              value >= 0.0 else {
            return fallback
        }
        return value
    }

    private func format(_ value: Double) -> String {
        let normalized = abs(value) < 0.0000005 ? 0.0 : value
        return String(
            format: "%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            normalized
        )
    }

    private func svgDashAttribute(_ dashPattern: [Double]) -> String {
        guard !dashPattern.isEmpty else {
            return ""
        }
        return #" stroke-dasharray="\#(dashPattern.map(formatDashValue).joined(separator: " "))""#
    }

    private func formatDashValue(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) <= 1.0e-9 {
            return String(Int(rounded))
        }
        return format(value)
    }

    private func escaped(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&":
                output += "&amp;"
            case "<":
                output += "&lt;"
            case ">":
                output += "&gt;"
            case "\"":
                output += "&quot;"
            case "'":
                output += "&apos;"
            default:
                output.append(character)
            }
        }
        return output
    }

    private func sectionSourceAttributes(
        id: String?,
        name: String?
    ) -> String {
        var attributes = ""
        if let id {
            attributes += #" data-section-source-id="\#(escaped(id))""#
        }
        if let name {
            attributes += #" data-section-source-name="\#(escaped(name))""#
        }
        return attributes
    }

    private func pathData(
        points: [Point2D],
        closes: Bool,
        transform: Transform
    ) -> String {
        guard let first = points.first else {
            return ""
        }
        let transformedFirst = transform.point(first)
        var parts = [
            "M \(format(transformedFirst.x)) \(format(transformedFirst.y))",
        ]
        for point in points.dropFirst() {
            let transformed = transform.point(point)
            parts.append("L \(format(transformed.x)) \(format(transformed.y))")
        }
        if closes {
            parts.append("Z")
        }
        return parts.joined(separator: " ")
    }
}
