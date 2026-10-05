import SwiftCAD

/// One live contour invocation sharing the complete page's original accounting owner.
public struct DrawingSilhouettePreparation: Sendable {
    public let policy: DrawingSilhouettePolicy
    private let admission: DrawingSilhouetteAdmission
    private var silhouetteUsage: SurfaceSilhouetteUsage

    public init(policy: DrawingSilhouettePolicy, usage: inout DrawingExchangeUsage) throws {
        try policy.validate(); try usage.check()
        self.policy = policy
        let admission = try DrawingSilhouetteAdmission(usage: &usage)
        self.admission = admission
        silhouetteUsage = try admission.createUsage(maximumWork: usage.maximumWork,
            maximumCells: policy.maximumCells, maximumStorage: usage.maximumBytes / MemoryLayout<UInt32>.stride,
            maximumDepth: usage.maximumCurveSubdivisionDepth, maximumAlgebraicDepth: usage.maximumAlgebraicDepth,
            maximumSourceDepth: min(16, usage.maximumNesting))
    }

    public mutating func silhouettes(_ projection: DrawingOccurrenceProjection,
        document: DesignDocument, evaluated: EvaluatedDocument, usage: inout DrawingExchangeUsage,
        producer: any DocumentDrawingSilhouetteProducing = DocumentDrawingSilhouetteProducer()) throws -> DrawingOccurrenceSilhouettes {
        try requireOwner(usage)
        try projection.validateCurrent(document: document, evaluated: evaluated)
        let placements = projection.exchangeProjection.placements
        let bytes = placements.count.multipliedReportingOverflow(by: MemoryLayout<BRepDrawingSilhouettes>.stride)
        guard !bytes.overflow else { throw invalid("Original silhouette receipt storage overflowed.") }
        try silhouetteUsage.preparationStorageCallback(bytes.partialValue)
        var values: [BRepDrawingSilhouettes] = []; values.reserveCapacity(placements.count)
        var faces = 0; var spans = 0
        for placement in placements {
            try usage.check()
            guard faces < policy.maximumSourceFaces, spans < policy.maximumProjectedSpans else {
                throw invalid("Whole-page original silhouette face or span capacity is exhausted.")
            }
            let value = try producer.silhouettes(placement, document: document.cadDocument,
                currentEvaluation: evaluated, onto: projection.original.frame,
                maximumSourceEntities: policy.maximumSourceEntities,
                maximumSourceFaces: policy.maximumSourceFaces - faces,
                maximumProjectedSpans: policy.maximumProjectedSpans - spans,
                maximumControlPointCount: policy.maximumControlPointCount,
                maximumBoundaryCurveCount: policy.maximumBoundaryCurveCount, usage: &silhouetteUsage)
            faces += value.originalFaces.count
            func appendCount(_ count: Int) throws {
                let next = spans.addingReportingOverflow(count)
                guard !next.overflow, next.partialValue <= policy.maximumProjectedSpans else {
                    throw invalid("Whole-page original silhouette span capacity is exhausted.")
                }
                spans = next.partialValue
            }
            try appendCount(value.spans.count); try appendCount(value.exactTrimmedSpans.count)
            try appendCount(value.contacts.count); try appendCount(value.algebraicContacts.count)
            try appendCount(value.atlasStations.count); try appendCount(value.singularStations.count)
            try appendCount(value.collapsedCurves.count)
            values.append(try value.refiningAlgebraicPoints(maximumParameterWidth: policy.maximumParameterWidth, usage: &silhouetteUsage))
        }
        return DrawingOccurrenceSilhouettes(projection: projection, values: values)
    }

    /// Prepares original curve/silhouette events without claiming foreground visibility.
    public mutating func projectedContacts(_ contours: DrawingOccurrenceSilhouettes,
        document: DesignDocument, evaluated: EvaluatedDocument, maximumPartitions: Int,
        usage: inout DrawingExchangeUsage,
        producer: any DocumentDrawingProjectedContactPreparing = DocumentDrawingProjectedContactPreparer())
        throws -> BRepDrawingProjectedContacts {
        try requireOwner(usage)
        try contours.validateCurrent(document: document, evaluated: evaluated)
        return try producer.prepare(contours.projection.exchangeProjection, silhouettes: contours.values,
            document: evaluated.document, currentEvaluation: evaluated, maximumPartitions: maximumPartitions,
            usage: &silhouetteUsage)
    }

