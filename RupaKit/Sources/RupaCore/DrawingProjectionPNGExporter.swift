import CoreGraphics
import Foundation
import ImageIO
import SwiftCAD
import UniformTypeIdentifiers

public struct DrawingProjectionPNGExporter: Sendable {
    public struct Options: Codable, Equatable, Sendable {
        public var width: Double
        public var height: Double
        public var padding: Double
        public var pixelScale: Double
        public var pagePreset: DrawingProjectionPagePreset?
        public var style: DrawingProjectionExportStyle

        public init(
            width: Double = 1024.0,
            height: Double = 1024.0,
            padding: Double = 32.0,
            pixelScale: Double = 2.0,
            pagePreset: DrawingProjectionPagePreset? = nil,
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
            self.pixelScale = pixelScale
            self.pagePreset = pagePreset
            self.style = style ?? .technical()
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
        var canvasWidth: Double
        var canvasHeight: Double
        var bounds: Bounds
        var scale: Double
        var offsetX: Double
        var offsetY: Double

        func point(_ point: Point2D) -> CGPoint {
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

            return CGPoint(x: x, y: y)
        }

        private static let minimumSpan = 1.0e-12
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func png(for result: DrawingProjectionResult) throws -> Data {
        let options = normalizedOptions()
        let pixelWidth = Int((options.width * options.pixelScale).rounded(.up))
        let pixelHeight = Int((options.height * options.pixelScale).rounded(.up))
        guard pixelWidth > 0,
              pixelHeight > 0 else {
            throw EditorError(
                code: .exportFailed,
                message: "Drawing projection PNG export requires a positive output size."
            )
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw EditorError(
                code: .exportFailed,
                message: "Drawing projection PNG export could not create a bitmap context."
            )
        }

        context.scaleBy(x: options.pixelScale, y: options.pixelScale)
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0.0, y: 0.0, width: options.width, height: options.height))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let segments = renderableSegments(from: result)
        let bounds = normalizedBounds(
            reportedBounds: result.bounds,
            segments: segments,
            sectionContours: result.sectionContours,
            sectionHatches: result.sectionHatches,
            annotations: result.annotations
        )
        let transform = transform(options: options, bounds: bounds)

        drawSectionHatches(result.sectionHatches, transform: transform, options: options, in: context)
        drawSegments(.hidden, segments: segments, transform: transform, style: options.style.hidden, in: context)
        drawSegments(
            .partiallyHidden,
            segments: segments,
            transform: transform,
            style: options.style.partiallyHidden,
            in: context
        )
        drawSegments(
            .unclassified,
            segments: segments,
            transform: transform,
            style: options.style.unclassified,
            in: context
        )
        drawSegments(.visible, segments: segments, transform: transform, style: options.style.visible, in: context)
        drawSectionContours(result.sectionContours, transform: transform, options: options, in: context)
        drawAnnotations(result.annotations, transform: transform, options: options, in: context)

        guard let image = context.makeImage() else {
            throw EditorError(
                code: .exportFailed,
                message: "Drawing projection PNG export could not finalize the bitmap image."
            )
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw EditorError(
                code: .exportFailed,
                message: "Drawing projection PNG export could not create an image destination."
            )
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw EditorError(
                code: .exportFailed,
                message: "Drawing projection PNG export failed while encoding PNG data."
            )
        }
        return data as Data
    }

    private func drawSegments(
        _ visibility: DrawingProjectionResult.Visibility,
        segments: [RenderableSegment],
        transform: Transform,
        style: DrawingProjectionLayerStyle,
        in context: CGContext
    ) {
        apply(style: style, in: context)
        for segment in segments where segment.visibility == visibility {
            drawLine(
                start: segment.start,
                end: segment.end,
                transform: transform,
                in: context
            )
        }
    }

    private func drawSectionHatches(
        _ hatches: [DrawingProjectionResult.SectionHatchSegment],
        transform: Transform,
        options: Options,
        in context: CGContext
    ) {
        apply(style: options.style.sectionHatch, in: context)
        for hatch in hatches {
            drawLine(start: hatch.start2D, end: hatch.end2D, transform: transform, in: context)
        }
    }

    private func drawSectionContours(
        _ contours: [DrawingProjectionResult.SectionContour],
        transform: Transform,
        options: Options,
        in context: CGContext
    ) {
        apply(style: options.style.sectionContour, in: context)
        for contour in contours where contour.projectedPoints2D.count >= 2 {
            drawPath(points: contour.projectedPoints2D, closes: true, transform: transform, in: context)
        }
    }

    private func drawAnnotations(
        _ annotations: [DrawingProjectionResult.Annotation],
        transform: Transform,
        options: Options,
        in context: CGContext
    ) {
        apply(style: options.style.annotation, in: context)
        for annotation in annotations {
            let points = annotation.anchors.map { $0.point2D }
            if points.count >= 2 {
                drawPath(points: points, closes: false, transform: transform, in: context)
            }
            if let leaderStart = annotation.labelLayout?.leaderStart2D,
               let leaderEnd = annotation.labelLayout?.leaderEnd2D {
                drawLine(start: leaderStart, end: leaderEnd, transform: transform, in: context)
            }
            for point in points {
                drawAnchor(point, transform: transform, in: context)
            }
        }
    }

