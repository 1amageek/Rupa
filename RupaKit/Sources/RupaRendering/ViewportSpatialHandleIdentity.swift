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
    case affordance(ViewportAffordanceTarget)

    /// Charges owned value/array storage and conservative UTF-8 backing, without
    /// walking CAD geometry or encoding another copy of the table.
    static func retainedByteCount(for table: [Self], limits: MeshSourcePresentationPlanLimits = .standard) throws -> Int {
        try limits.validate()
        guard table.count <= limits.maxItemCount else { throw RealityViewportSpatialBatch.exhausted() }
        if table.capacity == 0 { return 0 }
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
        try charge(table.capacity, stride: MemoryLayout<Self>.stride)
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
                 .patternArrayCurvePathPoint, .patternArrayOutputMode, .constructionPlane: break
            }
        }
        return bytes
    }
}

extension ViewportInteractionTarget {
    var spatialIdentity: ViewportSpatialHandleIdentity {
        get throws {
        switch self {
        case .sketchCurveHandle(let target): .sketchCurveHandle(target.identity)
        case .sketchDimension(let target): .sketchDimension(target.identity)
        case .sketchPointHandle(let target): .sketchPointHandle(target.identity)
        case .bridgeCurveEndpoint(let target): .bridgeCurveEndpoint(target.identity)
        case .splineControlPoint(let target): .splineControlPoint(target.identity)
        case .splineControlPointSlide(let target): .splineControlPointSlide(target.identity)
        case .polySplineSurfaceVertex(let target):
            .polySplineSurfaceVertex(featureID: target.featureID, componentID: target.componentID,
                                     role: .init(target.dragMode))
        case .polySplineSurfaceVertexSlide(let target): .polySplineSurfaceVertexSlide(target.identity)
        case .surfaceControlPoint(let target): .surfaceControlPoint(.init(target.target), role: .init(target.dragMode))
        case .surfaceControlPointSlide(let target):
            .surfaceControlPointSlide(try ViewportSpatialReferenceAddress.project(target.targets), direction: target.direction)
        case .surfaceTrimEndpoint(let target): .surfaceTrimEndpoint(.init(target.target), endpoint: target.endpoint)
        case .surfaceTrimControlPoint(let target): .surfaceTrimControlPoint(.init(target.target), index: target.controlPointIndex)
        case .surfaceFrame(let target):
            .surfaceFrame(try ViewportSpatialReferenceAddress.project(target.targets), displayID: target.displayID, axis: target.axis)
        case .regionOffset(let target): .regionOffset(target.identity)
        case .edgeOffset(let target): .edgeOffset(target.identity)
        case .slotWidth(let target): .slotWidth(target.identity)
        case .sketchVertexOffset(let target): .sketchVertexOffset(target.identity)
        case .patternArrayLinearAxis(let target): .patternArrayLinearAxis(target.identity)
        case .independentCopyExtrudeDistance(let target): .independentCopyExtrudeDistance(target.identity)
        case .independentCopyBodyDimension(let target): .independentCopyBodyDimension(target.identity)
        case .patternArrayRadialAngle(let target): .patternArrayRadialAngle(target.identity)
        case .patternArrayCopyCount(let target): .patternArrayCopyCount(target.identity)
        case .patternArrayCurveExtent(let target): .patternArrayCurveExtent(target.identity)
        case .patternArrayCurvePathPoint(let target): .patternArrayCurvePathPoint(target.identity)
        case .patternArrayOutputMode(let target): .patternArrayOutputMode(target.identity)
        case .constructionPlane(let target): .constructionPlane(target.identity)
        case .affordance(let target): .affordance(target)
        }
        }
    }
}
