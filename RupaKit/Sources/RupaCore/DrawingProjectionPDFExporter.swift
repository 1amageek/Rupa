import Foundation
import SwiftCAD

public struct DrawingProjectionPDFExporter: Sendable {
    public struct Options: Codable, Equatable, Sendable {
        public var pageWidth: Double
        public var pageHeight: Double
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
            pageWidth: Double = 792.0,
            pageHeight: Double = 612.0,
            padding: Double = 36.0,
            pagePreset: DrawingProjectionPagePreset? = nil,
            visibleStrokeWidth: Double = 1.2,
            hiddenStrokeWidth: Double = 0.8,
            partiallyHiddenStrokeWidth: Double = 1.0,
            unclassifiedStrokeWidth: Double = 0.8,
            sectionHatchStrokeWidth: Double = 0.6,
            sectionContourStrokeWidth: Double = 1.3,
            annotationStrokeWidth: Double = 0.9,
            style: DrawingProjectionExportStyle? = nil
        ) {
            if let pagePreset {
                let page = pagePreset.page
                self.pageWidth = page.width
                self.pageHeight = page.height
            } else {
                self.pageWidth = pageWidth
                self.pageHeight = pageHeight
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
        var pageWidth: Double
        var pageHeight: Double
        var bounds: Bounds
        var scale: Double
        var offsetX: Double
        var offsetY: Double

        func point(_ point: Point2D) -> Point2D {
            let x: Double
            if abs(bounds.width) <= Self.minimumSpan {
                x = pageWidth / 2.0
            } else {
                x = offsetX + (point.x - bounds.minX) * scale
            }

            let y: Double
            if abs(bounds.height) <= Self.minimumSpan {
                y = pageHeight / 2.0
            } else {
                y = offsetY + (point.y - bounds.minY) * scale
            }

            return Point2D(x: x, y: y)
        }

        private static let minimumSpan = 1.0e-12
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func pdf(for result: DrawingProjectionResult) -> Data {
        let options = normalizedOptions()
        let segments = renderableSegments(from: result)
        let bounds = normalizedBounds(
            reportedBounds: result.bounds,
            segments: segments,
            sectionContours: result.sectionContours,
            sectionHatches: result.sectionHatches,
            annotations: result.annotations
        )
        let transform = transform(options: options, bounds: bounds)
        let content = contentStream(
            result: result,
            options: options,
            segments: segments,
            transform: transform
        )
        return Data(pdfDocument(options: options, content: content).utf8)
    }

    private func contentStream(
        result: DrawingProjectionResult,
        options: Options,
        segments: [RenderableSegment],
        transform: Transform
    ) -> String {
        var lines: [String] = [
            "q",
            "1 J",
            "1 j",
            "% Rupa drawing projection",
            "% saved-view \(sanitizedComment(result.savedViewID.description))",
        ]
        appendSectionHatches(
            result.sectionHatches,
            transform: transform,
            style: options.style.sectionHatch,
            to: &lines
        )
        appendSegments(
            visibility: .hidden,
            segments: segments,
            transform: transform,
            style: options.style.hidden,
            to: &lines
        )
        appendSegments(
            visibility: .partiallyHidden,
            segments: segments,
            transform: transform,
            style: options.style.partiallyHidden,
            to: &lines
        )
        appendSegments(
            visibility: .unclassified,
            segments: segments,
            transform: transform,
            style: options.style.unclassified,
            to: &lines
        )
        appendSegments(
            visibility: .visible,
            segments: segments,
            transform: transform,
            style: options.style.visible,
            to: &lines
        )
        appendSectionContours(
            result.sectionContours,
            transform: transform,
            style: options.style.sectionContour,
            to: &lines
        )
        appendAnnotations(
            result.annotations,
            transform: transform,
            style: options.style.annotation,
            to: &lines
        )
        lines.append("Q")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func appendSegments(
        visibility: DrawingProjectionResult.Visibility,
        segments: [RenderableSegment],
        transform: Transform,
        style: DrawingProjectionLayerStyle,
        to lines: inout [String]
    ) {
        lines.append("% layer \(visibility.rawValue)-segments")
        append(style: style, to: &lines)
        for segment in segments where segment.visibility == visibility {
            appendLine(start: segment.start, end: segment.end, transform: transform, to: &lines)
        }
    }

    private func appendSectionHatches(
        _ hatches: [DrawingProjectionResult.SectionHatchSegment],
        transform: Transform,
        style: DrawingProjectionLayerStyle,
        to lines: inout [String]
    ) {
        lines.append("% layer section-hatches")
        append(style: style, to: &lines)
        for hatch in hatches {
            appendLine(start: hatch.start2D, end: hatch.end2D, transform: transform, to: &lines)
        }
    }

    private func appendSectionContours(
        _ contours: [DrawingProjectionResult.SectionContour],
        transform: Transform,
        style: DrawingProjectionLayerStyle,
        to lines: inout [String]
    ) {
        lines.append("% layer section-contours")
        append(style: style, to: &lines)
        for contour in contours where contour.projectedPoints2D.count >= 2 {
            appendPath(points: contour.projectedPoints2D, closes: true, transform: transform, to: &lines)
        }
    }

    private func append(
        style: DrawingProjectionLayerStyle,
        to lines: inout [String]
    ) {
        lines.append("\(format(style.color.red)) \(format(style.color.green)) \(format(style.color.blue)) RG")
        lines.append("\(format(style.strokeWidth)) w")
        lines.append(pdfDashPattern(style.dashPattern))
    }

    private func appendAnnotations(
        _ annotations: [DrawingProjectionResult.Annotation],
        transform: Transform,
        style: DrawingProjectionLayerStyle,
        to lines: inout [String]
    ) {
        lines.append("% layer drawing-annotations")
        append(style: style, to: &lines)
        for annotation in annotations {
            appendAnnotation(annotation, transform: transform, style: style, to: &lines)
        }
    }

    private func appendAnnotation(
        _ annotation: DrawingProjectionResult.Annotation,
        transform: Transform,
        style: DrawingProjectionLayerStyle,
        to lines: inout [String]
    ) {
        lines.append(
            "% annotation \(sanitizedComment(annotation.id)) label \(annotation.labelLayout?.placement.rawValue ?? "automatic")"
        )
        let points = annotation.anchors.map { transform.point($0.point2D) }
        if points.count >= 2 {
            let first = points[0]
            lines.append("\(format(first.x)) \(format(first.y)) m")
            for point in points.dropFirst() {
                lines.append("\(format(point.x)) \(format(point.y)) l")
            }
            lines.append("S")
        }
        for point in points {
            let radius = 2.0
            lines.append("\(format(point.x - radius)) \(format(point.y)) m")
            lines.append("\(format(point.x + radius)) \(format(point.y)) l")
            lines.append("\(format(point.x)) \(format(point.y - radius)) m")
            lines.append("\(format(point.x)) \(format(point.y + radius)) l")
            lines.append("S")
        }
        if let leaderStart = annotation.labelLayout?.leaderStart2D,
           let leaderEnd = annotation.labelLayout?.leaderEnd2D {
            appendLine(
                start: leaderStart,
                end: leaderEnd,
                transform: transform,
                to: &lines
            )
        }
        let label = transform.point(annotation.labelPoint2D)
        lines.append("\(format(style.color.red)) \(format(style.color.green)) \(format(style.color.blue)) rg")
        lines.append("BT")
        lines.append("/F1 9 Tf")
        lines.append("\(format(label.x)) \(format(label.y)) Td")
        lines.append("(\(pdfString(annotation.displayText))) Tj")
        lines.append("ET")
    }

    private func appendLine(
        start: Point2D,
        end: Point2D,
        transform: Transform,
        to lines: inout [String]
    ) {
        let startPoint = transform.point(start)
        let endPoint = transform.point(end)
        lines.append("\(format(startPoint.x)) \(format(startPoint.y)) m")
        lines.append("\(format(endPoint.x)) \(format(endPoint.y)) l")
        lines.append("S")
    }

    private func appendPath(
        points: [Point2D],
        closes: Bool,
        transform: Transform,
        to lines: inout [String]
    ) {
        guard let first = points.first else {
            return
        }
        let transformedFirst = transform.point(first)
        lines.append("\(format(transformedFirst.x)) \(format(transformedFirst.y)) m")
        for point in points.dropFirst() {
            let transformed = transform.point(point)
            lines.append("\(format(transformed.x)) \(format(transformed.y)) l")
        }
        if closes {
            lines.append("h")
        }
        lines.append("S")
    }

    private func pdfDocument(
        options: Options,
        content: String
    ) -> String {
        let objects = [
            "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n",
            "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n",
            "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 \(format(options.pageWidth)) \(format(options.pageHeight))] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >> endobj\n",
            "4 0 obj << /Length \(content.utf8.count) >> stream\n\(content)endstream endobj\n",
            "5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n",
        ]
        var result = "%PDF-1.4\n"
        var offsets: [Int] = [0]
        for object in objects {
            offsets.append(result.utf8.count)
            result += object
        }
        let xrefOffset = result.utf8.count
        result += "xref\n0 \(objects.count + 1)\n"
        result += "0000000000 65535 f \n"
        for offset in offsets.dropFirst() {
            result += String(format: "%010d 00000 n \n", offset)
        }
        result += "trailer << /Size \(objects.count + 1) /Root 1 0 R >>\n"
        result += "startxref\n\(xrefOffset)\n%%EOF\n"
        return result
    }

    private func renderableSegments(
        from result: DrawingProjectionResult
    ) -> [RenderableSegment] {
        result.strokes.flatMap { stroke in
            if stroke.visibilitySegments.isEmpty {
                return [
                    RenderableSegment(
                        visibility: stroke.visibility,
                        start: stroke.start2D,
                        end: stroke.end2D
                    ),
                ]
            }

            return stroke.visibilitySegments.map { segment in
                RenderableSegment(
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
        let availableWidth = max(1.0, options.pageWidth - options.padding * 2.0)
        let availableHeight = max(1.0, options.pageHeight - options.padding * 2.0)
        let boundedWidth = max(abs(bounds.width), 1.0e-12)
        let boundedHeight = max(abs(bounds.height), 1.0e-12)
        let scale = min(
            availableWidth / boundedWidth,
            availableHeight / boundedHeight
        )
        let contentWidth = abs(bounds.width) <= 1.0e-12 ? 0.0 : bounds.width * scale
        let contentHeight = abs(bounds.height) <= 1.0e-12 ? 0.0 : bounds.height * scale
        return Transform(
            pageWidth: options.pageWidth,
            pageHeight: options.pageHeight,
            bounds: bounds,
            scale: scale,
            offsetX: (options.pageWidth - contentWidth) / 2.0,
            offsetY: (options.pageHeight - contentHeight) / 2.0
        )
    }

    private func normalizedOptions() -> Options {
        let visibleStrokeWidth = finitePositive(options.visibleStrokeWidth, fallback: 1.2)
        let hiddenStrokeWidth = finitePositive(options.hiddenStrokeWidth, fallback: 0.8)
        let partiallyHiddenStrokeWidth = finitePositive(options.partiallyHiddenStrokeWidth, fallback: 1.0)
        let unclassifiedStrokeWidth = finitePositive(options.unclassifiedStrokeWidth, fallback: 0.8)
        let sectionHatchStrokeWidth = finitePositive(options.sectionHatchStrokeWidth, fallback: 0.6)
        let sectionContourStrokeWidth = finitePositive(options.sectionContourStrokeWidth, fallback: 1.3)
        let annotationStrokeWidth = finitePositive(options.annotationStrokeWidth, fallback: 0.9)
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
            pageWidth: finitePositive(options.pageWidth, fallback: 792.0),
            pageHeight: finitePositive(options.pageHeight, fallback: 612.0),
            padding: finiteNonnegative(options.padding, fallback: 36.0),
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

    private func pdfDashPattern(_ dashPattern: [Double]) -> String {
        guard !dashPattern.isEmpty else {
            return "[] 0 d"
        }
        return "[\(dashPattern.map(formatDashValue).joined(separator: " "))] 0 d"
    }

    private func formatDashValue(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) <= 1.0e-9 {
            return String(Int(rounded))
        }
        return format(value)
    }

    private func sanitizedComment(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x20...0x7e where scalar.value != 0x25:
                output.unicodeScalars.append(scalar)
            default:
                output += "_"
            }
        }
        return output
    }

    private func pdfString(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x28:
                output += "\\("
            case 0x29:
                output += "\\)"
            case 0x5c:
                output += "\\\\"
            case 0x20...0x7e:
                output.unicodeScalars.append(scalar)
            default:
                output += "?"
            }
        }
        return output
    }
}
