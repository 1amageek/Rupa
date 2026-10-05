import SwiftCAD

/// Converts retained original world section laws into the existing single-map paper publication.
struct DrawingSectionPageComposer {
    let curves: any BRepDrawingCurveLinearizing

    func compose(base: DrawingExchangePage, projection: DrawingOccurrenceProjection,
                 sections: DrawingOccurrenceSections, contributions: [DrawingSectionPageContribution],
                 evaluated: EvaluatedDocument, options: DrawingGeometricPageOptions,
                 usage: inout DrawingExchangeUsage) throws -> DrawingExchangePage {
        let mapper = DrawingPaperMapper(options: options)
        let frame = projection.original.frame
        let sourceDeviation = ((options.maximumCurveDeviation / 2).nextDown / options.pointsPerMeter).nextDown
        guard sourceDeviation.isFinite, sourceDeviation > 0 else { throw invalid("Section page precision is exhausted.") }
        try charge(base.paths.count, stride: MemoryLayout<DrawingPagePath>.stride, usage: &usage)
        // The base path records are copied only at the final output composition boundary;
        // immutable point/parameter buffers remain shared until a new path is appended.
        var paths = base.paths
        try charge(base.regions.count, stride: MemoryLayout<DrawingPageRegion>.stride, usage: &usage)
        var regions = base.regions

        func paperPath(_ curve: OrthographicProjectedCurve, from start: Double, to end: Double,
                       maximumDeviation: Double? = nil, usage: inout DrawingExchangeUsage) throws -> (points: [Point2D], parameters: [Double]) {
            let source = try curves.linearize(curve, from: start, to: end,
                maximumDeviation: maximumDeviation ?? sourceDeviation, usage: &usage)
            try charge(source.samples.count, stride: MemoryLayout<Point2D>.stride + MemoryLayout<Double>.stride, usage: &usage)
            var points: [Point2D] = [], parameters: [Double] = []
            points.reserveCapacity(source.samples.count); parameters.reserveCapacity(source.samples.count)
            for sample in source.samples {
                try usage.check(); try usage.charge(work: 1)
                points.append(try mapper.map(sample.point)); parameters.append(sample.parameter)
            }
            return (points, parameters)
        }
        func append(_ curve: Curve3D, from start: Double, to end: Double, identity: String,
                    role: DrawingPageStrokeRole, usage: inout DrawingExchangeUsage) throws {
            try usage.check(); try usage.charge(entities: 1, work: 1, bytes: MemoryLayout<DrawingPagePath>.stride)
            let projected = try DefaultOrthographicCurveProjector().project(curve, onto: frame,
                tolerance: evaluated.configuration.tolerance)
            let piece = try paperPath(projected, from: start, to: end, usage: &usage)
            paths.append(DrawingPagePath(points: piece.points, identity: identity,
                role: role, originalParameters: piece.parameters))
        }
        for (sectionIndex, contribution) in contributions.enumerated() {
            let original = sections.values[sectionIndex]
            let section = original.original
            let prefix = try identity(original.occurrence.original.identity, suffix: ".section.",
                ordinal: sectionIndex, usage: &usage)
            for component in section.components {
                try usage.check(); try usage.charge(work: 1)
                let sourceIdentity = try identity(prefix, suffix: ".component.", ordinal: component.ordinal, usage: &usage)
                switch component.geometry {
                case .transverseSegment(let first, let last):
                    try usage.charge(work: 2, bytes: MemoryLayout<BSplineCurve3D>.stride)
                    try charge(2, stride: MemoryLayout<Point3D>.stride, usage: &usage)
                    try charge(6, stride: MemoryLayout<Double>.stride, usage: &usage)
                    let curve = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                        controlPoints: [first.point, last.point], weights: [1, 1]))
                    try append(curve, from: 0, to: 1, identity: sourceIdentity, role: .sectionContour, usage: &usage)
                case .closedCurve(let closed):
                    let start: Double, end: Double
                    switch closed.intersection.curve.parameterDomain {
                    case .periodic(let period): start = 0; end = period
                    case .closed(let lower, let upper): start = lower; end = upper
                    case .unbounded: throw invalid("Closed section has no retained finite native domain.")
                    }
                    try append(closed.intersection.curve, from: start, to: end,
                        identity: sourceIdentity, role: .sectionContour, usage: &usage)
                case .trimmedCurve(let chain):
                    for (ordinal, segment) in chain.segments.enumerated() {
                        let name = try identity(sourceIdentity, suffix: ".span.", ordinal: ordinal, usage: &usage)
                        try append(segment.intersection.curve, from: segment.startParameter, to: segment.endParameter,
                            identity: name, role: .sectionContour, usage: &usage)
                    }
                case .tangent(let contact):
                    try usage.charge(entities: 1, bytes: MemoryLayout<DrawingPagePath>.stride + MemoryLayout<Point2D>.stride)
                    let point = try paperPoint(contact.point, frame: frame, mapper: mapper)
                    paths.append(DrawingPagePath(points: [point], identity: sourceIdentity, role: .sectionContour))
                case .coincident:
                    try section.visitCoincidentContours(componentOrdinal: component.ordinal, in: evaluated,
                        consumeUse: { _ in try usage.check(); try usage.charge(entities: 1, work: 1) },
                        visit: { loopID, ordinal, edge in
                            let name = try identity(sourceIdentity, suffix: ".coedge.", ordinal: ordinal, usage: &usage)
                            // Loop identity remains original source provenance even when ordinals repeat.
                            // Portable original topology identities format as thirty-six canonical bytes.
                            try usage.charge(bytes: 36)
                            let completeName = try identity(name, suffix: ".loop.", text: loopID.description, usage: &usage)
                            try usage.charge(bytes: MemoryLayout<DrawingPagePath>.stride)
                            let piece = try paperPath(edge.curve, from: edge.startParameter, to: edge.endParameter, usage: &usage)
                            paths.append(DrawingPagePath(points: piece.points, identity: completeName,
                                role: .sectionContour, originalParameters: piece.parameters))
                        })
                }
            }
            for (ordinal, region) in contribution.regions.enumerated() {
                try region.validateCurrent(evaluated, for: section)
                try region.patch.validate(tolerance: evaluated.configuration.tolerance)
                try usage.charge(entities: 1, work: 1, bytes: MemoryLayout<DrawingPageRegion>.stride)
                try charge(region.patch.loops.count, stride: MemoryLayout<[Point2D]>.stride + MemoryLayout<Bool>.stride, usage: &usage)
                var loops: [[Point2D]] = [], outer: [Bool] = []
                for loop in region.patch.loops {
                    var points: [Point2D] = []
                    for edge in loop.edges {
                        try usage.check(); try usage.charge(work: 1)
                        let projected = try DefaultOrthographicCurveProjector().project(edge.curve,
                            onto: frame, tolerance: evaluated.configuration.tolerance)
                        let regionDeviation = ((options.maximumCurveDeviation / 4).nextDown / options.pointsPerMeter).nextDown
                        guard regionDeviation.isFinite, regionDeviation > 0 else { throw invalid("Material loop precision is exhausted.") }
                        let piece = try paperPath(projected, from: edge.startParameter, to: edge.endParameter,
                            maximumDeviation: regionDeviation, usage: &usage)
                        if let previous = points.last, let first = piece.points.first {
                            try admitJoin(previous, first, maximumDeviation: (options.maximumCurveDeviation / 4).nextDown)
                        }
                        let count = points.isEmpty ? piece.points.count : max(0, piece.points.count - 1)
                        try charge(count, stride: MemoryLayout<Point2D>.stride, usage: &usage)
                        if points.isEmpty { points.append(contentsOf: piece.points) }
                        else { points.append(contentsOf: piece.points.dropFirst()) }
                    }
                    guard points.count >= 4 else { throw invalid("Original material loop has no complete closed paper contour.") }
                    guard let first = points.first, let last = points.last else { throw invalid("Material loop is empty.") }
                    try admitJoin(last, first, maximumDeviation: (options.maximumCurveDeviation / 4).nextDown)
                    points[points.count - 1] = first
                    loops.append(points); outer.append(loop.role == .outer)
                }
                let name = try identity(prefix, suffix: ".material.", ordinal: ordinal, usage: &usage)
                regions.append(DrawingPageRegion(identity: name, loops: loops, outer: outer))
            }
            for (ordinal, segment) in contribution.hatchSegments.enumerated() {
                try segment.validateCurrent(evaluated, for: section)
                guard segment.start.y == segment.end.y else { throw invalid("Original hatch row is inconsistent.") }
                let curve = try segment.originalCurve(in: evaluated, for: section,
                    maximumSourceDepth: min(16, usage.maximumNesting),
                    maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
                    maximumAlgebraicDepth: usage.maximumAlgebraicDepth, usage: &usage)
                let name = try identity(prefix, suffix: ".hatch.", ordinal: ordinal, usage: &usage)
                try append(curve, from: 0, to: 1,
                    identity: name, role: .sectionHatch, usage: &usage)
            }
        }
        return DrawingExchangePage(width: base.width, height: base.height, paths: paths, glyphs: base.glyphs,
            styles: base.styles, maximumGlyphDeviation: base.maximumGlyphDeviation, regions: regions, resolvedGlyphBoundaries: base.resolvedGlyphBoundaries)
    }

    private func paperPoint(_ point: Point3D, frame: OrthographicProjectionFrame,
                            mapper: DrawingPaperMapper) throws -> Point2D {
        func coordinate(_ direction: Vector3D) throws -> (value: Double, error: Double) {
            var lower = 0.0, upper = 0.0, value = 0.0
            for (source, origin, coefficient) in [(point.x, frame.origin.x, direction.x),
                                                 (point.y, frame.origin.y, direction.y),
                                                 (point.z, frame.origin.z, direction.z)] {
                let difference = source - origin
                let a = difference.nextDown * coefficient, b = difference.nextUp * coefficient
                lower = (lower + min(a, b).nextDown).nextDown
                upper = (upper + max(a, b).nextUp).nextUp
                value += difference * coefficient
                guard difference.isFinite, a.isFinite, b.isFinite, lower.isFinite, upper.isFinite, value.isFinite else {
                    throw invalid("Original section contact projection is nonfinite.")
                }
            }
            return (value, max(abs(value - lower), abs(upper - value)).nextUp)
        }
        let x = try coordinate(frame.horizontal), y = try coordinate(frame.vertical)
        return try mapper.map(Point2D(x: x.value, y: y.value), sourceError: (x.error + y.error).nextUp)
    }

    private func admitJoin(_ first: Point2D, _ last: Point2D, maximumDeviation: Double) throws {
        let x = (first.x - last.x), y = (first.y - last.y)
        let bound = (max(abs(x.nextDown), abs(x.nextUp)) + max(abs(y.nextDown), abs(y.nextUp))).nextUp
        guard bound.isFinite, bound <= maximumDeviation else {
            throw invalid("Original material endpoint correspondence exceeds the caller's page deviation.")
        }
    }

    private func identity(_ base: String, suffix: String, ordinal: Int,
                          usage: inout DrawingExchangeUsage) throws -> String {
        // Decimal Int formatting owns at most twenty bytes, admitted before allocation.
        try usage.charge(bytes: 20)
        return try identity(base, suffix: suffix, text: String(ordinal), usage: &usage)
    }
    private func identity(_ base: String, suffix: String, text: String,
                          usage: inout DrawingExchangeUsage) throws -> String {
        let first = base.utf8.count.addingReportingOverflow(suffix.utf8.count)
        let total = first.partialValue.addingReportingOverflow(text.utf8.count)
        guard !first.overflow, !total.overflow else { throw invalid("Section identity admission overflowed.") }
        try usage.charge(bytes: total.partialValue)
        return base + suffix + text
    }
    private func charge(_ count: Int, stride: Int, usage: inout DrawingExchangeUsage) throws {
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, !bytes.overflow else { throw invalid("Section paper allocation admission overflowed.") }
        try usage.charge(bytes: bytes.partialValue)
    }
    private func invalid(_ message: String) -> EditorError { EditorError(code: .evaluationFailed, message: message) }
}
