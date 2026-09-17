import Foundation
import RupaCore
import RupaViewportScene

/// One semantic owner's registration, retained for exactly one prepared frame.
struct ViewportSpatialInteractionRecord: Sendable {
    let identity: ViewportSpatialHandleIdentity
    let occurrenceID: String?
    let modelTransform: Transform3D
    let target: ViewportSpatialPreparedInteractionTarget

    init(target: ViewportSpatialPreparedInteractionTarget,
         occurrenceID: String? = nil, modelTransform: Transform3D = .identity) throws {
        if case .affordance(let address, let members, let groupEdit, let placement) = target {
            try Task.checkCancellation()
            guard members.count <= MeshSourcePresentationPlanLimits.standard.maxPositionCount else {
                throw RealityViewportSpatialBatch.exhausted()
            }
            guard !members.isEmpty,
                  (members.count > 1) == (groupEdit != nil),
                  members.contains(where: { $0.featureID == address.featureID }),
                  (members.count == 1 ? occurrenceID == members[0].occurrenceID : occurrenceID == nil) else {
                throw RealityViewportSpatialBatch.invalid("Body affordance has no complete occurrence-scoped edit baseline.")
            }
            // A placement baseline addresses one scene node, so it belongs to a
            // single-body gizmo whose member names that node. A group gizmo
            // stands for no single node and carries none.
            if let placement {
                guard members.count == 1,
                      members[0].featureID == placement.featureID,
                      members[0].sceneNodeID == placement.sceneNodeID else {
                    throw RealityViewportSpatialBatch.invalid(
                        "Body affordance placement baseline names no member scene node."
                    )
                }
            }
            var occurrences: Set<String> = []
            for member in members {
                try Task.checkCancellation()
                guard !member.occurrenceID.isEmpty, occurrences.insert(member.occurrenceID).inserted else {
                    throw RealityViewportSpatialBatch.invalid("Body affordance repeats or omits an occurrence address.")
                }
            }
        }
        identity = try target.spatialIdentity
        self.occurrenceID = occurrenceID
        self.modelTransform = modelTransform
        self.target = target
    }

    static func retainedByteCount(
        for records: [Self], limits: MeshSourcePresentationPlanLimits = .standard
    ) throws -> Int {
        var bytes = try ViewportSpatialHandleIdentity.retainedByteCount(
            for: records.lazy.map(\.identity), capacity: records.capacity, limits: limits
        )
        func charge(_ count: Int, stride: Int = 1) throws {
            try Task.checkCancellation()
            let size = count.multipliedReportingOverflow(by: stride)
            let next = bytes.addingReportingOverflow(size.partialValue)
            guard count >= 0, !size.overflow, !next.overflow,
                  next.partialValue <= limits.maxRetainedByteCount else { throw RealityViewportSpatialBatch.exhausted() }
            bytes = next.partialValue
        }
        func array<Element>(_ values: [Element]) throws {
            guard values.count <= limits.maxPositionCount else { throw RealityViewportSpatialBatch.exhausted() }
            try charge(values.capacity, stride: MemoryLayout<Element>.stride)
        }
        func string(_ value: String) throws {
            try charge(32)
            try charge(value.utf8.count, stride: 2)
        }
        func selection(_ value: SelectionTarget) throws {
            switch value.component {
            case .object, .constructionPlane: break
            case .face(let id), .edge(let id), .vertex(let id), .sketchEntity(let id), .region(let id):
                try string(id.rawValue)
            }
        }
        // Identity accounting already charges its inline slot. CAD geometry
        // referenced by a target remains immutable source-owned COW storage;
        // only its value slot and producer-owned collections are charged here.
        try charge(records.capacity, stride: MemoryLayout<Self>.stride - MemoryLayout<ViewportSpatialHandleIdentity>.stride)
        for record in records {
            try Task.checkCancellation()
            if let occurrenceID = record.occurrenceID { try string(occurrenceID) }
            switch record.target {
            case .sketchCurveHandle(let value): try selection(value.target)
            case .sketchDimension(let value): try selection(value.target)
            case .sketchPointHandle(let value): try selection(value.target)
            case .splineControlPoint(let value): try selection(value.target)
            case .bridgeCurveEndpoint(let value, _): try string(value.referenceDescription)
            case .splineControlPointSlide(_, _, let target, let indexes, _, _):
                try selection(target)
                try array(indexes)
            case .polySplineSurfaceVertex(let value): try selection(value.target)
            case .polySplineSurfaceVertexSlide(let targets, _, _):
                try array(targets)
                for target in targets { try selection(target) }
            case .surfaceControlPointSlide(let targets, _, _), .surfaceFrame(let targets, _, _, _, _):
                try array(targets)
            case .regionOffset(_, _, let target, _), .slotWidth(_, _, let target, _),
                 .edgeOffset(_, _, let target, _, _, _), .sketchVertexOffset(_, _, let target, _, _):
                try selection(target)
            case .patternArrayLinearAxis(let value): try string(value.title)
            case .independentCopyExtrudeDistance(let value): try string(value.title)
            case .independentCopyBodyDimension(let value): try string(value.label)
            case .patternArrayRadialAngle(let value): try string(value.title)
            case .patternArrayCopyCount(let value):
                try string(value.title)
                if case .curve(let points, _) = value.guide { try array(points) }
            case .patternArrayCurveExtent(let value):
                try string(value.title)
                try array(value.pathPoints)
            case .patternArrayCurvePathPoint(let value):
                try string(value.title)
                try array(value.pathPoints)
            case .patternArrayOutputMode(let value):
                try string(value.title)
                try string(value.highlightedTitle)
            case .constructionPlane(_, _, _, _, let corners): try array(corners)
            case .affordance(_, let members, _, let placement):
                try array(members)
                for member in members {
                    try string(member.occurrenceID)
                    if let baseline = member.placement {
                        try array(baseline.baseLocalTransform.matrix.values)
                        try array(baseline.parentWorldTransform.matrix.values)
                    }
                }
                if let placement {
                    // Both frames own heap matrix storage the producer
                    // allocated for this table, the way a sketch baseline's do.
                    try array(placement.baseLocalTransform.matrix.values)
                    try array(placement.parentWorldTransform.matrix.values)
                }
            case .sketchTransform(let value):
                // Both frames own heap matrix storage the producer allocated
                // for this table, so they are charged rather than treated as
                // immutable source-owned geometry.
                try array(value.baseLocalTransform.matrix.values)
                try array(value.parentWorldTransform.matrix.values)
            case .surfaceControlPoint, .surfaceTrimEndpoint, .surfaceTrimControlPoint: break
            }
        }
        return bytes
    }
}
