import Foundation
import SwiftCAD
import RupaCoreTypes

struct SketchPointConstraintPropagator: Sendable {
    private struct Point: Equatable, Sendable {
        var x: Double
        var y: Double
    }

    private struct LineMetrics: Sendable {
        var start: Point
        var end: Point
        var length: Double
        var angle: Double
    }

    private struct CircularMetrics: Sendable {
        var center: Point
        var radius: Double
        var centerReference: SketchReference
    }

    private struct LineCircularTangency: Sendable {
        var lineID: SketchEntityID
        var circularID: SketchEntityID
        var side: SketchTangencyConstraint.LineSide
    }

    private struct SmoothSplineControlPointReferences: Sendable {
        var incoming: SketchReference
        var knot: SketchReference
        var outgoing: SketchReference
    }

    private struct SplineEndpointTangentReferences: Sendable {
        var splineID: SketchEntityID
        var endpoint: SketchSplineEndpoint
        var endpointReference: SketchReference
        var handleReference: SketchReference
        var lineID: SketchEntityID
        var orientation: SketchTangentOrientation
    }

    private struct TangentSplineEndpointReferences: Sendable {
        var endpoint: SketchSplineEndpointReference
        var endpointReference: SketchReference
        var handleReference: SketchReference
        var curvatureReference: SketchReference
        var orientation: SketchTangentOrientation
    }

    private struct TangentSplineEndpointPairReferences: Sendable {
        var first: TangentSplineEndpointReferences
        var second: TangentSplineEndpointReferences
    }

    private let parameters: ParameterTable
    private let tolerance: Double

    init(parameters: ParameterTable, tolerance: Double = 1.0e-12) {
        self.parameters = parameters
        self.tolerance = tolerance
    }

    func propagate(
        from reference: SketchReference,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        try propagateFromReference(
            reference,
            in: &sketch,
            owner: owner,
            lockedLineIDs: []
        )
    }

    func satisfyAddingConstraint(
        _ constraint: SketchConstraint,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let originalSketch = sketch
        sketch.constraints.append(constraint)

        switch constraint {
        case let .coincident(first, second):
            try satisfyAddedCoincidentConstraint(
                first,
                second,
                originalSketch: originalSketch,
                in: &sketch,
                owner: owner
            )
        case let .horizontal(lineID):
            try satisfyAddedLineAngleConstraint(
                lineID,
                angle: 0.0,
                lockedLineIDs: [],
                in: &sketch,
                owner: owner
            )
        case let .vertical(lineID):
            try satisfyAddedLineAngleConstraint(
                lineID,
                angle: Double.pi / 2.0,
                lockedLineIDs: [],
                in: &sketch,
                owner: owner
            )
        case let .parallel(first, second):
            let firstLine = try lineMetrics(for: first, in: sketch, owner: owner)
            try satisfyAddedLineAngleConstraint(
                second,
                angle: firstLine.angle,
                lockedLineIDs: [first],
                in: &sketch,
                owner: owner
            )
        case let .perpendicular(first, second):
            let firstLine = try lineMetrics(for: first, in: sketch, owner: owner)
            try satisfyAddedLineAngleConstraint(
                second,
                angle: firstLine.angle + Double.pi / 2.0,
                lockedLineIDs: [first],
                in: &sketch,
                owner: owner
            )
        case let .equalLength(first, second):
            let firstLine = try lineMetrics(for: first, in: sketch, owner: owner)
            try satisfyAddedLineLengthConstraint(
                second,
                length: firstLine.length,
                lockedLineIDs: [first],
                in: &sketch,
                owner: owner
            )
        case let .tangent(tangency):
            try satisfyAddedTangentConstraint(
                tangency,
                in: &sketch,
                owner: owner
            )
        case let .concentric(first, second):
            try satisfyAddedConcentricConstraint(
                first,
                second,
                in: &sketch,
                owner: owner
            )
        case let .equalRadius(first, second):
            try satisfyAddedEqualRadiusConstraint(
                first,
                second,
                in: &sketch,
                owner: owner
            )
        case let .smoothSplineControlPoint(entityID, index):
            try satisfyAddedSmoothSplineControlPointConstraint(
                entityID,
                index: index,
                in: &sketch,
                owner: owner
            )
        case let .splineEndpointTangent(tangency):
            try satisfyAddedSplineEndpointTangentConstraint(
                splineID: tangency.splineEndpoint.splineID,
                endpoint: tangency.splineEndpoint.endpoint,
                lineID: tangency.line,
                orientation: tangency.orientation,
                in: &sketch,
                owner: owner
            )
        case let .tangentSplineEndpoints(tangency):
            try satisfyAddedTangentSplineEndpointsConstraint(
                tangency.first,
                tangency.second,
                orientation: tangency.orientation,
                in: &sketch,
                owner: owner
            )
        case let .smoothSplineEndpoints(tangency):
            try satisfyAddedSmoothSplineEndpointsConstraint(
                tangency.first,
                tangency.second,
                orientation: tangency.orientation,
                in: &sketch,
                owner: owner
            )
        case .fixed:
            try validateLineLengths(in: sketch, owner: owner)
            try validateConcentricConstraints(in: sketch, owner: owner)
            try validateEqualRadiusConstraints(in: sketch, owner: owner)
            try validateTangentConstraints(in: sketch, owner: owner)
            try validateSmoothSplineControlPointConstraints(in: sketch, owner: owner)
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
        }
    }

