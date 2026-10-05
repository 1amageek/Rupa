import SwiftCAD

/// Converts Native outline commands without flattening or changing their fill law.
public struct OriginalDrawingGlyphContourBuilder: DrawingGlyphContourBuilding {
    public init() {}

    public func contours(_ outline: DrawingGlyphOutline, nextIdentity: inout UInt64,
                         usage: inout DrawingExchangeUsage) throws -> DrawingGlyphContours {
        var identity = nextIdentity
        func allocateIdentity() throws -> UInt64 {
            let next = identity.addingReportingOverflow(1)
            guard !next.overflow else { throw invalid("Original glyph identity capacity is exhausted.") }
            let result = identity; identity = next.partialValue; return result
        }
        func reserve<T>(_ count: Int, _ type: T.Type, usage: inout DrawingExchangeUsage) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
            guard count >= 0, !bytes.overflow else { throw invalid("Original glyph storage admission overflowed.") }
            try usage.charge(bytes: bytes.partialValue)
        }
        try usage.check()
        guard !outline.identity.isEmpty, !outline.fontPostScriptName.isEmpty,
            outline.fontSize.isFinite, outline.fontSize > 0 else {
            throw invalid("Original glyph contour provenance or font size is invalid.")
        }
        try reserve(outline.commands.count, OriginalPlanarContour.self, usage: &usage)
        var contours: [OriginalPlanarContour] = []; contours.reserveCapacity(outline.commands.count)
        var segments: [OriginalPlanarContourSegment] = []
        var segmentCapacity = 0
        var start: Point2D?
        var current: Point2D?
        var startID: UInt64?
        var currentID: UInt64?
        var contourID: UInt64?

        func point(_ value: Point2D) throws -> Point3D {
            guard value.x.isFinite, value.y.isFinite else { throw invalid("Original glyph control is nonfinite.") }
            return Point3D(x: value.x, y: value.y, z: 0)
        }
        func append(end: Point2D, first: Point2D? = nil, second: Point2D? = nil,
                    usage: inout DrawingExchangeUsage) throws {
            guard let from = current, let fromID = currentID, let start, let startID else {
                throw invalid("Original glyph drawing command has no current contour point.")
            }
            if contourID == nil { contourID = try allocateIdentity() }
            let degree = second != nil ? 3 : first != nil ? 2 : 1
            try usage.charge(entities: 1, work: degree + 1)
            try reserve(degree + 1, Point3D.self, usage: &usage)
            try reserve(3 * (degree + 1), Double.self, usage: &usage)
            if segments.count == segmentCapacity {
                let doubled = segmentCapacity.multipliedReportingOverflow(by: 2)
                guard !doubled.overflow else { throw invalid("Original glyph segment capacity overflowed.") }
                let capacity = max(1, doubled.partialValue)
                // Both old and new allocations may coexist during contiguous growth.
                try reserve(capacity, OriginalPlanarContourSegment.self, usage: &usage)
                segments.reserveCapacity(capacity); segmentCapacity = capacity
            }
            var controls: [Point3D] = []; controls.reserveCapacity(degree + 1)
            controls.append(try point(from))
            if let first { controls.append(try point(first)) }
            if let second { controls.append(try point(second)) }
            controls.append(try point(end))
            var knots = [Double](repeating: 0, count: 2 * (degree + 1))
            for index in (degree + 1)..<knots.count { knots[index] = 1 }
            let weights = [Double](repeating: 1, count: degree + 1)
            let endID = end == start ? startID : try allocateIdentity()
            let segmentID = try allocateIdentity()
            segments.append(OriginalPlanarContourSegment(id: segmentID, startVertexID: fromID,
                endVertexID: endID, curve: BSplineCurve3D(degree: degree, knots: knots,
                    controlPoints: controls, weights: weights)))
            current = end; currentID = endID
        }
        func close(clearCursor: Bool = true, usage: inout DrawingExchangeUsage) throws {
            guard let firstPoint = start, let lastPoint = current else { return }
            if !segments.isEmpty, lastPoint != firstPoint { try append(end: firstPoint, usage: &usage) }
            if !segments.isEmpty {
                guard let contourID else { throw invalid("Original glyph contour identity is absent.") }
                contours.append(OriginalPlanarContour(id: contourID, segments: segments))
            }
            segments = []; segmentCapacity = 0; contourID = nil
            if clearCursor { start = nil; current = nil; startID = nil; currentID = nil }
            else { current = firstPoint; currentID = startID }
        }
        for command in outline.commands {
            try usage.check(); try usage.charge(work: 1)
            switch command {
            case .move(let value):
                try close(usage: &usage); _ = try point(value)
                let id = try allocateIdentity(); contourID = try allocateIdentity()
                start = value; current = value; startID = id; currentID = id
            case .line(let end): try append(end: end, usage: &usage)
            case .quadratic(let control, let end): try append(end: end, first: control, usage: &usage)
            case .cubic(let first, let second, let end): try append(end: end, first: first, second: second, usage: &usage)
            case .close: try close(clearCursor: false, usage: &usage)
            }
        }
        try close(usage: &usage)
        guard !contours.isEmpty || outline.text.allSatisfy(\.isWhitespace) else {
            throw invalid("A non-whitespace original glyph has no drawable closed contours.")
        }
        try usage.check(); nextIdentity = identity
        return DrawingGlyphContours(outline: outline, contours: contours)
    }

    private func invalid(_ message: String) -> EditorError {
        EditorError(code: .evaluationFailed, message: message)
    }
}