    private func apply(
        style: DrawingProjectionLayerStyle,
        in context: CGContext
    ) {
        context.setStrokeColor(
            CGColor(
                red: normalizedChannel(style.color.red),
                green: normalizedChannel(style.color.green),
                blue: normalizedChannel(style.color.blue),
                alpha: 1.0
            )
        )
        context.setLineWidth(max(style.strokeWidth, 0.25))
        context.setLineDash(
            phase: 0.0,
            lengths: style.dashPattern.map { CGFloat($0) }
        )
    }

    private func drawLine(
        start: Point2D,
        end: Point2D,
        transform: Transform,
        in context: CGContext
    ) {
        context.beginPath()
        context.move(to: transform.point(start))
        context.addLine(to: transform.point(end))
        context.strokePath()
    }

    private func drawPath(
        points: [Point2D],
        closes: Bool,
        transform: Transform,
        in context: CGContext
    ) {
        guard let first = points.first else {
            return
        }
        context.beginPath()
        context.move(to: transform.point(first))
        for point in points.dropFirst() {
            context.addLine(to: transform.point(point))
        }
        if closes {
            context.closePath()
        }
        context.strokePath()
    }

    private func drawAnchor(
        _ point: Point2D,
        transform: Transform,
        in context: CGContext
    ) {
        let center = transform.point(point)
        let radius = 2.5
        context.strokeEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2.0,
                height: radius * 2.0
            )
        )
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
        var bounds: Bounds
        if let reportedBounds,
           reportedBounds.minX.isFinite,
           reportedBounds.minY.isFinite,
           reportedBounds.maxX.isFinite,
           reportedBounds.maxY.isFinite,
           reportedBounds.maxX >= reportedBounds.minX,
           reportedBounds.maxY >= reportedBounds.minY {
            bounds = Bounds(
                minX: reportedBounds.minX,
                minY: reportedBounds.minY,
                maxX: reportedBounds.maxX,
                maxY: reportedBounds.maxY
            )
        } else {
            bounds = Bounds(
                minX: Double.infinity,
                minY: Double.infinity,
                maxX: -Double.infinity,
                maxY: -Double.infinity
            )
        }

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
            if let leaderStart = annotation.labelLayout?.leaderStart2D {
                bounds.include(leaderStart)
            }
            if let leaderEnd = annotation.labelLayout?.leaderEnd2D {
                bounds.include(leaderEnd)
            }
            for anchor in annotation.anchors {
                bounds.include(anchor.point2D)
            }
        }

        if !bounds.minX.isFinite || !bounds.minY.isFinite || !bounds.maxX.isFinite || !bounds.maxY.isFinite {
            return Bounds(minX: -0.5, minY: -0.5, maxX: 0.5, maxY: 0.5)
        }
        if abs(bounds.width) <= 1.0e-12 {
            bounds.minX -= 0.5
            bounds.maxX += 0.5
        }
        if abs(bounds.height) <= 1.0e-12 {
            bounds.minY -= 0.5
            bounds.maxY += 0.5
        }
        return bounds
    }

    private func transform(options: Options, bounds: Bounds) -> Transform {
        let drawableWidth = max(options.width - options.padding * 2.0, 1.0)
        let drawableHeight = max(options.height - options.padding * 2.0, 1.0)
        let xScale = drawableWidth / max(bounds.width, 1.0e-12)
        let yScale = drawableHeight / max(bounds.height, 1.0e-12)
        let scale = min(xScale, yScale)
        let renderedWidth = bounds.width * scale
        let renderedHeight = bounds.height * scale
        return Transform(
            canvasWidth: options.width,
            canvasHeight: options.height,
            bounds: bounds,
            scale: scale,
            offsetX: (options.width - renderedWidth) / 2.0,
            offsetY: (options.height - renderedHeight) / 2.0
        )
    }

    private func normalizedOptions() -> Options {
        let fallback = DrawingProjectionExportStyle.technical()
        return Options(
            width: normalizedPositive(options.width, fallback: 1024.0),
            height: normalizedPositive(options.height, fallback: 1024.0),
            padding: max(options.padding.isFinite ? options.padding : 32.0, 0.0),
            pixelScale: normalizedPositive(options.pixelScale, fallback: 2.0),
            pagePreset: options.pagePreset,
            style: options.style.normalized(fallback: fallback)
        )
    }

    private func normalizedPositive(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite, value > 0.0 else {
            return fallback
        }
        return value
    }

    private func normalizedChannel(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0.0
        }
        return min(max(value, 0.0), 1.0)
    }
}