    func validateCanResizeCircularEntity(
        _ entityID: SketchEntityID,
        in sketch: Sketch,
        owner: String
    ) throws {
        guard isCircularRadiusAnchored(entityID, in: sketch) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot resize a fixed circular sketch radius."
            )
        }
    }

    func propagateCircularRadius(
        from entityID: SketchEntityID,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        try propagateCircularRadiusConstraints(
            from: entityID,
            in: &sketch,
            owner: owner
        )
    }

    func validateCanMove(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws {
        guard isAnchored(reference, in: sketch) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot move a fixed sketch point."
            )
        }
    }

    func isAnchored(
        _ reference: SketchReference,
        in sketch: Sketch
    ) -> Bool {
        let connected = connectedPointReferences(connectedTo: reference, in: sketch)
        return sketch.constraints.contains { constraint in
            guard case let .fixed(fixedReference) = constraint else {
                return false
            }
            return connected.contains(fixedReference)
        }
    }

    private func propagateFromReference(
        _ reference: SketchReference,
        in sketch: inout Sketch,
        owner: String,
        lockedLineIDs: Set<SketchEntityID>
    ) throws {
        let initialPoint = try point(for: reference, in: sketch, owner: owner)
        var pending: [(reference: SketchReference, point: Point)] = [(reference, initialPoint)]
        var affectedLineIDs = Set<SketchEntityID>()
        if let lineID = lineID(for: reference) {
            affectedLineIDs.insert(lineID)
        }

        try resolvePointConstraints(
            pending: &pending,
            in: &sketch,
            owner: owner,
            affectedLineIDs: &affectedLineIDs
        )

        try propagateLineAngleConstraints(
            changedLineIDs: &affectedLineIDs,
            in: &sketch,
            owner: owner,
            lockedLineIDs: lockedLineIDs
        )

        try validateLineLengths(in: sketch, owner: owner)
        try validateLineAngleConstraints(affecting: affectedLineIDs, in: sketch, owner: owner)
        try validateLineLengthConstraints(affecting: affectedLineIDs, in: sketch, owner: owner)
        try validateConcentricConstraints(in: sketch, owner: owner)
        try validateEqualRadiusConstraints(in: sketch, owner: owner)
        try validateTangentConstraints(in: sketch, owner: owner)
        try validateSmoothSplineControlPointConstraints(in: sketch, owner: owner)
        try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
    }

    private func resolvePointConstraints(
        pending: inout [(reference: SketchReference, point: Point)],
        in sketch: inout Sketch,
        owner: String,
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        var iterationCount = 0
        let iterationLimit = max(32, sketch.constraints.count * max(1, sketch.entities.count) * 8)

        while pending.isEmpty == false {
            iterationCount += 1
            guard iterationCount <= iterationLimit else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) could not resolve sketch point constraints."
                )
            }

            let update = pending.removeFirst()
            if let lineID = lineID(for: update.reference) {
                affectedLineIDs.insert(lineID)
            }
            try enqueueCoincidentReferences(
                connectedTo: update.reference,
                point: update.point,
                sketch: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
            try enqueueConcentricReferences(
                connectedTo: update.reference,
                point: update.point,
                sketch: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
            try enqueueLineOrientationReferences(
                connectedTo: update.reference,
                point: update.point,
                sketch: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
            try enqueueSmoothSplineControlPointReferences(
                connectedTo: update.reference,
                sketch: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
            try enqueueSplineEndpointTangentReferences(
                connectedTo: update.reference,
                sketch: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
            try enqueueTangentSplineEndpointReferences(
                connectedTo: update.reference,
                sketch: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
            try enqueueSmoothSplineEndpointReferences(
                connectedTo: update.reference,
                sketch: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        }
    }

    private func enqueueCoincidentReferences(
        connectedTo reference: SketchReference,
        point: Point,
        sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        for connectedReference in coincidentReferences(connectedTo: reference, in: sketch) {
            guard connectedReference != reference else {
                continue
            }
            try assign(
                point,
                to: connectedReference,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        }
    }

    private func enqueueConcentricReferences(
        connectedTo reference: SketchReference,
        point: Point,
        sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        for connectedReference in concentricReferences(connectedTo: reference, in: sketch) {
            guard connectedReference != reference else {
                continue
            }
            try assign(
                point,
                to: connectedReference,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        }
    }

    private func enqueueLineOrientationReferences(
        connectedTo reference: SketchReference,
        point: Point,
        sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        guard let lineID = lineID(for: reference),
              let otherReference = otherLineEndpoint(for: reference) else {
            return
        }
        let otherPoint = try self.point(for: otherReference, in: sketch, owner: owner)
        if hasHorizontalConstraint(lineID, in: sketch) {
            try assign(
                Point(x: otherPoint.x, y: point.y),
                to: otherReference,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        }
        if hasVerticalConstraint(lineID, in: sketch) {
            try assign(
                Point(x: point.x, y: otherPoint.y),
                to: otherReference,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        }
    }

    private func enqueueSmoothSplineControlPointReferences(
        connectedTo reference: SketchReference,
        sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        guard case let .splineControlPoint(entityID, controlPointIndex) = reference else {
            return
        }
        for constraint in sketch.constraints {
            guard case let .smoothSplineControlPoint(smoothEntityID, knotIndex) = constraint,
                  smoothEntityID == entityID,
                  controlPointIndex >= knotIndex - 1,
                  controlPointIndex <= knotIndex + 1 else {
                continue
            }
            let references = try smoothSplineControlPointReferences(
                entityID: entityID,
                index: knotIndex,
                in: sketch,
                owner: owner
            )
            let targetReference: SketchReference
            let sourceReference: SketchReference
            if controlPointIndex == knotIndex + 1 {
                targetReference = references.incoming
                sourceReference = references.outgoing
            } else if controlPointIndex == knotIndex - 1 {
                targetReference = references.outgoing
                sourceReference = references.incoming
            } else if isAnchored(references.outgoing, in: sketch) == false {
                targetReference = references.outgoing
                sourceReference = references.incoming
            } else {
                targetReference = references.incoming
                sourceReference = references.outgoing
            }

            let targetPoint = try mirroredSmoothSplinePoint(
                source: sourceReference,
                around: references.knot,
                in: sketch,
                owner: owner
            )
            try assign(
                targetPoint,
                to: targetReference,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        }
    }

    private func enqueueSplineEndpointTangentReferences(
        connectedTo reference: SketchReference,
        sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        guard case .splineControlPoint = reference else {
            return
        }
        for constraint in sketch.constraints {
            guard case let .splineEndpointTangent(tangency) = constraint else {
                continue
            }
            let references = try splineEndpointTangentReferences(
                splineID: tangency.splineEndpoint.splineID,
                endpoint: tangency.splineEndpoint.endpoint,
                lineID: tangency.line,
                orientation: tangency.orientation,
                in: sketch,
                owner: owner
            )
            guard reference == references.endpointReference || reference == references.handleReference else {
                continue
            }
            if reference == references.handleReference || isAnchored(references.handleReference, in: sketch) {
                if let movedReference = try alignLine(
                    references.lineID,
                    toAngle: splineEndpointTangentAngle(references, in: sketch, owner: owner),
                    in: &sketch,
                    owner: owner,
                    lockedLineIDs: []
                ) {
                    pending.append((
                        reference: movedReference,
                        point: try point(for: movedReference, in: sketch, owner: owner)
                    ))
                    affectedLineIDs.insert(references.lineID)
                }
            } else {
                try alignSplineEndpointHandleToLine(
                    references,
                    in: &sketch,
                    owner: owner,
                    pending: &pending,
                    affectedLineIDs: &affectedLineIDs
                )
            }
        }
    }

    private func enqueueTangentSplineEndpointReferences(
        connectedTo reference: SketchReference,
        sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        guard case .splineControlPoint = reference else {
            return
        }
        for constraint in sketch.constraints {
            guard case let .tangentSplineEndpoints(tangency) = constraint else {
                continue
            }
            let pair = try tangentSplineEndpointPairReferences(
                tangency.first,
                tangency.second,
                orientation: tangency.orientation,
                in: sketch,
                owner: owner
            )
            if reference == pair.first.endpointReference || reference == pair.first.handleReference {
                try propagateTangentSplineEndpointUpdate(
                    source: pair.first,
                    target: pair.second,
                    changedReference: reference,
                    sketch: &sketch,
                    owner: owner,
                    pending: &pending,
                    affectedLineIDs: &affectedLineIDs
                )
            } else if reference == pair.second.endpointReference || reference == pair.second.handleReference {
                try propagateTangentSplineEndpointUpdate(
                    source: pair.second,
                    target: pair.first,
                    changedReference: reference,
                    sketch: &sketch,
                    owner: owner,
                    pending: &pending,
                    affectedLineIDs: &affectedLineIDs
                )
            }
        }
    }

    private func enqueueSmoothSplineEndpointReferences(
        connectedTo reference: SketchReference,
        sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        guard case .splineControlPoint = reference else {
            return
        }
        for constraint in sketch.constraints {
            guard case let .smoothSplineEndpoints(tangency) = constraint else {
                continue
            }
            let pair = try tangentSplineEndpointPairReferences(
                tangency.first,
                tangency.second,
                orientation: tangency.orientation,
                in: sketch,
                owner: owner
            )
            if reference == pair.first.endpointReference ||
                reference == pair.first.handleReference ||
                reference == pair.first.curvatureReference {
                try propagateSmoothSplineEndpointUpdate(
                    source: pair.first,
                    target: pair.second,
                    changedReference: reference,
                    sketch: &sketch,
                    owner: owner,
                    pending: &pending,
                    affectedLineIDs: &affectedLineIDs
                )
            } else if reference == pair.second.endpointReference ||
                reference == pair.second.handleReference ||
                reference == pair.second.curvatureReference {
                try propagateSmoothSplineEndpointUpdate(
                    source: pair.second,
                    target: pair.first,
                    changedReference: reference,
                    sketch: &sketch,
                    owner: owner,
                    pending: &pending,
                    affectedLineIDs: &affectedLineIDs
                )
            }
        }
    }

    private func assign(
        _ point: Point,
        to reference: SketchReference,
        in sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        let currentPoint = try self.point(for: reference, in: sketch, owner: owner)
        guard pointsDiffer(currentPoint, point) else {
            return
        }
        guard isDirectlyFixed(reference, in: sketch) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot move a fixed sketch point."
            )
        }
        try set(point, for: reference, in: &sketch, owner: owner)
        if let lineID = lineID(for: reference) {
            affectedLineIDs.insert(lineID)
        }
        pending.append((reference, point))
    }

    private func propagateLineAngleConstraints(
        changedLineIDs: inout Set<SketchEntityID>,
        in sketch: inout Sketch,
        owner: String,
        lockedLineIDs: Set<SketchEntityID>
    ) throws {
        guard changedLineIDs.isEmpty == false else {
            return
        }
        var pendingLineIDs = Array(changedLineIDs)
        var iterationCount = 0
        let iterationLimit = max(32, sketch.constraints.count * max(1, sketch.entities.count) * 8)

        while pendingLineIDs.isEmpty == false {
            iterationCount += 1
            guard iterationCount <= iterationLimit else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) could not resolve sketch line angle constraints."
                )
            }

            let sourceLineID = pendingLineIDs.removeFirst()
            let source = try lineMetrics(for: sourceLineID, in: sketch, owner: owner)
            for update in lineAngleUpdates(from: sourceLineID, sourceAngle: source.angle, in: sketch) {
                if let movedReference = try alignLine(
                    update.lineID,
                    toAngle: update.angle,
                    in: &sketch,
                    owner: owner,
                    lockedLineIDs: lockedLineIDs
                ) {
                    var affectedLineIDs = Set<SketchEntityID>()
                    var pendingPoints: [(reference: SketchReference, point: Point)] = [
                        (
                            reference: movedReference,
                            point: try point(for: movedReference, in: sketch, owner: owner)
                        ),
                    ]
                    try resolvePointConstraints(
                        pending: &pendingPoints,
                        in: &sketch,
                        owner: owner,
                        affectedLineIDs: &affectedLineIDs
                    )
                    affectedLineIDs.insert(update.lineID)
                    changedLineIDs.formUnion(affectedLineIDs)
                    for affectedLineID in affectedLineIDs where pendingLineIDs.contains(affectedLineID) == false {
                        pendingLineIDs.append(affectedLineID)
                    }
                }
            }
            let resizedSource = try lineMetrics(for: sourceLineID, in: sketch, owner: owner)
            for update in lineLengthUpdates(from: sourceLineID, sourceLength: resizedSource.length, in: sketch) {
                if let movedReference = try resizeLine(
                    update.lineID,
                    toLength: update.length,
                    in: &sketch,
                    owner: owner,
                    lockedLineIDs: lockedLineIDs
                ) {
                    var affectedLineIDs = Set<SketchEntityID>()
                    var pendingPoints: [(reference: SketchReference, point: Point)] = [
                        (
                            reference: movedReference,
                            point: try point(for: movedReference, in: sketch, owner: owner)
                        ),
                    ]
                    try resolvePointConstraints(
                        pending: &pendingPoints,
                        in: &sketch,
                        owner: owner,
                        affectedLineIDs: &affectedLineIDs
                    )
                    affectedLineIDs.insert(update.lineID)
                    changedLineIDs.formUnion(affectedLineIDs)
                    for affectedLineID in affectedLineIDs where pendingLineIDs.contains(affectedLineID) == false {
                        pendingLineIDs.append(affectedLineID)
                    }
                }
            }
            for tangency in tangentCircularUpdates(from: sourceLineID, in: sketch) {
                if let movedReference = try moveCircularEntityToTangent(
                    tangency.circularID,
                    withLine: sourceLineID,
                    side: tangency.side,
                    in: &sketch,
                    owner: owner
                ) {
                    var affectedLineIDs = Set<SketchEntityID>()
                    var pendingPoints: [(reference: SketchReference, point: Point)] = [
                        (
                            reference: movedReference,
                            point: try point(for: movedReference, in: sketch, owner: owner)
                        ),
                    ]
                    try resolvePointConstraints(
                        pending: &pendingPoints,
                        in: &sketch,
                        owner: owner,
                        affectedLineIDs: &affectedLineIDs
                    )
                    changedLineIDs.formUnion(affectedLineIDs)
                    for affectedLineID in affectedLineIDs where pendingLineIDs.contains(affectedLineID) == false {
                        pendingLineIDs.append(affectedLineID)
                    }
                }
            }
            for references in try splineEndpointTangentUpdates(fromLine: sourceLineID, in: sketch, owner: owner) {
                var affectedLineIDs = Set<SketchEntityID>()
                var pendingPoints: [(reference: SketchReference, point: Point)] = []
                try alignSplineEndpointHandleToLine(
                    references,
                    in: &sketch,
                    owner: owner,
                    pending: &pendingPoints,
                    affectedLineIDs: &affectedLineIDs
                )
                try resolvePointConstraints(
                    pending: &pendingPoints,
                    in: &sketch,
                    owner: owner,
                    affectedLineIDs: &affectedLineIDs
                )
                changedLineIDs.formUnion(affectedLineIDs)
                for affectedLineID in affectedLineIDs where pendingLineIDs.contains(affectedLineID) == false {
                    pendingLineIDs.append(affectedLineID)
                }
            }
        }
    }

    private func satisfyAddedCoincidentConstraint(
        _ first: SketchReference,
        _ second: SketchReference,
        originalSketch: Sketch,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let firstPoint = try point(for: first, in: sketch, owner: owner)
        let secondPoint = try point(for: second, in: sketch, owner: owner)
        guard pointsDiffer(firstPoint, secondPoint) else {
            let affectedLineIDs = Set([lineID(for: first), lineID(for: second)].compactMap { $0 })
            try validateLineLengths(in: sketch, owner: owner)
            try validateLineAngleConstraints(affecting: affectedLineIDs, in: sketch, owner: owner)
            try validateLineLengthConstraints(affecting: affectedLineIDs, in: sketch, owner: owner)
            try validateConcentricConstraints(in: sketch, owner: owner)
            try validateEqualRadiusConstraints(in: sketch, owner: owner)
            try validateTangentConstraints(in: sketch, owner: owner)
            try validateSmoothSplineControlPointConstraints(in: sketch, owner: owner)
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
            return
        }

        let firstAnchored = isAnchored(first, in: originalSketch)
        let secondAnchored = isAnchored(second, in: originalSketch)
        guard firstAnchored == false || secondAnchored == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot satisfy a coincident constraint between fixed sketch points."
            )
        }

        let movedReference: SketchReference
        let targetPoint: Point
        if secondAnchored {
            movedReference = first
            targetPoint = secondPoint
        } else {
            movedReference = second
            targetPoint = firstPoint
        }

        var pending: [(reference: SketchReference, point: Point)] = []
        var affectedLineIDs = Set<SketchEntityID>()
        try assign(
            targetPoint,
            to: movedReference,
            in: &sketch,
            owner: owner,
            pending: &pending,
            affectedLineIDs: &affectedLineIDs
        )
        try resolvePointConstraints(
            pending: &pending,
            in: &sketch,
            owner: owner,
            affectedLineIDs: &affectedLineIDs
        )
        try propagateLineAngleConstraints(
            changedLineIDs: &affectedLineIDs,
            in: &sketch,
            owner: owner,
            lockedLineIDs: []
        )
        try validateLineLengths(in: sketch, owner: owner)
        try validateLineAngleConstraints(affecting: affectedLineIDs, in: sketch, owner: owner)
        try validateLineLengthConstraints(affecting: affectedLineIDs, in: sketch, owner: owner)
        try validateConcentricConstraints(in: sketch, owner: owner)
        try validateEqualRadiusConstraints(in: sketch, owner: owner)
        try validateTangentConstraints(in: sketch, owner: owner)
        try validateSmoothSplineControlPointConstraints(in: sketch, owner: owner)
        try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
    }

    private func satisfyAddedLineAngleConstraint(
        _ lineID: SketchEntityID,
        angle: Double,
        lockedLineIDs: Set<SketchEntityID>,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let movedReference = try alignLine(
            lineID,
            toAngle: angle,
            in: &sketch,
            owner: owner,
            lockedLineIDs: lockedLineIDs
        )
        if let movedReference {
            try propagateFromReference(
                movedReference,
                in: &sketch,
                owner: owner,
                lockedLineIDs: lockedLineIDs
            )
        } else {
            try validateLineLengths(in: sketch, owner: owner)
            try validateLineAngleConstraints(affecting: lockedLineIDs.union([lineID]), in: sketch, owner: owner)
            try validateLineLengthConstraints(affecting: lockedLineIDs.union([lineID]), in: sketch, owner: owner)
            try validateConcentricConstraints(in: sketch, owner: owner)
            try validateEqualRadiusConstraints(in: sketch, owner: owner)
            try validateTangentConstraints(in: sketch, owner: owner)
            try validateSmoothSplineControlPointConstraints(in: sketch, owner: owner)
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
        }
    }

    private func satisfyAddedLineLengthConstraint(
        _ lineID: SketchEntityID,
        length: Double,
        lockedLineIDs: Set<SketchEntityID>,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let movedReference = try resizeLine(
            lineID,
            toLength: length,
            in: &sketch,
            owner: owner,
            lockedLineIDs: lockedLineIDs
        )
        if let movedReference {
            try propagateFromReference(
                movedReference,
                in: &sketch,
                owner: owner,
                lockedLineIDs: lockedLineIDs
            )
        } else {
            try validateLineLengths(in: sketch, owner: owner)
            try validateLineAngleConstraints(affecting: lockedLineIDs.union([lineID]), in: sketch, owner: owner)
            try validateLineLengthConstraints(affecting: lockedLineIDs.union([lineID]), in: sketch, owner: owner)
            try validateConcentricConstraints(in: sketch, owner: owner)
            try validateEqualRadiusConstraints(in: sketch, owner: owner)
            try validateTangentConstraints(in: sketch, owner: owner)
            try validateSmoothSplineControlPointConstraints(in: sketch, owner: owner)
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
        }
    }

    private func satisfyAddedTangentConstraint(
        _ tangency: SketchTangencyConstraint,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let movedReference: SketchReference?
        let lockedLineIDs: Set<SketchEntityID>
        switch tangency {
        case let .lineCircular(lineID, circularID, side):
            _ = try lineMetrics(for: lineID, in: sketch, owner: owner)
            _ = try circularMetrics(for: circularID, in: sketch, owner: owner)
            movedReference = try moveCircularEntityToTangent(
                circularID,
                withLine: lineID,
                side: side,
                in: &sketch,
                owner: owner
            )
            lockedLineIDs = [lineID]
        case .circularCircular:
            movedReference = try satisfyCircularCircularTangency(
                tangency,
                preferredMovableEntityID: nil,
                in: &sketch,
                owner: owner
            )
            lockedLineIDs = []
        }
        if let movedReference {
            try propagateFromReference(
                movedReference,
                in: &sketch,
                owner: owner,
                lockedLineIDs: lockedLineIDs
            )
        } else {
            try validateTangentConstraints(in: sketch, owner: owner)
            try validateSmoothSplineControlPointConstraints(in: sketch, owner: owner)
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
        }
    }

    private func satisfyAddedConcentricConstraint(
        _ first: SketchEntityID,
        _ second: SketchEntityID,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let firstMetrics = try circularMetrics(for: first, in: sketch, owner: owner)
        let secondMetrics = try circularMetrics(for: second, in: sketch, owner: owner)
        guard pointsDiffer(firstMetrics.center, secondMetrics.center) else {
            try validateConcentricConstraints(in: sketch, owner: owner)
            try validateTangentConstraints(in: sketch, owner: owner)
            try validateSmoothSplineControlPointConstraints(in: sketch, owner: owner)
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
            return
        }
        guard isAnchored(secondMetrics.centerReference, in: sketch) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot move a fixed circular sketch center."
            )
        }
        try set(firstMetrics.center, for: secondMetrics.centerReference, in: &sketch, owner: owner)
        try propagateFromReference(
            secondMetrics.centerReference,
            in: &sketch,
            owner: owner,
            lockedLineIDs: []
        )
    }

    private func satisfyAddedEqualRadiusConstraint(
        _ first: SketchEntityID,
        _ second: SketchEntityID,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let firstMetrics = try circularMetrics(for: first, in: sketch, owner: owner)
        if try resizeCircularEntity(second, toRadius: firstMetrics.radius, in: &sketch, owner: owner) {
            try propagateCircularRadiusConstraints(from: second, in: &sketch, owner: owner)
        } else {
            try validateEqualRadiusConstraints(in: sketch, owner: owner)
            try validateTangentConstraints(in: sketch, owner: owner)
            try validateSmoothSplineControlPointConstraints(in: sketch, owner: owner)
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
        }
    }

    private func satisfyAddedSmoothSplineControlPointConstraint(
        _ entityID: SketchEntityID,
        index: Int,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let references = try smoothSplineControlPointReferences(
            entityID: entityID,
            index: index,
            in: sketch,
            owner: owner
        )
        guard try smoothSplineControlPointIsSatisfied(references, in: sketch, owner: owner) == false else {
            try validateSmoothSplineControlPointConstraints(in: sketch, owner: owner)
            return
        }
        let outgoingAnchored = isAnchored(references.outgoing, in: sketch)
        let incomingAnchored = isAnchored(references.incoming, in: sketch)
        guard outgoingAnchored == false || incomingAnchored == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot smooth a spline control point with both handles fixed."
            )
        }

        var pending: [(reference: SketchReference, point: Point)] = []
        var affectedLineIDs = Set<SketchEntityID>()
        if outgoingAnchored == false {
            let targetPoint = try mirroredSmoothSplinePoint(
                source: references.incoming,
                around: references.knot,
                in: sketch,
                owner: owner
            )
            try assign(
                targetPoint,
                to: references.outgoing,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        } else {
            let targetPoint = try mirroredSmoothSplinePoint(
                source: references.outgoing,
                around: references.knot,
                in: sketch,
                owner: owner
            )
            try assign(
                targetPoint,
                to: references.incoming,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        }
        try resolvePointConstraints(
            pending: &pending,
            in: &sketch,
            owner: owner,
            affectedLineIDs: &affectedLineIDs
        )
        try validateSmoothSplineControlPointConstraints(in: sketch, owner: owner)
        try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
    }

    private func satisfyAddedSplineEndpointTangentConstraint(
        splineID: SketchEntityID,
        endpoint: SketchSplineEndpoint,
        lineID: SketchEntityID,
        orientation: SketchTangentOrientation,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let references = try splineEndpointTangentReferences(
            splineID: splineID,
            endpoint: endpoint,
            lineID: lineID,
            orientation: orientation,
            in: sketch,
            owner: owner
        )
        guard try splineEndpointTangentIsSatisfied(references, in: sketch, owner: owner) == false else {
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
            return
        }
        if isAnchored(references.handleReference, in: sketch) == false {
            var pending: [(reference: SketchReference, point: Point)] = []
            var affectedLineIDs = Set<SketchEntityID>()
            try alignSplineEndpointHandleToLine(
                references,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
            try resolvePointConstraints(
                pending: &pending,
                in: &sketch,
                owner: owner,
                affectedLineIDs: &affectedLineIDs
            )
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
        } else if let movedReference = try alignLine(
            references.lineID,
            toAngle: splineEndpointLineAngle(references, in: sketch, owner: owner),
            in: &sketch,
            owner: owner,
            lockedLineIDs: []
        ) {
            try propagateFromReference(
                movedReference,
                in: &sketch,
                owner: owner,
                lockedLineIDs: []
            )
        } else {
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
        }
    }

    private func satisfyAddedTangentSplineEndpointsConstraint(
        _ first: SketchSplineEndpointReference,
        _ second: SketchSplineEndpointReference,
        orientation: SketchTangentOrientation,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let pair = try tangentSplineEndpointPairReferences(
            first,
            second,
            orientation: orientation,
            in: sketch,
            owner: owner
        )
        guard try tangentSplineEndpointsAreSatisfied(pair, in: sketch, owner: owner) == false else {
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
            return
        }

        var pending: [(reference: SketchReference, point: Point)] = []
        var affectedLineIDs = Set<SketchEntityID>()
        if isAnchored(pair.second.handleReference, in: sketch) == false {
            try alignTangentSplineEndpointHandle(
                target: pair.second,
                source: pair.first,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        } else if isAnchored(pair.first.handleReference, in: sketch) == false {
            try alignTangentSplineEndpointHandle(
                target: pair.first,
                source: pair.second,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        } else {
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
            return
        }

        try resolvePointConstraints(
            pending: &pending,
            in: &sketch,
            owner: owner,
            affectedLineIDs: &affectedLineIDs
        )
        try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
    }

    private func satisfyAddedSmoothSplineEndpointsConstraint(
        _ first: SketchSplineEndpointReference,
        _ second: SketchSplineEndpointReference,
        orientation: SketchTangentOrientation,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let pair = try tangentSplineEndpointPairReferences(
            first,
            second,
            orientation: orientation,
            in: sketch,
            owner: owner
        )
        guard try smoothSplineEndpointsAreSatisfied(pair, in: sketch, owner: owner) == false else {
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
            return
        }

        var pending: [(reference: SketchReference, point: Point)] = []
        var affectedLineIDs = Set<SketchEntityID>()
        if smoothSplineEndpointCanMove(pair.second, shouldAlignEndpoint: true, in: sketch) {
            try alignSmoothSplineEndpoint(
                target: pair.second,
                source: pair.first,
                shouldAlignEndpoint: true,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        } else if smoothSplineEndpointCanMove(pair.first, shouldAlignEndpoint: true, in: sketch) {
            try alignSmoothSplineEndpoint(
                target: pair.first,
                source: pair.second,
                shouldAlignEndpoint: true,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        } else if try smoothSplineEndpointsShareEndpoint(pair, in: sketch, owner: owner),
                  smoothSplineEndpointCanMove(pair.second, shouldAlignEndpoint: false, in: sketch) {
            try alignSmoothSplineEndpoint(
                target: pair.second,
                source: pair.first,
                shouldAlignEndpoint: false,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        } else if try smoothSplineEndpointsShareEndpoint(pair, in: sketch, owner: owner),
                  smoothSplineEndpointCanMove(pair.first, shouldAlignEndpoint: false, in: sketch) {
            try alignSmoothSplineEndpoint(
                target: pair.first,
                source: pair.second,
                shouldAlignEndpoint: false,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        } else {
            try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
            return
        }

        try resolvePointConstraints(
            pending: &pending,
            in: &sketch,
            owner: owner,
            affectedLineIDs: &affectedLineIDs
        )
        try validateSplineEndpointTangentConstraints(in: sketch, owner: owner)
    }

    private func lineAngleUpdates(
        from lineID: SketchEntityID,
        sourceAngle: Double,
        in sketch: Sketch
    ) -> [(lineID: SketchEntityID, angle: Double)] {
        sketch.constraints.compactMap { constraint in
            switch constraint {
            case let .parallel(first, second):
                guard first != second else {
                    return nil
                }
                if first == lineID {
                    return (second, sourceAngle)
                }
                if second == lineID {
                    return (first, sourceAngle)
                }
                return nil
            case let .perpendicular(first, second):
                guard first != second else {
                    return nil
                }
                if first == lineID {
                    return (second, sourceAngle + Double.pi / 2.0)
                }
                if second == lineID {
                    return (first, sourceAngle - Double.pi / 2.0)
                }
                return nil
            case .coincident,
                 .horizontal,
                 .vertical,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                return nil
            }
        }
    }

    private func lineLengthUpdates(
        from lineID: SketchEntityID,
        sourceLength: Double,
        in sketch: Sketch
    ) -> [(lineID: SketchEntityID, length: Double)] {
        sketch.constraints.compactMap { constraint in
            switch constraint {
            case let .equalLength(first, second):
                guard first != second else {
                    return nil
                }
                if first == lineID {
                    return (second, sourceLength)
                }
                if second == lineID {
                    return (first, sourceLength)
                }
                return nil
            case .coincident,
                 .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                return nil
            }
        }
    }

    private func tangentCircularUpdates(
        from lineID: SketchEntityID,
        in sketch: Sketch
    ) -> [LineCircularTangency] {
        sketch.constraints.compactMap { constraint in
            switch constraint {
            case let .tangent(tangency):
                if case let .lineCircular(line, circular, side) = tangency,
                   line == lineID {
                    return LineCircularTangency(
                        lineID: line,
                        circularID: circular,
                        side: side
                    )
                }
                return nil
            case .coincident,
                 .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                return nil
            }
        }
    }

    private func alignLine(
        _ lineID: SketchEntityID,
        toAngle angle: Double,
        in sketch: inout Sketch,
        owner: String,
        lockedLineIDs: Set<SketchEntityID>
    ) throws -> SketchReference? {
        let metrics = try lineMetrics(for: lineID, in: sketch, owner: owner)
        let targetAngle = equivalentAngle(angle, near: metrics.angle, period: Double.pi)
        guard angleMatches(metrics.angle, targetAngle, period: Double.pi) == false else {
            return nil
        }
        guard lockedLineIDs.contains(lineID) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot satisfy a locked sketch line angle constraint."
            )
        }

        let startReference = SketchReference.lineStart(lineID)
        let endReference = SketchReference.lineEnd(lineID)
        let startAnchored = isAnchored(startReference, in: sketch)
        let endAnchored = isAnchored(endReference, in: sketch)
        guard startAnchored == false || endAnchored == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot satisfy a fixed sketch line angle constraint."
            )
        }

        let directionX = cos(targetAngle)
        let directionY = sin(targetAngle)
        let movedReference: SketchReference
        let updatedLine: SketchLine
        if endAnchored {
            let start = Point(
                x: metrics.end.x - directionX * metrics.length,
                y: metrics.end.y - directionY * metrics.length
            )
            guard pointsDiffer(metrics.start, start) else {
                return nil
            }
            updatedLine = SketchLine(
                start: sketchPoint(x: start.x, y: start.y),
                end: sketchPoint(x: metrics.end.x, y: metrics.end.y)
            )
            movedReference = startReference
        } else {
            let end = Point(
                x: metrics.start.x + directionX * metrics.length,
                y: metrics.start.y + directionY * metrics.length
            )
            guard pointsDiffer(metrics.end, end) else {
                return nil
            }
            updatedLine = SketchLine(
                start: sketchPoint(x: metrics.start.x, y: metrics.start.y),
                end: sketchPoint(x: end.x, y: end.y)
            )
            movedReference = endReference
        }

        sketch.entities[lineID] = .line(updatedLine)
        return movedReference
    }

    private func resizeLine(
        _ lineID: SketchEntityID,
        toLength length: Double,
        in sketch: inout Sketch,
        owner: String,
        lockedLineIDs: Set<SketchEntityID>
    ) throws -> SketchReference? {
        guard length > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot satisfy a non-positive sketch line length constraint."
            )
        }
        let metrics = try lineMetrics(for: lineID, in: sketch, owner: owner)
        guard abs(metrics.length - length) > tolerance else {
            return nil
        }
        guard lockedLineIDs.contains(lineID) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot satisfy a locked sketch line length constraint."
            )
        }

        let startReference = SketchReference.lineStart(lineID)
        let endReference = SketchReference.lineEnd(lineID)
        let startAnchored = isAnchored(startReference, in: sketch)
        let endAnchored = isAnchored(endReference, in: sketch)
        guard startAnchored == false || endAnchored == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot satisfy a fixed sketch line length constraint."
            )
        }

        let directionX = cos(metrics.angle)
        let directionY = sin(metrics.angle)
        let movedReference: SketchReference
        let updatedLine: SketchLine
        if endAnchored {
            let start = Point(
                x: metrics.end.x - directionX * length,
                y: metrics.end.y - directionY * length
            )
            updatedLine = SketchLine(
                start: sketchPoint(x: start.x, y: start.y),
                end: sketchPoint(x: metrics.end.x, y: metrics.end.y)
            )
            movedReference = startReference
        } else {
            let end = Point(
                x: metrics.start.x + directionX * length,
                y: metrics.start.y + directionY * length
            )
            updatedLine = SketchLine(
                start: sketchPoint(x: metrics.start.x, y: metrics.start.y),
                end: sketchPoint(x: end.x, y: end.y)
            )
            movedReference = endReference
        }

        sketch.entities[lineID] = .line(updatedLine)
        return movedReference
    }

    private func moveCircularEntityToTangent(
        _ circularID: SketchEntityID,
        withLine lineID: SketchEntityID,
        side: SketchTangencyConstraint.LineSide,
        in sketch: inout Sketch,
        owner: String
    ) throws -> SketchReference? {
        let line = try lineMetrics(for: lineID, in: sketch, owner: owner)
        let circular = try circularMetrics(for: circularID, in: sketch, owner: owner)
        let normal = lineNormal(for: line)
        let signedDistance = signedDistanceFromLine(line, to: circular.center, normal: normal)
        let targetDistance = tangentTargetDistance(side: side, radius: circular.radius)
        let offset = targetDistance - signedDistance
        guard abs(offset) > tolerance else {
            return nil
        }
        guard isAnchored(circular.centerReference, in: sketch) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot move a fixed circular sketch center."
            )
        }
        let center = Point(
            x: circular.center.x + normal.x * offset,
            y: circular.center.y + normal.y * offset
        )
        try set(center, for: circular.centerReference, in: &sketch, owner: owner)
        return circular.centerReference
    }

    private func satisfyCircularCircularTangency(
        _ tangency: SketchTangencyConstraint,
        preferredMovableEntityID: SketchEntityID?,
        in sketch: inout Sketch,
        owner: String
    ) throws -> SketchReference? {
        guard case let .circularCircular(firstID, secondID, contact) = tangency else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a circular-circular tangent constraint."
            )
        }
        let first = try circularMetrics(for: firstID, in: sketch, owner: owner)
        let second = try circularMetrics(for: secondID, in: sketch, owner: owner)
        let targetDistance: Double
        switch contact {
        case .external:
            targetDistance = first.radius + second.radius
        case .firstContainsSecond:
            guard first.radius - second.radius > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) first-containing tangency requires the first radius to be larger."
                )
            }
            targetDistance = first.radius - second.radius
        case .secondContainsFirst:
            guard second.radius - first.radius > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) second-containing tangency requires the second radius to be larger."
                )
            }
            targetDistance = second.radius - first.radius
        }

        let preferredID = preferredMovableEntityID ?? secondID
        let preferred = preferredID == firstID ? first : second
        let alternate = preferredID == firstID ? second : first
        let preferredEntityID = preferredID == firstID ? firstID : secondID
        let alternateEntityID = preferredID == firstID ? secondID : firstID
        let movable: (id: SketchEntityID, metrics: CircularMetrics, source: CircularMetrics)
        if isAnchored(preferred.centerReference, in: sketch) == false {
            movable = (preferredEntityID, preferred, alternate)
        } else if isAnchored(alternate.centerReference, in: sketch) == false {
            movable = (alternateEntityID, alternate, preferred)
        } else {
            return nil
        }

        let delta = Point(
            x: movable.metrics.center.x - movable.source.center.x,
            y: movable.metrics.center.y - movable.source.center.y
        )
        let currentDistance = hypot(delta.x, delta.y)
        guard abs(currentDistance - targetDistance) > tolerance else {
            return nil
        }
        let direction = currentDistance > tolerance
            ? Point(x: delta.x / currentDistance, y: delta.y / currentDistance)
            : Point(x: 1.0, y: 0.0)
        let center = Point(
            x: movable.source.center.x + direction.x * targetDistance,
            y: movable.source.center.y + direction.y * targetDistance
        )
        try set(center, for: movable.metrics.centerReference, in: &sketch, owner: owner)
        return movable.metrics.centerReference
    }

    private func translateLineToTangent(
        _ lineID: SketchEntityID,
        withCircularEntity circularID: SketchEntityID,
        side: SketchTangencyConstraint.LineSide,
        in sketch: inout Sketch,
        owner: String
    ) throws -> [SketchReference] {
        let line = try lineMetrics(for: lineID, in: sketch, owner: owner)
        let circular = try circularMetrics(for: circularID, in: sketch, owner: owner)
        let normal = lineNormal(for: line)
        let signedDistance = signedDistanceFromLine(line, to: circular.center, normal: normal)
        let targetDistance = tangentTargetDistance(side: side, radius: circular.radius)
        let offset = signedDistance - targetDistance
        guard abs(offset) > tolerance else {
            return []
        }

        let startReference = SketchReference.lineStart(lineID)
        let endReference = SketchReference.lineEnd(lineID)
        guard isAnchored(startReference, in: sketch) == false,
              isAnchored(endReference, in: sketch) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot translate a fixed sketch line to satisfy tangency."
            )
        }

        let start = Point(
            x: line.start.x + normal.x * offset,
            y: line.start.y + normal.y * offset
        )
        let end = Point(
            x: line.end.x + normal.x * offset,
            y: line.end.y + normal.y * offset
        )
        let updatedLine = SketchLine(
            start: sketchPoint(x: start.x, y: start.y),
            end: sketchPoint(x: end.x, y: end.y)
        )
        sketch.entities[lineID] = .line(updatedLine)
        return [startReference, endReference]
    }

    private func circularMetrics(
        for entityID: SketchEntityID,
        in sketch: Sketch,
        owner: String
    ) throws -> CircularMetrics {
        guard let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing circular sketch entity."
            )
        }
        switch entity {
        case let .circle(circle):
            let radius = try resolvedLength(circle.radius, owner: "\(owner) circle radius")
            guard radius > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) circle radius must be greater than zero."
                )
            }
            return CircularMetrics(
                center: try resolvedPoint(circle.center, owner: "\(owner) circle center"),
                radius: radius,
                centerReference: .circleCenter(entityID)
            )
        case let .arc(arc):
            try validateArc(arc, owner: owner)
            let radius = try resolvedLength(arc.radius, owner: "\(owner) arc radius")
            return CircularMetrics(
                center: try resolvedPoint(arc.center, owner: "\(owner) arc center"),
                radius: radius,
                centerReference: .arcCenter(entityID)
            )
        case .point, .line, .spline:
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) tangent constraint requires a circular sketch entity."
            )
        }
    }

    private func lineNormal(for line: LineMetrics) -> Point {
        Point(x: -sin(line.angle), y: cos(line.angle))
    }

    private func signedDistanceFromLine(
        _ line: LineMetrics,
        to point: Point,
        normal: Point
    ) -> Double {
        let deltaX = point.x - line.start.x
        let deltaY = point.y - line.start.y
        return deltaX * normal.x + deltaY * normal.y
    }

    private func tangentTargetDistance(
        side: SketchTangencyConstraint.LineSide,
        radius: Double
    ) -> Double {
        side == .left ? radius : -radius
    }

    private func isLineEntity(_ entityID: SketchEntityID, in sketch: Sketch) -> Bool {
        guard let entity = sketch.entities[entityID], case .line = entity else {
            return false
        }
        return true
    }

    private func isCircularEntity(_ entityID: SketchEntityID, in sketch: Sketch) -> Bool {
        guard let entity = sketch.entities[entityID] else {
            return false
        }
        switch entity {
        case .circle, .arc:
            return true
        case .point, .line, .spline:
            return false
        }
    }

    private func resizeCircularEntity(
        _ entityID: SketchEntityID,
        toRadius radius: Double,
        in sketch: inout Sketch,
        owner: String
    ) throws -> Bool {
        guard radius > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) circular radius must be greater than zero."
            )
        }
        let metrics = try circularMetrics(for: entityID, in: sketch, owner: owner)
        guard abs(metrics.radius - radius) > tolerance else {
            return false
        }
        guard isCircularRadiusAnchored(entityID, in: sketch) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot resize a fixed circular sketch radius."
            )
        }
        guard let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing circular sketch entity."
            )
        }
        switch entity {
        case var .circle(circle):
            circle.radius = .length(radius, .meter)
            sketch.entities[entityID] = .circle(circle)
        case var .arc(arc):
            arc.radius = .length(radius, .meter)
            try validateArc(arc, owner: owner)
            sketch.entities[entityID] = .arc(arc)
        case .point, .line, .spline:
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references an unsupported circular sketch entity."
            )
        }
        return true
    }

    private func propagateCircularRadiusConstraints(
        from entityID: SketchEntityID,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        var pending = [entityID]
        var visited = Set<SketchEntityID>()
        let iterationLimit = max(32, sketch.constraints.count * max(1, sketch.entities.count) * 8)
        var iterationCount = 0

        while pending.isEmpty == false {
            iterationCount += 1
            guard iterationCount <= iterationLimit else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) could not resolve sketch radius constraints."
                )
            }
            let sourceID = pending.removeFirst()
            guard visited.insert(sourceID).inserted else {
                continue
            }
            let sourceRadius = try circularMetrics(for: sourceID, in: sketch, owner: owner).radius
            for connectedID in equalRadiusEntityIDs(connectedTo: sourceID, in: sketch) where connectedID != sourceID {
                if try resizeCircularEntity(connectedID, toRadius: sourceRadius, in: &sketch, owner: owner) {
                    pending.append(connectedID)
                }
            }
            try propagateTangentConstraints(forCircularEntity: sourceID, in: &sketch, owner: owner)
        }

        try validateEqualRadiusConstraints(in: sketch, owner: owner)
        try validateTangentConstraints(in: sketch, owner: owner)
    }

    private func propagateTangentConstraints(
        forCircularEntity entityID: SketchEntityID,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        for tangency in tangentLineConstraints(forCircularEntity: entityID, in: sketch) {
            if let movedReference = try moveCircularEntityToTangent(
                entityID,
                withLine: tangency.lineID,
                side: tangency.side,
                in: &sketch,
                owner: owner
            ) {
                try propagateFromReference(
                    movedReference,
                    in: &sketch,
                    owner: owner,
                    lockedLineIDs: [tangency.lineID]
                )
            }
        }
        for constraint in sketch.constraints {
            guard case let .tangent(tangency) = constraint,
                  case let .circularCircular(first, second, _) = tangency,
                  first == entityID || second == entityID else {
                continue
            }
            let otherID = first == entityID ? second : first
            if let movedReference = try satisfyCircularCircularTangency(
                tangency,
                preferredMovableEntityID: otherID,
                in: &sketch,
                owner: owner
            ) {
                try propagateFromReference(
                    movedReference,
                    in: &sketch,
                    owner: owner,
                    lockedLineIDs: []
                )
            }
        }
    }

    private func tangentLineConstraints(
        forCircularEntity entityID: SketchEntityID,
        in sketch: Sketch
    ) -> [LineCircularTangency] {
        sketch.constraints.compactMap { constraint in
            switch constraint {
            case let .tangent(tangency):
                if case let .lineCircular(line, circular, side) = tangency,
                   circular == entityID {
                    return LineCircularTangency(
                        lineID: line,
                        circularID: circular,
                        side: side
                    )
                }
                return nil
            case .coincident,
                 .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                return nil
            }
        }
    }

    private func coincidentReferences(
        connectedTo reference: SketchReference,
        in sketch: Sketch
    ) -> Set<SketchReference> {
        var connected: Set<SketchReference> = [reference]
        var changed = true
        while changed {
            changed = false
            for constraint in sketch.constraints {
                guard case let .coincident(first, second) = constraint else {
                    continue
                }
                if connected.contains(first), connected.insert(second).inserted {
                    changed = true
                }
                if connected.contains(second), connected.insert(first).inserted {
                    changed = true
                }
            }
        }
        return connected
    }

    private func connectedPointReferences(
        connectedTo reference: SketchReference,
        in sketch: Sketch
    ) -> Set<SketchReference> {
        coincidentReferences(connectedTo: reference, in: sketch)
            .union(concentricReferences(connectedTo: reference, in: sketch))
    }

    private func concentricReferences(
        connectedTo reference: SketchReference,
        in sketch: Sketch
    ) -> Set<SketchReference> {
        guard let entityID = circularCenterEntityID(for: reference),
              let centerReference = circularCenterReference(for: entityID, in: sketch) else {
            return [reference]
        }
        var connected: Set<SketchEntityID> = [entityID]
        var changed = true
        while changed {
            changed = false
            for constraint in sketch.constraints {
                guard case let .concentric(first, second) = constraint else {
                    continue
                }
                if connected.contains(first), connected.insert(second).inserted {
                    changed = true
                }
                if connected.contains(second), connected.insert(first).inserted {
                    changed = true
                }
            }
        }
        var references: Set<SketchReference> = [centerReference]
        for connectedID in connected {
            if let reference = circularCenterReference(for: connectedID, in: sketch) {
                references.insert(reference)
            }
        }
        return references
    }

    private func equalRadiusEntityIDs(
        connectedTo entityID: SketchEntityID,
        in sketch: Sketch
    ) -> Set<SketchEntityID> {
        var connected: Set<SketchEntityID> = [entityID]
        var changed = true
        while changed {
            changed = false
            for constraint in sketch.constraints {
                guard case let .equalRadius(first, second) = constraint else {
                    continue
                }
                if connected.contains(first), connected.insert(second).inserted {
                    changed = true
                }
                if connected.contains(second), connected.insert(first).inserted {
                    changed = true
                }
            }
        }
        return connected
    }

    private func isCircularRadiusAnchored(
        _ entityID: SketchEntityID,
        in sketch: Sketch
    ) -> Bool {
        let connected = equalRadiusEntityIDs(connectedTo: entityID, in: sketch)
        return sketch.constraints.contains { constraint in
            guard case let .fixed(reference) = constraint,
                  let fixedEntityID = circularRadiusEntityID(for: reference) else {
                return false
            }
            return connected.contains(fixedEntityID)
        }
    }

    private func hasHorizontalConstraint(
        _ lineID: SketchEntityID,
        in sketch: Sketch
    ) -> Bool {
        sketch.constraints.contains { constraint in
            if case .horizontal(lineID) = constraint {
                return true
            }
            return false
        }
    }

    private func hasVerticalConstraint(
        _ lineID: SketchEntityID,
        in sketch: Sketch
    ) -> Bool {
        sketch.constraints.contains { constraint in
            if case .vertical(lineID) = constraint {
                return true
            }
            return false
        }
    }

    private func isDirectlyFixed(
        _ reference: SketchReference,
        in sketch: Sketch
    ) -> Bool {
        sketch.constraints.contains { constraint in
            guard case let .fixed(fixedReference) = constraint else {
                return false
            }
            return fixedReference == reference
        }
    }

    private func point(
        for reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Point {
        switch reference {
        case let .entity(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .point(point) = entity else {
                throw invalidPointReference(owner)
            }
            return try resolvedPoint(point, owner: owner)
        case let .lineStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidPointReference(owner)
            }
            return try resolvedPoint(line.start, owner: owner)
        case let .lineEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidPointReference(owner)
            }
            return try resolvedPoint(line.end, owner: owner)
        case let .circleCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .circle(circle) = entity else {
                throw invalidPointReference(owner)
            }
            return try resolvedPoint(circle.center, owner: owner)
        case let .arcCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidPointReference(owner)
            }
            return try resolvedPoint(arc.center, owner: owner)
        case let .arcStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidPointReference(owner)
            }
            return try pointOnArc(arc, angle: arc.startAngle, owner: owner)
        case let .arcEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidPointReference(owner)
            }
            return try pointOnArc(arc, angle: arc.endAngle, owner: owner)
        case let .splineControlPoint(entityID, index):
            guard let entity = sketch.entities[entityID],
                  case let .spline(spline) = entity,
                  spline.controlPoints.indices.contains(index) else {
                throw invalidPointReference(owner)
            }
            return try resolvedPoint(spline.controlPoints[index], owner: owner)
        case .circleRadius, .arcRadius:
            throw invalidPointReference(owner)
        }
    }

    private func set(
        _ point: Point,
        for reference: SketchReference,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        let sketchPoint = SketchPoint(
            x: .length(point.x, .meter),
            y: .length(point.y, .meter)
        )
        switch reference {
        case let .entity(entityID):
            guard let entity = sketch.entities[entityID],
                  case .point = entity else {
                throw invalidPointReference(owner)
            }
            sketch.entities[entityID] = .point(sketchPoint)
        case let .lineStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case var .line(line) = entity else {
                throw invalidPointReference(owner)
            }
            line.start = sketchPoint
            sketch.entities[entityID] = .line(line)
        case let .lineEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case var .line(line) = entity else {
                throw invalidPointReference(owner)
            }
            line.end = sketchPoint
            sketch.entities[entityID] = .line(line)
        case let .circleCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case var .circle(circle) = entity else {
                throw invalidPointReference(owner)
            }
            circle.center = sketchPoint
            sketch.entities[entityID] = .circle(circle)
        case let .arcCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case var .arc(arc) = entity else {
                throw invalidPointReference(owner)
            }
            arc.center = sketchPoint
            try validateArc(arc, owner: owner)
            sketch.entities[entityID] = .arc(arc)
        case let .arcStart(entityID):
            try setArcEndpoint(point, entityID: entityID, isStart: true, in: &sketch, owner: owner)
        case let .arcEnd(entityID):
            try setArcEndpoint(point, entityID: entityID, isStart: false, in: &sketch, owner: owner)
        case let .splineControlPoint(entityID, index):
            guard let entity = sketch.entities[entityID],
                  case var .spline(spline) = entity,
                  spline.controlPoints.indices.contains(index) else {
                throw invalidPointReference(owner)
            }
            spline.controlPoints[index] = sketchPoint
            try validateSpline(spline, owner: owner)
            sketch.entities[entityID] = .spline(spline)
        case .circleRadius, .arcRadius:
            throw invalidPointReference(owner)
        }
    }

    private func setArcEndpoint(
        _ point: Point,
        entityID: SketchEntityID,
        isStart: Bool,
        in sketch: inout Sketch,
        owner: String
    ) throws {
        guard let entity = sketch.entities[entityID],
              case var .arc(arc) = entity else {
            throw invalidPointReference(owner)
        }
        let center = try resolvedPoint(arc.center, owner: owner)
        let deltaX = point.x - center.x
        let deltaY = point.y - center.y
        let radius = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard radius > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) would collapse an arc endpoint onto its center."
            )
        }
        let angle = atan2(deltaY, deltaX)
        arc.radius = .length(radius, .meter)
        if isStart {
            arc.startAngle = .angle(angle, .radian)
        } else {
            arc.endAngle = .angle(angle, .radian)
        }
        try validateArc(arc, owner: owner)
        sketch.entities[entityID] = .arc(arc)
    }

    private func validateArc(_ arc: SketchArc, owner: String) throws {
        let radius = try resolvedLength(arc.radius, owner: "\(owner) arc radius")
        guard radius > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) arc radius must be greater than zero."
            )
        }
        let startAngle = try resolvedAngle(arc.startAngle, owner: "\(owner) arc start angle")
        let endAngle = try resolvedAngle(arc.endAngle, owner: "\(owner) arc end angle")
        let span = normalizedPositiveSpan(startAngle: startAngle, endAngle: endAngle)
        guard span > tolerance,
              span < (Double.pi * 2.0 - tolerance) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) arc must remain a partial arc."
            )
        }
    }

    private func validateSpline(_ spline: SketchSpline, owner: String) throws {
        let count = spline.controlPoints.count
        guard count >= 4, (count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) spline control point count must be 3n + 1 and at least 4."
            )
        }
        let points = try spline.controlPoints.map { point in
            try resolvedPoint(point, owner: owner)
        }
        for segmentIndex in stride(from: 0, to: points.count - 1, by: 3) {
            let start = points[segmentIndex]
            let end = points[segmentIndex + 3]
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            guard sqrt(deltaX * deltaX + deltaY * deltaY) > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) spline cubic segment \(segmentIndex / 3) must not collapse to a point."
                )
            }
        }
    }

    private func validateLineLengths(in sketch: Sketch, owner: String) throws {
        for entity in sketch.entities.values {
            guard case let .line(line) = entity else {
                continue
            }
            let start = try resolvedPoint(line.start, owner: owner)
            let end = try resolvedPoint(line.end, owner: owner)
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            guard sqrt(deltaX * deltaX + deltaY * deltaY) > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) would collapse a constrained sketch line."
                )
            }
        }
    }

    private func validateLineAngleConstraints(
        affecting lineIDs: Set<SketchEntityID>,
        in sketch: Sketch,
        owner: String
    ) throws {
        guard lineIDs.isEmpty == false else {
            return
        }
        for constraint in sketch.constraints {
            switch constraint {
            case let .parallel(first, second):
                guard lineIDs.contains(first) || lineIDs.contains(second) else {
                    continue
                }
                let firstLine = try lineMetrics(for: first, in: sketch, owner: owner)
                let secondLine = try lineMetrics(for: second, in: sketch, owner: owner)
                guard angleMatches(firstLine.angle, secondLine.angle, period: Double.pi) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy a parallel sketch line constraint."
                    )
                }
            case let .perpendicular(first, second):
                guard lineIDs.contains(first) || lineIDs.contains(second) else {
                    continue
                }
                let firstLine = try lineMetrics(for: first, in: sketch, owner: owner)
                let secondLine = try lineMetrics(for: second, in: sketch, owner: owner)
                guard angleMatches(
                    firstLine.angle + Double.pi / 2.0,
                    secondLine.angle,
                    period: Double.pi
                ) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy a perpendicular sketch line constraint."
                    )
                }
            case .coincident,
                 .horizontal,
                 .vertical,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                continue
            }
        }
    }

    private func validateLineLengthConstraints(
        affecting lineIDs: Set<SketchEntityID>,
        in sketch: Sketch,
        owner: String
    ) throws {
        guard lineIDs.isEmpty == false else {
            return
        }
        for constraint in sketch.constraints {
            switch constraint {
            case let .equalLength(first, second):
                guard lineIDs.contains(first) || lineIDs.contains(second) else {
                    continue
                }
                let firstLine = try lineMetrics(for: first, in: sketch, owner: owner)
                let secondLine = try lineMetrics(for: second, in: sketch, owner: owner)
                guard abs(firstLine.length - secondLine.length) <= 1.0e-9 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy an equal length sketch line constraint."
                    )
                }
            case .coincident,
                 .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                continue
            }
        }
    }

    private func validateConcentricConstraints(in sketch: Sketch, owner: String) throws {
        for constraint in sketch.constraints {
            switch constraint {
            case let .concentric(first, second):
                let firstCenter = try circularMetrics(for: first, in: sketch, owner: owner).center
                let secondCenter = try circularMetrics(for: second, in: sketch, owner: owner).center
                guard pointsDiffer(firstCenter, secondCenter) == false else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy a concentric sketch constraint."
                    )
                }
            case .coincident,
                 .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                continue
            }
        }
    }

    private func validateEqualRadiusConstraints(in sketch: Sketch, owner: String) throws {
        for constraint in sketch.constraints {
            switch constraint {
            case let .equalRadius(first, second):
                let firstRadius = try circularMetrics(for: first, in: sketch, owner: owner).radius
                let secondRadius = try circularMetrics(for: second, in: sketch, owner: owner).radius
                guard abs(firstRadius - secondRadius) <= 1.0e-9 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy an equal radius sketch constraint."
                    )
                }
            case .coincident,
                 .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                continue
            }
        }
    }

    private func validateTangentConstraints(in sketch: Sketch, owner: String) throws {
        for constraint in sketch.constraints {
            switch constraint {
            case let .tangent(tangency):
                let residual: Double
                switch tangency {
                case let .lineCircular(lineID, circularID, side):
                    let line = try lineMetrics(for: lineID, in: sketch, owner: owner)
                    let circular = try circularMetrics(for: circularID, in: sketch, owner: owner)
                    let signedDistance = signedDistanceFromLine(
                        line,
                        to: circular.center,
                        normal: lineNormal(for: line)
                    )
                    residual = signedDistance - tangentTargetDistance(
                        side: side,
                        radius: circular.radius
                    )
                case let .circularCircular(firstID, secondID, contact):
                    let first = try circularMetrics(for: firstID, in: sketch, owner: owner)
                    let second = try circularMetrics(for: secondID, in: sketch, owner: owner)
                    let centerDistance = hypot(
                        second.center.x - first.center.x,
                        second.center.y - first.center.y
                    )
                    switch contact {
                    case .external:
                        residual = centerDistance - first.radius - second.radius
                    case .firstContainsSecond:
                        residual = centerDistance - first.radius + second.radius
                    case .secondContainsFirst:
                        residual = centerDistance + first.radius - second.radius
                    }
                }
                guard abs(residual) <= 1.0e-9 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy a tangent sketch constraint."
                    )
                }
            case .coincident,
                 .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                continue
            }
        }
    }

    private func validateSmoothSplineControlPointConstraints(in sketch: Sketch, owner: String) throws {
        for constraint in sketch.constraints {
            switch constraint {
            case let .smoothSplineControlPoint(entityID, index):
                let references = try smoothSplineControlPointReferences(
                    entityID: entityID,
                    index: index,
                    in: sketch,
                    owner: owner
                )
                guard try smoothSplineControlPointIsSatisfied(references, in: sketch, owner: owner) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy a smooth spline control point constraint."
                    )
                }
            case .coincident,
                 .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                continue
            }
        }
    }

    private func smoothSplineControlPointReferences(
        entityID: SketchEntityID,
        index: Int,
        in sketch: Sketch,
        owner: String
    ) throws -> SmoothSplineControlPointReferences {
        guard index > 0 else {
            throw invalidSmoothSplineControlPointConstraint(owner)
        }
        guard let entity = sketch.entities[entityID],
              case let .spline(spline) = entity,
              index < spline.controlPoints.count - 1,
              index.isMultiple(of: 3) else {
            throw invalidSmoothSplineControlPointConstraint(owner)
        }
        return SmoothSplineControlPointReferences(
            incoming: .splineControlPoint(entity: entityID, index: index - 1),
            knot: .splineControlPoint(entity: entityID, index: index),
            outgoing: .splineControlPoint(entity: entityID, index: index + 1)
        )
    }

    private func smoothSplineControlPointIsSatisfied(
        _ references: SmoothSplineControlPointReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Bool {
        let incomingPoint = try point(for: references.incoming, in: sketch, owner: owner)
        let knotPoint = try point(for: references.knot, in: sketch, owner: owner)
        let outgoingPoint = try point(for: references.outgoing, in: sketch, owner: owner)
        return abs((knotPoint.x - incomingPoint.x) - (outgoingPoint.x - knotPoint.x)) <= 1.0e-9 &&
            abs((knotPoint.y - incomingPoint.y) - (outgoingPoint.y - knotPoint.y)) <= 1.0e-9
    }

    private func mirroredSmoothSplinePoint(
        source: SketchReference,
        around knot: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Point {
        let sourcePoint = try point(for: source, in: sketch, owner: owner)
        let knotPoint = try point(for: knot, in: sketch, owner: owner)
        return Point(
            x: (2.0 * knotPoint.x) - sourcePoint.x,
            y: (2.0 * knotPoint.y) - sourcePoint.y
        )
    }

    private func splineEndpointTangentUpdates(
        fromLine lineID: SketchEntityID,
        in sketch: Sketch,
        owner: String
    ) throws -> [SplineEndpointTangentReferences] {
        var updates: [SplineEndpointTangentReferences] = []
        for constraint in sketch.constraints {
            switch constraint {
            case let .splineEndpointTangent(tangency):
                guard tangency.line == lineID else {
                    continue
                }
                let update = try splineEndpointTangentReferences(
                    splineID: tangency.splineEndpoint.splineID,
                    endpoint: tangency.splineEndpoint.endpoint,
                    lineID: tangency.line,
                    orientation: tangency.orientation,
                    in: sketch,
                    owner: owner
                )
                updates.append(update)
            case .coincident,
                 .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                continue
            }
        }
        return updates
    }

    private func alignSplineEndpointHandleToLine(
        _ references: SplineEndpointTangentReferences,
        in sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        guard isAnchored(references.handleReference, in: sketch) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot move a fixed spline tangent handle."
            )
        }
        let targetPoint = try alignedSplineEndpointHandlePoint(references, in: sketch, owner: owner)
        try assign(
            targetPoint,
            to: references.handleReference,
            in: &sketch,
            owner: owner,
            pending: &pending,
            affectedLineIDs: &affectedLineIDs
        )
    }

    private func splineEndpointTangentReferences(
        splineID: SketchEntityID,
        endpoint: SketchSplineEndpoint,
        lineID: SketchEntityID,
        orientation: SketchTangentOrientation,
        in sketch: Sketch,
        owner: String
    ) throws -> SplineEndpointTangentReferences {
        guard let entity = sketch.entities[splineID],
              case let .spline(spline) = entity,
              spline.controlPoints.count >= 4 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) spline endpoint tangent constraint requires a spline entity."
            )
        }
        _ = try lineMetrics(for: lineID, in: sketch, owner: owner)
        let endpointReference: SketchReference
        let handleReference: SketchReference
        switch endpoint {
        case .start:
            endpointReference = .splineControlPoint(entity: splineID, index: 0)
            handleReference = .splineControlPoint(entity: splineID, index: 1)
        case .end:
            endpointReference = .splineControlPoint(entity: splineID, index: spline.controlPoints.count - 1)
            handleReference = .splineControlPoint(entity: splineID, index: spline.controlPoints.count - 2)
        }
        return SplineEndpointTangentReferences(
            splineID: splineID,
            endpoint: endpoint,
            endpointReference: endpointReference,
            handleReference: handleReference,
            lineID: lineID,
            orientation: orientation
        )
    }

    private func tangentSplineEndpointPairReferences(
        _ first: SketchSplineEndpointReference,
        _ second: SketchSplineEndpointReference,
        orientation: SketchTangentOrientation,
        in sketch: Sketch,
        owner: String
    ) throws -> TangentSplineEndpointPairReferences {
        guard first != second else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) tangent spline endpoints constraint requires two distinct endpoints."
            )
        }
        return TangentSplineEndpointPairReferences(
            first: try tangentSplineEndpointReferences(
                first,
                orientation: orientation,
                in: sketch,
                owner: owner
            ),
            second: try tangentSplineEndpointReferences(
                second,
                orientation: orientation,
                in: sketch,
                owner: owner
            )
        )
    }

    private func tangentSplineEndpointReferences(
        _ reference: SketchSplineEndpointReference,
        orientation: SketchTangentOrientation,
        in sketch: Sketch,
        owner: String
    ) throws -> TangentSplineEndpointReferences {
        guard let entity = sketch.entities[reference.splineID],
              case let .spline(spline) = entity,
              spline.controlPoints.count >= 4 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) tangent spline endpoints constraint requires spline entities."
            )
        }
        let endpointReference: SketchReference
        let handleReference: SketchReference
        let curvatureReference: SketchReference
        switch reference.endpoint {
        case .start:
            endpointReference = .splineControlPoint(entity: reference.splineID, index: 0)
            handleReference = .splineControlPoint(entity: reference.splineID, index: 1)
            curvatureReference = .splineControlPoint(entity: reference.splineID, index: 2)
        case .end:
            endpointReference = .splineControlPoint(entity: reference.splineID, index: spline.controlPoints.count - 1)
            handleReference = .splineControlPoint(entity: reference.splineID, index: spline.controlPoints.count - 2)
            curvatureReference = .splineControlPoint(entity: reference.splineID, index: spline.controlPoints.count - 3)
        }
        return TangentSplineEndpointReferences(
            endpoint: reference,
            endpointReference: endpointReference,
            handleReference: handleReference,
            curvatureReference: curvatureReference,
            orientation: orientation
        )
    }

    private func splineEndpointTangentIsSatisfied(
        _ references: SplineEndpointTangentReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Bool {
        let tangentAngle = try splineEndpointTangentAngle(references, in: sketch, owner: owner)
        let line = try lineMetrics(for: references.lineID, in: sketch, owner: owner)
        return angleMatches(
            tangentAngle,
            orientedAngle(line.angle, orientation: references.orientation),
            period: Double.pi * 2.0
        )
    }

    private func splineEndpointLineAngle(
        _ references: SplineEndpointTangentReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        orientedAngle(
            try splineEndpointTangentAngle(references, in: sketch, owner: owner),
            orientation: references.orientation
        )
    }

    private func splineEndpointTangentAngle(
        _ references: SplineEndpointTangentReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        let endpointPoint = try point(for: references.endpointReference, in: sketch, owner: owner)
        let handlePoint = try point(for: references.handleReference, in: sketch, owner: owner)
        let deltaX: Double
        let deltaY: Double
        switch references.endpoint {
        case .start:
            deltaX = handlePoint.x - endpointPoint.x
            deltaY = handlePoint.y - endpointPoint.y
        case .end:
            deltaX = endpointPoint.x - handlePoint.x
            deltaY = endpointPoint.y - handlePoint.y
        }
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) spline tangent handle must not collapse onto its endpoint."
            )
        }
        return atan2(deltaY, deltaX)
    }

    private func tangentSplineEndpointsAreSatisfied(
        _ pair: TangentSplineEndpointPairReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Bool {
        let firstAngle = try tangentSplineEndpointAngle(pair.first, in: sketch, owner: owner)
        let secondAngle = try tangentSplineEndpointAngle(pair.second, in: sketch, owner: owner)
        return angleMatches(
            firstAngle,
            orientedAngle(secondAngle, orientation: pair.first.orientation),
            period: Double.pi * 2.0
        )
    }

    private func smoothSplineEndpointsAreSatisfied(
        _ pair: TangentSplineEndpointPairReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Bool {
        let firstEndpoint = try point(for: pair.first.endpointReference, in: sketch, owner: owner)
        let secondEndpoint = try point(for: pair.second.endpointReference, in: sketch, owner: owner)
        guard pointsDiffer(firstEndpoint, secondEndpoint) == false else {
            return false
        }
        let firstVector = try tangentSplineEndpointVector(pair.first, in: sketch, owner: owner)
        let secondVector = try tangentSplineEndpointVector(pair.second, in: sketch, owner: owner)
        let orientedSecondVector = orientedVector(
            secondVector,
            orientation: pair.first.orientation
        )
        guard pointsDiffer(firstVector, orientedSecondVector) == false else {
            return false
        }
        let firstSecondDerivative = try splineEndpointSecondDerivativeVector(
            pair.first,
            in: sketch,
            owner: owner
        )
        let secondSecondDerivative = try splineEndpointSecondDerivativeVector(
            pair.second,
            in: sketch,
            owner: owner
        )
        return pointsDiffer(firstSecondDerivative, secondSecondDerivative) == false
    }

    private func smoothSplineEndpointsShareEndpoint(
        _ pair: TangentSplineEndpointPairReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Bool {
        let firstEndpoint = try point(for: pair.first.endpointReference, in: sketch, owner: owner)
        let secondEndpoint = try point(for: pair.second.endpointReference, in: sketch, owner: owner)
        return pointsDiffer(firstEndpoint, secondEndpoint) == false
    }

    private func smoothSplineEndpointCanMove(
        _ references: TangentSplineEndpointReferences,
        shouldAlignEndpoint: Bool,
        in sketch: Sketch
    ) -> Bool {
        if shouldAlignEndpoint,
           isAnchored(references.endpointReference, in: sketch) {
            return false
        }
        return isAnchored(references.handleReference, in: sketch) == false &&
            isAnchored(references.curvatureReference, in: sketch) == false
    }

    private func tangentSplineEndpointAngle(
        _ references: TangentSplineEndpointReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        let vector = try tangentSplineEndpointVector(references, in: sketch, owner: owner)
        return atan2(vector.y, vector.x)
    }

    private func tangentSplineEndpointVector(
        _ references: TangentSplineEndpointReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Point {
        let endpointPoint = try point(for: references.endpointReference, in: sketch, owner: owner)
        let handlePoint = try point(for: references.handleReference, in: sketch, owner: owner)
        let deltaX: Double
        let deltaY: Double
        switch references.endpoint.endpoint {
        case .start:
            deltaX = handlePoint.x - endpointPoint.x
            deltaY = handlePoint.y - endpointPoint.y
        case .end:
            deltaX = endpointPoint.x - handlePoint.x
            deltaY = endpointPoint.y - handlePoint.y
        }
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) spline tangent handle must not collapse onto its endpoint."
            )
        }
        return Point(x: deltaX, y: deltaY)
    }

    private func splineEndpointSecondDerivativeVector(
        _ references: TangentSplineEndpointReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Point {
        let endpointPoint = try point(for: references.endpointReference, in: sketch, owner: owner)
        let handlePoint = try point(for: references.handleReference, in: sketch, owner: owner)
        let curvaturePoint = try point(for: references.curvatureReference, in: sketch, owner: owner)
        return Point(
            x: endpointPoint.x - 2.0 * handlePoint.x + curvaturePoint.x,
            y: endpointPoint.y - 2.0 * handlePoint.y + curvaturePoint.y
        )
    }

    private func alignedSplineEndpointHandlePoint(
        _ references: SplineEndpointTangentReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Point {
        let endpointPoint = try point(for: references.endpointReference, in: sketch, owner: owner)
        let handlePoint = try point(for: references.handleReference, in: sketch, owner: owner)
        let line = try lineMetrics(for: references.lineID, in: sketch, owner: owner)
        let currentVector: Point
        switch references.endpoint {
        case .start:
            currentVector = Point(
                x: handlePoint.x - endpointPoint.x,
                y: handlePoint.y - endpointPoint.y
            )
        case .end:
            currentVector = Point(
                x: endpointPoint.x - handlePoint.x,
                y: endpointPoint.y - handlePoint.y
            )
        }
        let currentLength = sqrt(currentVector.x * currentVector.x + currentVector.y * currentVector.y)
        guard currentLength > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) spline tangent handle must not collapse onto its endpoint."
            )
        }
        let lineDirection = orientedVector(
            Point(x: cos(line.angle), y: sin(line.angle)),
            orientation: references.orientation
        )
        let tangentVector = Point(
            x: lineDirection.x * currentLength,
            y: lineDirection.y * currentLength
        )
        switch references.endpoint {
        case .start:
            return Point(
                x: endpointPoint.x + tangentVector.x,
                y: endpointPoint.y + tangentVector.y
            )
        case .end:
            return Point(
                x: endpointPoint.x - tangentVector.x,
                y: endpointPoint.y - tangentVector.y
            )
        }
    }

    private func propagateTangentSplineEndpointUpdate(
        source: TangentSplineEndpointReferences,
        target: TangentSplineEndpointReferences,
        changedReference: SketchReference,
        sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        if isAnchored(target.handleReference, in: sketch) == false {
            try alignTangentSplineEndpointHandle(
                target: target,
                source: source,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        } else if changedReference == source.endpointReference,
                  isAnchored(source.handleReference, in: sketch) == false {
            try alignTangentSplineEndpointHandle(
                target: source,
                source: target,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        } else if angleMatches(
            try tangentSplineEndpointAngle(source, in: sketch, owner: owner),
            orientedAngle(
                try tangentSplineEndpointAngle(target, in: sketch, owner: owner),
                orientation: source.orientation
            ),
            period: Double.pi * 2.0
        ) == false {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot satisfy tangent spline endpoints with fixed spline handles."
            )
        }
    }

    private func propagateSmoothSplineEndpointUpdate(
        source: TangentSplineEndpointReferences,
        target: TangentSplineEndpointReferences,
        changedReference: SketchReference,
        sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        if changedReference == source.endpointReference {
            guard isAnchored(target.endpointReference, in: sketch) == false else {
                guard try smoothSplineEndpointsAreSatisfied(
                    TangentSplineEndpointPairReferences(first: source, second: target),
                    in: sketch,
                    owner: owner
                ) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy smooth spline endpoints with fixed spline endpoints."
                    )
                }
                return
            }
            try alignSmoothSplineEndpoint(
                target: target,
                source: source,
                shouldAlignEndpoint: true,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
            return
        }

        if changedReference == source.handleReference {
            if isAnchored(target.handleReference, in: sketch) {
                guard try tangentSplineEndpointsAreSatisfied(
                    TangentSplineEndpointPairReferences(first: source, second: target),
                    in: sketch,
                    owner: owner
                ) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy smooth spline endpoints with fixed spline handles."
                    )
                }
            } else {
                try alignSmoothSplineEndpointHandle(
                    target: target,
                    source: source,
                    in: &sketch,
                    owner: owner,
                    pending: &pending,
                    affectedLineIDs: &affectedLineIDs
                )
            }
            if isAnchored(target.curvatureReference, in: sketch) {
                guard try smoothSplineEndpointsAreSatisfied(
                    TangentSplineEndpointPairReferences(first: source, second: target),
                    in: sketch,
                    owner: owner
                ) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy smooth spline endpoints with fixed curvature handles."
                    )
                }
            } else {
                try alignSmoothSplineEndpointCurvatureHandle(
                    target: target,
                    source: source,
                    in: &sketch,
                    owner: owner,
                    pending: &pending,
                    affectedLineIDs: &affectedLineIDs
                )
            }
            return
        }

        if changedReference == source.curvatureReference {
            if isAnchored(target.curvatureReference, in: sketch) {
                guard try smoothSplineEndpointsAreSatisfied(
                    TangentSplineEndpointPairReferences(first: source, second: target),
                    in: sketch,
                    owner: owner
                ) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy smooth spline endpoints with fixed curvature handles."
                    )
                }
            } else {
                try alignSmoothSplineEndpointCurvatureHandle(
                    target: target,
                    source: source,
                    in: &sketch,
                    owner: owner,
                    pending: &pending,
                    affectedLineIDs: &affectedLineIDs
                )
            }
            return
        }

        if smoothSplineEndpointCanMove(target, shouldAlignEndpoint: false, in: sketch) {
            try alignSmoothSplineEndpointHandle(
                target: target,
                source: source,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
            try alignSmoothSplineEndpointCurvatureHandle(
                target: target,
                source: source,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        } else if try smoothSplineEndpointsAreSatisfied(
            TangentSplineEndpointPairReferences(first: source, second: target),
            in: sketch,
            owner: owner
        ) == false {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot satisfy smooth spline endpoints with fixed spline handles."
            )
        }
    }

    private func alignTangentSplineEndpointHandle(
        target: TangentSplineEndpointReferences,
        source: TangentSplineEndpointReferences,
        in sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        guard isAnchored(target.handleReference, in: sketch) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot move a fixed spline tangent handle."
            )
        }
        let targetPoint = try alignedTangentSplineEndpointHandlePoint(
            target: target,
            source: source,
            in: sketch,
            owner: owner
        )
        try assign(
            targetPoint,
            to: target.handleReference,
            in: &sketch,
            owner: owner,
            pending: &pending,
            affectedLineIDs: &affectedLineIDs
        )
    }

    private func alignSmoothSplineEndpoint(
        target: TangentSplineEndpointReferences,
        source: TangentSplineEndpointReferences,
        shouldAlignEndpoint: Bool,
        in sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        if shouldAlignEndpoint {
            guard isAnchored(target.endpointReference, in: sketch) == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) cannot move a fixed spline endpoint."
                )
            }
            let sourceEndpointPoint = try point(for: source.endpointReference, in: sketch, owner: owner)
            try assign(
                sourceEndpointPoint,
                to: target.endpointReference,
                in: &sketch,
                owner: owner,
                pending: &pending,
                affectedLineIDs: &affectedLineIDs
            )
        }
        try alignSmoothSplineEndpointHandle(
            target: target,
            source: source,
            in: &sketch,
            owner: owner,
            pending: &pending,
            affectedLineIDs: &affectedLineIDs
        )
        try alignSmoothSplineEndpointCurvatureHandle(
            target: target,
            source: source,
            in: &sketch,
            owner: owner,
            pending: &pending,
            affectedLineIDs: &affectedLineIDs
        )
    }

    private func alignSmoothSplineEndpointHandle(
        target: TangentSplineEndpointReferences,
        source: TangentSplineEndpointReferences,
        in sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        guard isAnchored(target.handleReference, in: sketch) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot move a fixed spline tangent handle."
            )
        }
        let targetPoint = try alignedSmoothSplineEndpointHandlePoint(
            target: target,
            source: source,
            in: sketch,
            owner: owner
        )
        try assign(
            targetPoint,
            to: target.handleReference,
            in: &sketch,
            owner: owner,
            pending: &pending,
            affectedLineIDs: &affectedLineIDs
        )
    }

    private func alignSmoothSplineEndpointCurvatureHandle(
        target: TangentSplineEndpointReferences,
        source: TangentSplineEndpointReferences,
        in sketch: inout Sketch,
        owner: String,
        pending: inout [(reference: SketchReference, point: Point)],
        affectedLineIDs: inout Set<SketchEntityID>
    ) throws {
        guard isAnchored(target.curvatureReference, in: sketch) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot move a fixed spline curvature handle."
            )
        }
        let targetPoint = try alignedSmoothSplineEndpointCurvaturePoint(
            target: target,
            source: source,
            in: sketch,
            owner: owner
        )
        try assign(
            targetPoint,
            to: target.curvatureReference,
            in: &sketch,
            owner: owner,
            pending: &pending,
            affectedLineIDs: &affectedLineIDs
        )
    }

    private func alignedSmoothSplineEndpointHandlePoint(
        target: TangentSplineEndpointReferences,
        source: TangentSplineEndpointReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Point {
        let targetEndpointPoint = try point(for: target.endpointReference, in: sketch, owner: owner)
        let sourceVector = orientedVector(
            try tangentSplineEndpointVector(source, in: sketch, owner: owner),
            orientation: target.orientation
        )
        switch target.endpoint.endpoint {
        case .start:
            return Point(
                x: targetEndpointPoint.x + sourceVector.x,
                y: targetEndpointPoint.y + sourceVector.y
            )
        case .end:
            return Point(
                x: targetEndpointPoint.x - sourceVector.x,
                y: targetEndpointPoint.y - sourceVector.y
            )
        }
    }

    private func alignedSmoothSplineEndpointCurvaturePoint(
        target: TangentSplineEndpointReferences,
        source: TangentSplineEndpointReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Point {
        let targetEndpointPoint = try point(for: target.endpointReference, in: sketch, owner: owner)
        let targetHandlePoint = try point(for: target.handleReference, in: sketch, owner: owner)
        let sourceSecondDerivative = try splineEndpointSecondDerivativeVector(
            source,
            in: sketch,
            owner: owner
        )
        return Point(
            x: sourceSecondDerivative.x - targetEndpointPoint.x + 2.0 * targetHandlePoint.x,
            y: sourceSecondDerivative.y - targetEndpointPoint.y + 2.0 * targetHandlePoint.y
        )
    }

    private func alignedTangentSplineEndpointHandlePoint(
        target: TangentSplineEndpointReferences,
        source: TangentSplineEndpointReferences,
        in sketch: Sketch,
        owner: String
    ) throws -> Point {
        let endpointPoint = try point(for: target.endpointReference, in: sketch, owner: owner)
        let handlePoint = try point(for: target.handleReference, in: sketch, owner: owner)
        let currentVector: Point
        switch target.endpoint.endpoint {
        case .start:
            currentVector = Point(
                x: handlePoint.x - endpointPoint.x,
                y: handlePoint.y - endpointPoint.y
            )
        case .end:
            currentVector = Point(
                x: endpointPoint.x - handlePoint.x,
                y: endpointPoint.y - handlePoint.y
            )
        }
        let currentLength = sqrt(currentVector.x * currentVector.x + currentVector.y * currentVector.y)
        guard currentLength > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) spline tangent handle must not collapse onto its endpoint."
            )
        }
        let sourceAngle = try tangentSplineEndpointAngle(source, in: sketch, owner: owner)
        let sourceDirection = orientedVector(
            Point(x: cos(sourceAngle), y: sin(sourceAngle)),
            orientation: target.orientation
        )
        let tangentVector = Point(
            x: sourceDirection.x * currentLength,
            y: sourceDirection.y * currentLength
        )
        switch target.endpoint.endpoint {
        case .start:
            return Point(
                x: endpointPoint.x + tangentVector.x,
                y: endpointPoint.y + tangentVector.y
            )
        case .end:
            return Point(
                x: endpointPoint.x - tangentVector.x,
                y: endpointPoint.y - tangentVector.y
            )
        }
    }

    private func orientedAngle(
        _ angle: Double,
        orientation: SketchTangentOrientation
    ) -> Double {
        orientation == .aligned ? angle : angle + Double.pi
    }

    private func orientedVector(
        _ vector: Point,
        orientation: SketchTangentOrientation
    ) -> Point {
        orientation == .aligned
            ? vector
            : Point(x: -vector.x, y: -vector.y)
    }

    private func validateSplineEndpointTangentConstraints(in sketch: Sketch, owner: String) throws {
        for constraint in sketch.constraints {
            switch constraint {
            case let .splineEndpointTangent(tangency):
                let references = try splineEndpointTangentReferences(
                    splineID: tangency.splineEndpoint.splineID,
                    endpoint: tangency.splineEndpoint.endpoint,
                    lineID: tangency.line,
                    orientation: tangency.orientation,
                    in: sketch,
                    owner: owner
                )
                guard try splineEndpointTangentIsSatisfied(references, in: sketch, owner: owner) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy a spline endpoint tangent constraint."
                    )
                }
            case let .tangentSplineEndpoints(tangency):
                let pair = try tangentSplineEndpointPairReferences(
                    tangency.first,
                    tangency.second,
                    orientation: tangency.orientation,
                    in: sketch,
                    owner: owner
                )
                guard try tangentSplineEndpointsAreSatisfied(pair, in: sketch, owner: owner) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy a tangent spline endpoints constraint."
                    )
                }
            case let .smoothSplineEndpoints(tangency):
                let pair = try tangentSplineEndpointPairReferences(
                    tangency.first,
                    tangency.second,
                    orientation: tangency.orientation,
                    in: sketch,
                    owner: owner
                )
                guard try smoothSplineEndpointsAreSatisfied(pair, in: sketch, owner: owner) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) cannot satisfy a smooth spline endpoints constraint."
                    )
                }
            case .coincident,
                 .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .fixed:
                continue
            }
        }
    }

    private func lineMetrics(
        for lineID: SketchEntityID,
        in sketch: Sketch,
        owner: String
    ) throws -> LineMetrics {
        guard let entity = sketch.entities[lineID],
              case let .line(line) = entity else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references an unsupported sketch line."
            )
        }
        let start = try resolvedPoint(line.start, owner: "\(owner) line start")
        let end = try resolvedPoint(line.end, owner: "\(owner) line end")
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) would collapse a constrained sketch line."
            )
        }
        return LineMetrics(
            start: start,
            end: end,
            length: length,
            angle: atan2(deltaY, deltaX)
        )
    }

    private func sketchPoint(x: Double, y: Double) -> SketchPoint {
        SketchPoint(
            x: .length(x, .meter),
            y: .length(y, .meter)
        )
    }

    private func pointOnArc(
        _ arc: SketchArc,
        angle: CADExpression,
        owner: String
    ) throws -> Point {
        let center = try resolvedPoint(arc.center, owner: owner)
        let radius = try resolvedLength(arc.radius, owner: "\(owner) arc radius")
        let resolvedAngle = try resolvedAngle(angle, owner: "\(owner) arc angle")
        return Point(
            x: center.x + cos(resolvedAngle) * radius,
            y: center.y + sin(resolvedAngle) * radius
        )
    }

    private func resolvedPoint(_ point: SketchPoint, owner: String) throws -> Point {
        Point(
            x: try resolvedLength(point.x, owner: "\(owner) x"),
            y: try resolvedLength(point.y, owner: "\(owner) y")
        )
    }

    private func resolvedLength(_ expression: CADExpression, owner: String) throws -> Double {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a length."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite length."
            )
        }
        return quantity.value
    }

    private func resolvedAngle(_ expression: CADExpression, owner: String) throws -> Double {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == .angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to an angle."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite angle."
            )
        }
        return quantity.value
    }

    private func lineID(for reference: SketchReference) -> SketchEntityID? {
        switch reference {
        case let .lineStart(entityID), let .lineEnd(entityID):
            return entityID
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcStart,
             .arcEnd,
             .arcRadius,
             .splineControlPoint:
            return nil
        }
    }

    private func circularCenterEntityID(for reference: SketchReference) -> SketchEntityID? {
        switch reference {
        case let .circleCenter(entityID), let .arcCenter(entityID):
            return entityID
        case .entity,
             .lineStart,
             .lineEnd,
             .circleRadius,
             .arcStart,
             .arcEnd,
             .arcRadius,
             .splineControlPoint:
            return nil
        }
    }

    private func circularRadiusEntityID(for reference: SketchReference) -> SketchEntityID? {
        switch reference {
        case let .circleRadius(entityID), let .arcRadius(entityID):
            return entityID
        case .entity,
             .lineStart,
             .lineEnd,
             .circleCenter,
             .arcCenter,
             .arcStart,
             .arcEnd,
             .splineControlPoint:
            return nil
        }
    }

    private func circularCenterReference(
        for entityID: SketchEntityID,
        in sketch: Sketch
    ) -> SketchReference? {
        guard let entity = sketch.entities[entityID] else {
            return nil
        }
        switch entity {
        case .circle:
            return .circleCenter(entityID)
        case .arc:
            return .arcCenter(entityID)
        case .point, .line, .spline:
            return nil
        }
    }

    private func circularRadiusReference(
        for entityID: SketchEntityID,
        in sketch: Sketch
    ) -> SketchReference? {
        guard let entity = sketch.entities[entityID] else {
            return nil
        }
        switch entity {
        case .circle:
            return .circleRadius(entityID)
        case .arc:
            return .arcRadius(entityID)
        case .point, .line, .spline:
            return nil
        }
    }

    private func otherLineEndpoint(for reference: SketchReference) -> SketchReference? {
        switch reference {
        case let .lineStart(entityID):
            return .lineEnd(entityID)
        case let .lineEnd(entityID):
            return .lineStart(entityID)
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcStart,
             .arcEnd,
             .arcRadius,
             .splineControlPoint:
            return nil
        }
    }

    private func pointsDiffer(_ lhs: Point, _ rhs: Point) -> Bool {
        abs(lhs.x - rhs.x) > tolerance || abs(lhs.y - rhs.y) > tolerance
    }

    private func angleMatches(_ lhs: Double, _ rhs: Double, period: Double) -> Bool {
        abs(normalizedSignedAngle(lhs - rhs, period: period)) <= 1.0e-9
    }

    private func equivalentAngle(_ angle: Double, near reference: Double, period: Double) -> Double {
        reference + normalizedSignedAngle(angle - reference, period: period)
    }

    private func normalizedSignedAngle(_ angle: Double, period: Double) -> Double {
        var result = angle
        let halfPeriod = period / 2.0
        while result < -halfPeriod {
            result += period
        }
        while result > halfPeriod {
            result -= period
        }
        return result
    }

    private func normalizedPositiveSpan(startAngle: Double, endAngle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= 0.0 {
            span += fullCircle
        }
        while span > fullCircle {
            span -= fullCircle
        }
        return span
    }

    private func invalidPointReference(_ owner: String) -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "\(owner) references an unsupported sketch point."
        )
    }

    private func invalidSmoothSplineControlPointConstraint(_ owner: String) -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "\(owner) requires an internal cubic spline control point."
        )
    }
}