    /// Publishes original retained spans through the exact paper law and same admission.
    public mutating func paths(_ contours: DrawingOccurrenceSilhouettes,
        document: DesignDocument, evaluated: EvaluatedDocument, options: DrawingGeometricPageOptions,
        usage: inout DrawingExchangeUsage,
        linearizer: any OriginalSilhouetteDrawingLinearizing = DefaultOriginalSilhouetteDrawingLinearizer()) throws -> [DrawingPagePath] {
        try requireOwner(usage); try contours.validateCurrent(document: document, evaluated: evaluated)
        var paths: [DrawingPagePath] = []; var capacity = 0
        func append(_ span: BRepDrawingExactSilhouetteSpan, placement: String, ordinal: Int) throws {
            let source = try linearizer.linearize(span, pointsPerMeter: options.pointsPerMeter,
                translation: options.translation, maximumDeviation: options.maximumCurveDeviation,
                maximumParameterWidth: policy.maximumParameterWidth, admission: admission,
                usage: &usage, silhouetteUsage: &silhouetteUsage)
            let bytes = source.samples.count.multipliedReportingOverflow(by: MemoryLayout<Point2D>.stride)
            guard !bytes.overflow else { throw invalid("Original silhouette paper samples overflowed.") }
            try usage.charge(bytes: bytes.partialValue)
            var points: [Point2D] = []; points.reserveCapacity(source.samples.count)
            for sample in source.samples { try usage.charge(work: 1); points.append(sample.point) }
            if paths.count == capacity {
                let doubled = capacity.multipliedReportingOverflow(by: 2)
                guard !doubled.overflow else { throw invalid("Original silhouette paper capacity overflowed.") }
                capacity = max(1, doubled.partialValue)
                let storage = capacity.multipliedReportingOverflow(by: MemoryLayout<DrawingPagePath>.stride)
                guard !storage.overflow else { throw invalid("Original silhouette path storage overflowed.") }
                try usage.charge(bytes: storage.partialValue); paths.reserveCapacity(capacity)
            }
            let identityBytes = placement.utf8.count.addingReportingOverflow(160)
            guard !identityBytes.overflow else { throw invalid("Original silhouette identity overflowed.") }
            try usage.charge(bytes: identityBytes.partialValue)
            let identity = placement + ".silhouette." + String(ordinal) + ".face." + span.faceID.description
            paths.append(DrawingPagePath(points: points, identity: identity, role: .geometry,
                originalSilhouettePath: source))
        }
        for (placementIndex, value) in contours.values.enumerated() {
            let placement = contours.projection.exchangeProjection.placements[placementIndex].identity
            // FIXME(INCOMPLETE_IMPLEMENTATION): Point source/provenance is now
            // connected, but actual foreground visibility and all lower extraction
            // domains remain required before whole D1 drawing completion.
            var ordinal = 0
            for span in value.exactTrimmedSpans {
                try append(span, placement: placement, ordinal: ordinal); ordinal += 1
            }
            for span in value.spans {
                try append(span.exactSpan(usage: &silhouetteUsage), placement: placement, ordinal: ordinal); ordinal += 1
            }
            func point(_ selector: OriginalSilhouetteDrawingPoint.Selector) throws {
                let source = try OriginalSilhouetteDrawingPoint.project(value, selector: selector,
                    pointsPerMeter: options.pointsPerMeter, translation: options.translation,
                    maximumDeviation: options.maximumCurveDeviation, admission: admission,
                    usage: &usage, silhouetteUsage: &silhouetteUsage)
                if paths.count == capacity {
                    let doubled = capacity.multipliedReportingOverflow(by: 2)
                    guard !doubled.overflow else { throw invalid("Silhouette point path capacity overflowed.") }
                    capacity = max(1, doubled.partialValue)
                    let bytes = capacity.multipliedReportingOverflow(by: MemoryLayout<DrawingPagePath>.stride)
                    guard !bytes.overflow else { throw invalid("Silhouette point path storage overflowed.") }
                    try usage.charge(bytes: bytes.partialValue); paths.reserveCapacity(capacity)
                }
                let bytes = placement.utf8.count.addingReportingOverflow(80 + MemoryLayout<Point2D>.stride)
                guard !bytes.overflow else { throw invalid("Silhouette point identity overflowed.") }
                try usage.charge(bytes: bytes.partialValue)
                let identity = placement + ".silhouette.point." + String(ordinal); ordinal += 1
                paths.append(DrawingPagePath(points: [source.point], identity: identity, role: .geometry,
                    originalSilhouettePoint: source))
            }
            for index in value.contacts.indices { try point(.contact(index)) }
            for index in value.algebraicContacts.indices { try point(.algebraicContact(index)) }
            for index in value.atlasStations.indices { try point(.atlasStation(index)) }
            for index in value.singularStations.indices { try point(.singularStation(index)) }
            for index in value.collapsedCurves.indices { try point(.collapsedCurve(index)) }
        }
        return paths
    }

    private func requireOwner(_ usage: DrawingExchangeUsage) throws {
        guard admission.belongsToSameInvocation(as: usage, silhouetteUsage: silhouetteUsage) else {
            throw invalid("Original silhouette preparation belongs to a different page accountant.")
        }
    }
    private func invalid(_ message: String) -> EditorError {
        EditorError(code: .evaluationFailed, message: message)
    }
}
