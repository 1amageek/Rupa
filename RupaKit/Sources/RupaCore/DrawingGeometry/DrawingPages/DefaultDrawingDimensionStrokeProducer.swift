import SwiftCAD

/// Original current measurement anchors mapped once, then explicit paper layout.
public struct DefaultDrawingDimensionStrokeProducer: DrawingDimensionStrokeProducing {
    private let angularCurves: any OriginalRootSpanDrawingLinearizing
    public init(angularCurves: any OriginalRootSpanDrawingLinearizing = DefaultOriginalRootSpanDrawingLinearizer()) {
        self.angularCurves = angularCurves
    }

    public func paths(annotation: DrawingProjectionResult.Annotation, layout: DrawingDimensionLayout,
        options: DrawingGeometricPageOptions, usage: inout DrawingExchangeUsage) throws -> [DrawingPagePath] {
        try build(annotation: annotation, layout: layout, options: options,
            radialMeasurement: nil, frame: nil, usage: &usage)
    }

    public func paths(annotation: DrawingProjectionResult.Annotation, layout: DrawingDimensionLayout,
        options: DrawingGeometricPageOptions, radialMeasurement: DrawingRadialDimensionMeasurement?,
        frame: OrthographicProjectionFrame, usage: inout DrawingExchangeUsage) throws -> [DrawingPagePath] {
        if let radialMeasurement {
            guard radialMeasurement.annotation.id == annotation.id,
                radialMeasurement.annotation.measurementID == annotation.measurementID,
                radialMeasurement.annotation.kind == annotation.kind else {
                throw invalid("Radial dimension source belongs to another original annotation.")
            }
            guard case .radial = layout.geometry else {
                throw invalid("Original circular dimension source requires an explicit radial layout.")
            }
        }
        return try build(annotation: annotation, layout: layout, options: options,
            radialMeasurement: radialMeasurement, frame: frame, usage: &usage)
    }

