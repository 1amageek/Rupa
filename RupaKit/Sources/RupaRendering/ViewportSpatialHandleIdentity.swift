import RupaCore
import RupaViewportScene

/// CAD operation identity for one prepared frame. Native entities carry only
/// the index into this table, never source or interaction authority.
enum ViewportSpatialHandleIdentity: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case planar
        case axis(ViewportCoordinateAxis)
        case localAxis(ViewportPolySplineSurfaceVertexLocalAxis)

        init(_ mode: ViewportPolySplineSurfaceVertexDragMode) {
            switch mode {
            case .planar: self = .planar
            case .axis(let axis): self = .axis(axis)
            case .localAxis(let axis, _): self = .localAxis(axis)
            }
        }
    }

    case sketchCurveHandle(ViewportSketchCurveHandleIdentity)
    case sketchDimension(ViewportSketchDimensionIdentity)
    case sketchPointHandle(ViewportSketchPointHandleIdentity)
    case bridgeCurveEndpoint(ViewportBridgeCurveEndpointHandleIdentity)
    case splineControlPoint(ViewportSplineControlPointIdentity)
    case splineControlPointSlide(ViewportSplineControlPointSlideHandleIdentity)
    case polySplineSurfaceVertex(featureID: FeatureID, componentID: SelectionComponentID, role: Role)
    case polySplineSurfaceVertexSlide(ViewportPolySplineSurfaceVertexSlideHandleIdentity)
    case surfaceControlPoint(ViewportSpatialReferenceAddress, role: Role)
    case surfaceControlPointSlide([ViewportSpatialReferenceAddress], direction: PolySplineSurfaceVertexSlideDirection)
    case surfaceTrimEndpoint(ViewportSpatialReferenceAddress, endpoint: SurfaceTrimEndpoint)
    case surfaceTrimControlPoint(ViewportSpatialReferenceAddress, index: Int)
    case surfaceFrame([ViewportSpatialReferenceAddress], displayID: SurfaceFrameDisplayID, axis: ViewportSurfaceFrameAxis)
    case regionOffset(ViewportRegionOffsetHandleIdentity)
    case edgeOffset(ViewportEdgeOffsetHandleIdentity)
    case slotWidth(ViewportSlotWidthHandleIdentity)
    case sketchVertexOffset(ViewportSketchVertexOffsetHandleIdentity)
    case patternArrayLinearAxis(ViewportPatternArrayLinearAxisHandleIdentity)
    case independentCopyExtrudeDistance(ViewportIndependentCopyExtrudeDistanceHandleIdentity)
    case independentCopyBodyDimension(ViewportIndependentCopyBodyDimensionHandleIdentity)
    case patternArrayRadialAngle(ViewportPatternArrayRadialAngleHandleIdentity)
    case patternArrayCopyCount(ViewportPatternArrayCopyCountHandleIdentity)
    case patternArrayCurveExtent(ViewportPatternArrayCurveExtentHandleIdentity)
    case patternArrayCurvePathPoint(ViewportPatternArrayCurvePathPointHandleIdentity)
    case patternArrayOutputMode(ViewportPatternArrayOutputModeHandleIdentity)
    case constructionPlane(ViewportConstructionPlaneHandleIdentity)
    case sketchTransform(ViewportSketchTransformHandleIdentity)
    case affordance(ViewportAffordanceTarget)

    /// Charges owned value/array storage and conservative UTF-8 backing, without
    /// walking CAD geometry or encoding another copy of the table.
    static func retainedByteCount(for table: [Self], limits: MeshSourcePresentationPlanLimits = .standard) throws -> Int {
        try retainedByteCount(for: table, capacity: table.capacity, limits: limits)
    }

    static func retainedByteCount(
        for table: some Collection<Self>, capacity: Int,
        limits: MeshSourcePresentationPlanLimits
    ) throws -> Int {
        try limits.validate()
        guard table.count <= limits.maxItemCount, capacity >= table.count else { throw RealityViewportSpatialBatch.exhausted() }
        if capacity == 0 { return 0 }
        var bytes = 0
        func charge(_ count: Int, stride: Int = 1) throws {
            try Task.checkCancellation()
            let size = count.multipliedReportingOverflow(by: stride)
            let next = bytes.addingReportingOverflow(size.partialValue)
            guard count >= 0, !size.overflow, !next.overflow,
                  next.partialValue <= limits.maxRetainedByteCount else { throw RealityViewportSpatialBatch.exhausted() }
            bytes = next.partialValue
        }
        func string(_ value: String) throws {
            try charge(32)
            try charge(value.utf8.count, stride: 2)
        }
        func target(_ value: SelectionTarget) throws {
            switch value.component {
            case .object, .constructionPlane: break
            case .face(let id), .edge(let id), .vertex(let id), .sketchEntity(let id), .region(let id):
                try string(id.rawValue)
            }
        }
        func address(_ value: ViewportSpatialReferenceAddress) throws {
            if let id = value.subshapeID { try string(id.role) }
        }
        func addresses(_ values: [ViewportSpatialReferenceAddress]) throws {
            guard values.count <= limits.maxPositionCount else { throw RealityViewportSpatialBatch.exhausted() }
            try charge(values.capacity, stride: MemoryLayout<ViewportSpatialReferenceAddress>.stride)
            for value in values { try address(value) }
        }
        try charge(capacity, stride: MemoryLayout<Self>.stride)
        for identity in table {
            try Task.checkCancellation()
            switch identity {
            case .splineControlPointSlide(let value):
                guard value.controlPointIndexes.count <= limits.maxPositionCount else { throw RealityViewportSpatialBatch.exhausted() }
                try charge(value.controlPointIndexes.capacity, stride: MemoryLayout<Int>.stride)
            case .polySplineSurfaceVertex(_, let componentID, _): try string(componentID.rawValue)
            case .polySplineSurfaceVertexSlide(let value):
                guard value.targets.count <= limits.maxPositionCount else { throw RealityViewportSpatialBatch.exhausted() }
                try charge(value.targets.capacity, stride: MemoryLayout<SelectionTarget>.stride)
                for value in value.targets { try target(value) }
            case .surfaceControlPoint(let value, _), .surfaceTrimEndpoint(let value, _), .surfaceTrimControlPoint(let value, _):
                try address(value)
            case .surfaceControlPointSlide(let values, _): try addresses(values)
            case .surfaceFrame(let values, let displayID, _):
                try addresses(values)
                try string(displayID.rawValue)
            case .regionOffset(let value): try string(value.componentID.rawValue)
            case .affordance(let value):
                if let selectionTarget = value.selectionTarget { try target(selectionTarget) }
                switch value.action {
                case .profileCornerMove(let value, _), .profileFaceMove(let value, _),
                     .profileEdgeChamfer(let value, _), .profileEdgeFillet(let value, _): try target(value)
                case .translate, .oneSidedScale, .centerScale, .rotate, .vertexMove, .faceMove: break
                }
            case .sketchCurveHandle, .sketchDimension, .sketchPointHandle, .bridgeCurveEndpoint,
                 .splineControlPoint, .edgeOffset, .slotWidth, .sketchVertexOffset,
                 .patternArrayLinearAxis, .independentCopyExtrudeDistance, .independentCopyBodyDimension,
                 .patternArrayRadialAngle, .patternArrayCopyCount, .patternArrayCurveExtent,
                 .patternArrayCurvePathPoint, .patternArrayOutputMode, .constructionPlane,
                 .sketchTransform: break
            }
        }
        return bytes
    }
}

extension ViewportInteractionTarget {
    /// The handle identity the claimed target resolves to.
    ///
    /// The projection stays throwing because a future native claim may carry
    /// reference addresses that the mounted frame has to resolve; the single
    /// case reachable today carries its identity directly.
    var spatialIdentity: ViewportSpatialHandleIdentity {
        get throws {
            switch self {
            case .affordance(let target): .affordance(target)
            }
        }
    }
}