    private func build(annotation: DrawingProjectionResult.Annotation, layout: DrawingDimensionLayout,
        options: DrawingGeometricPageOptions, radialMeasurement: DrawingRadialDimensionMeasurement?,
        frame: OrthographicProjectionFrame?, usage: inout DrawingExchangeUsage) throws -> [DrawingPagePath] {
        try usage.check(); try usage.charge(work: 1)
        try layout.validate()
        guard annotation.id == layout.annotationID else { throw invalid("Paper dimension uses a different original annotation.") }
        let capacity: Int
        if case .angular = layout.geometry { capacity = 12 } else { capacity = 9 }
        try usage.charge(bytes: capacity * MemoryLayout<DrawingPagePath>.stride)
        var result: [DrawingPagePath] = []; result.reserveCapacity(capacity)
        var ordinal = 0
        func paper(_ anchor: DrawingProjectionResult.AnnotationAnchor) throws -> Point2D {
            try DrawingPaperMapper(options: options).map(anchor.point2D)
        }
        func moved(_ point: Point2D, _ direction: Point2D, _ length: Double) throws -> Point2D {
            let value = Point2D(x: point.x + direction.x * length, y: point.y + direction.y * length)
            guard value.x.isFinite, value.y.isFinite else { throw invalid("Paper dimension coordinate overflowed.") }
            return value
        }
        func direction(_ first: Point2D, _ second: Point2D) throws -> Point2D {
            let x = second.x - first.x, y = second.y - first.y
            let scale = max(abs(x), abs(y))
            guard scale.isFinite, scale > 0 else { throw invalid("Original dimension anchors collapse in the current projection.") }
            let u = x / scale, v = y / scale
            let length = (u * u + v * v).squareRoot()
            return Point2D(x: u / length, y: v / length)
        }
        func append(_ first: Point2D, _ second: Point2D, usage: inout DrawingExchangeUsage) throws {
            guard result.count < capacity else { throw invalid("Paper dimension stroke capacity is exhausted.") }
            let bytes = layout.annotationID.utf8.count.addingReportingOverflow(32 + 2 * MemoryLayout<Point2D>.stride)
            guard !bytes.overflow else { throw invalid("Paper dimension identity storage overflowed.") }
            try usage.charge(entities: 1, work: 1, bytes: bytes.partialValue)
            let identity = layout.annotationID + ".dimension." + String(ordinal); ordinal += 1
            let source: DrawingRadialDimensionSource?
            if let radialMeasurement, let frame {
                source = try DrawingRadialDimensionSource(original: radialMeasurement.original,
                    bodyID: radialMeasurement.bodyID, sourceFeatureID: radialMeasurement.sourceFeatureID,
                    sourceSketchEntityID: radialMeasurement.sourceSketchEntityID,
                    occurrenceIdentity: radialMeasurement.occurrenceID?.description,
                    measurementIdentity: annotation.measurementID.description, identity: identity,
                    kind: annotation.kind == .radius ? .radius : .diameter,
                    frame: frame, pointsPerMeter: options.pointsPerMeter, translation: options.translation, usage: &usage)
            } else { source = nil }
            result.append(.init(points: [first, second], identity: identity, role: .annotation,
                originalRadialDimension: source))
        }
        func arrow(at tip: Point2D, toward direction: Point2D, usage: inout DrawingExchangeUsage) throws {
            switch layout.style.arrowKind {
            case .none: return
            case .open, .closedOutline: break
            }
            let base = try moved(tip, direction, layout.style.arrowLength)
            let normal = Point2D(x: -direction.y, y: direction.x)
            let left = try moved(base, normal, layout.style.arrowWidth * 0.5)
            let right = try moved(base, normal, -layout.style.arrowWidth * 0.5)
            try append(left, tip, usage: &usage); try append(tip, right, usage: &usage)
            if case .closedOutline = layout.style.arrowKind { try append(right, left, usage: &usage) }
        }
        func endpoints() throws -> (DrawingProjectionResult.AnnotationAnchor, DrawingProjectionResult.AnnotationAnchor) {
            guard annotation.anchors.count >= 2 else { throw invalid("Original dimension has fewer than two source anchors.") }
            if let first = annotation.anchors.first(where: { $0.role == .start }),
               let last = annotation.anchors.first(where: { $0.role == .end }) { return (first, last) }
            return (annotation.anchors[0], annotation.anchors[1])
        }
        try usage.check()
        switch layout.geometry {
        case .linear(let offset):
            guard annotation.kind == .distance || annotation.kind == .diameter, annotation.measurementMeters != nil else {
                throw invalid("Linear paper layout requires a current original distance or two-endpoint diameter.")
            }
            guard !annotation.anchors.contains(where: { $0.role == .center }) || annotation.kind == .distance else {
                throw invalid("Center-bound diameter needs the original radial layout.")
            }
            let anchors = try endpoints(); let first = try paper(anchors.0), last = try paper(anchors.1)
            let axis = try direction(first, last), normal = Point2D(x: -axis.y, y: axis.x)
            let start = try moved(first, normal, offset), end = try moved(last, normal, offset)
            try append(start, end, usage: &usage)
            if offset != 0 {
                let signed = offset > 0 ? normal : Point2D(x: -normal.x, y: -normal.y)
                try append(moved(first, signed, layout.style.extensionGap),
                    moved(start, signed, layout.style.extensionOvershoot), usage: &usage)
                try append(moved(last, signed, layout.style.extensionGap),
                    moved(end, signed, layout.style.extensionOvershoot), usage: &usage)
            }
            try arrow(at: start, toward: axis, usage: &usage)
            try arrow(at: end, toward: Point2D(x: -axis.x, y: -axis.y), usage: &usage)
        case .radial(let overshoot):
            guard annotation.kind == .radius || annotation.kind == .diameter, annotation.measurementMeters != nil,
                  let centerAnchor = annotation.anchors.first(where: { $0.role == .center }),
                  let boundary = annotation.anchors.first(where: { $0.role != .center }) else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Single topology radius anchors
                // need an original current center/boundary receipt before strokes.
                throw invalid("Radial paper dimension needs original current center and boundary anchors.")
            }
            let center = try paper(centerAnchor), end = try paper(boundary), axis = try direction(center, end)
            let start = annotation.kind == .diameter
                ? Point2D(x: center.x - (end.x - center.x), y: center.y - (end.y - center.y)) : center
            guard start.x.isFinite, start.y.isFinite else { throw invalid("Original diameter projection overflowed.") }
            try append(start, moved(end, axis, overshoot), usage: &usage)
            try arrow(at: end, toward: Point2D(x: -axis.x, y: -axis.y), usage: &usage)
            if annotation.kind == .diameter { try arrow(at: start, toward: axis, usage: &usage) }
        case .boundary:
            guard annotation.kind == .area || annotation.kind == .perimeter, annotation.anchors.count >= 3 else {
                throw invalid("Boundary dimension requires a current original point-anchored area or perimeter.")
            }
            // Admit the entire boundary rather than publishing a partially traversed polygon.
            let count = annotation.anchors.count.addingReportingOverflow(1)
            let bytes = count.partialValue.multipliedReportingOverflow(by: MemoryLayout<Point2D>.stride)
            let textBytes = layout.annotationID.utf8.count.addingReportingOverflow(32)
            let total = bytes.partialValue.addingReportingOverflow(textBytes.partialValue)
            guard !count.overflow, !bytes.overflow, !textBytes.overflow, !total.overflow else { throw invalid("Dimension boundary storage overflowed.") }
            try usage.charge(entities: 1, work: annotation.anchors.count, bytes: total.partialValue)
            var points: [Point2D] = []; points.reserveCapacity(count.partialValue)
            for anchor in annotation.anchors { try usage.check(); points.append(try paper(anchor)) }
            let identity = layout.annotationID + ".dimension.boundary"
            // Closed boundary explicitly repeats the first original point in admitted capacity.
            points.append(points[0])
            result.append(.init(points: points, identity: identity, role: .annotation))
        case .angular(let radius):
            guard let paperTolerance = options.paperTolerance else {
                throw invalid("Original angular paper layout requires explicit caller paper tolerance.")
            }
            let sector = try OriginalDrawingAngularSector(annotation: annotation, radius: radius,
                options: options, paperTolerance: paperTolerance, usage: &usage)
            var firstTip: Point2D?, lastTip: Point2D?
            // FIXME(INCOMPLETE_IMPLEMENTATION): The public angular path retains
            // original direction roots and exact paper action. Selected native endpoint
            // re-admission is connected in the lower query; full success/failure
            // publication still requires deferred behavioral verification and
            // other mandatory drawing source families before full D4 closure.
            for span in sector.spans {
                let path = try angularCurves.linearize(span, operationWord: sector.operationWord,
                    maximumDeviation: options.maximumCurveDeviation, usage: &usage)
                guard let first = path.samples.first, let last = path.samples.last, path.samples.count >= 2 else {
                    throw invalid("Original angular source has no complete bounded paper path.")
                }
                if firstTip == nil { firstTip = first.point }; lastTip = last.point
                let sampleBytes = path.samples.count.multipliedReportingOverflow(by:
                    MemoryLayout<Point2D>.stride)
                let identityBytes = layout.annotationID.utf8.count.addingReportingOverflow(48)
                guard !sampleBytes.overflow, !identityBytes.overflow else {
                    throw invalid("Original angular path storage overflowed.")
                }
                try usage.charge(entities: 1, bytes: sampleBytes.partialValue)
                try usage.charge(bytes: identityBytes.partialValue)
                var points: [Point2D] = []
                points.reserveCapacity(path.samples.count)
                for sample in path.samples {
                    try usage.charge(work: 1)
                    points.append(sample.point)
                }
                let identity = layout.annotationID + ".dimension.arc." + String(ordinal); ordinal += 1
                result.append(.init(points: points, identity: identity, role: .annotation,
                    originalRootSpanPath: path))
            }
            guard let start = firstTip, let end = lastTip else { throw invalid("Original angular sector has no endpoints.") }
            let mapper = DrawingPaperMapper(options: options)
            let center = try mapper.map(sector.originalCenter)
            let startAxis = try direction(center, start), endAxis = try direction(center, end)
            let firstAnchor = try mapper.map(sector.originalFirst)
            let secondAnchor = try mapper.map(sector.originalSecond)
            if firstAnchor != start {
                let extensionAxis = try direction(firstAnchor, start)
                try append(moved(firstAnchor, extensionAxis, layout.style.extensionGap),
                    moved(start, extensionAxis, layout.style.extensionOvershoot), usage: &usage)
            }
            if secondAnchor != end {
                let extensionAxis = try direction(secondAnchor, end)
                try append(moved(secondAnchor, extensionAxis, layout.style.extensionGap),
                    moved(end, extensionAxis, layout.style.extensionOvershoot), usage: &usage)
            }
            let sign: Double = sector.isCounterclockwise ? 1 : -1
            try arrow(at: start, toward: .init(x: -startAxis.y * sign, y: startAxis.x * sign), usage: &usage)
            try arrow(at: end, toward: .init(x: endAxis.y * sign, y: -endAxis.x * sign), usage: &usage)
        }
        try usage.check(); return result
    }

    private func invalid(_ message: String) -> EditorError {
        EditorError(code: .evaluationFailed, message: message)
    }
}
