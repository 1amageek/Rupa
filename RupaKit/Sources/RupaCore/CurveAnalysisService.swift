import Foundation
import SwiftCAD
import RupaCoreTypes

public struct CurveAnalysisService: Sendable {
    private struct EndpointPairKey: Hashable {
        var firstReference: String
        var secondReference: String

        init(_ firstReference: String, _ secondReference: String) {
            if firstReference <= secondReference {
                self.firstReference = firstReference
                self.secondReference = secondReference
            } else {
                self.firstReference = secondReference
                self.secondReference = firstReference
            }
        }
    }

    private struct EndpointSample {
        var entityID: SketchEntityID
        var referenceDescription: String
        var sample: CurveEvaluationSample
    }

    private struct PendingEndpointJoin {
        var first: EndpointSample
        var second: EndpointSample
        var constraintKinds: Set<String>
        var requiredContinuity: CurveAnalysisResult.ContinuityLevel
    }

    private let sampler: SketchCurveSampler
    private let positionTolerance: Double
    private let tangentTolerance: Double
    private let curvatureTolerance: Double

    public init(
        samplesPerSegment: Int = 16,
        positionTolerance: Double = 1.0e-7,
        tangentTolerance: Double = 1.0e-4,
        curvatureTolerance: Double = 1.0e-4
    ) {
        self.sampler = SketchCurveSampler(samplesPerSegment: samplesPerSegment)
        self.positionTolerance = positionTolerance
        self.tangentTolerance = tangentTolerance
        self.curvatureTolerance = curvatureTolerance
    }

    public func analyze(
        document: DesignDocument,
        displayUnit: LengthDisplayUnit,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> CurveAnalysisResult {
        try validate(document: document, objectRegistry: objectRegistry)

        let sceneNodeIDsByFeatureID = sceneNodeIDsByFeatureID(in: document)
        var curves: [CurveAnalysisResult.CurveEntry] = []
        var continuityJoins: [CurveAnalysisResult.ContinuityJoin] = []

        for featureID in document.cadDocument.designGraph.order {
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  case .sketch(let sketch) = feature.operation else {
                continue
            }
            let sceneNodeID = sceneNodeIDsByFeatureID[featureID]?.description
            for (entityID, entity) in sketch.entities.sorted(by: { $0.key.description < $1.key.description }) {
                guard let entry = try curveEntry(
                    featureID: featureID,
                    featureName: feature.name,
                    sceneNodeID: sceneNodeID,
                    entityID: entityID,
                    entity: entity,
                    document: document
                ) else {
                    continue
                }
                curves.append(entry)

                if case .spline(let spline) = entity {
                    let controlPoints = try spline.controlPoints.map { point in
                        try resolvedPoint(point, document: document)
                    }
                    continuityJoins.append(
                        contentsOf: splineContinuityJoins(
                            featureID: featureID,
                            entityID: entityID,
                            controlPoints: controlPoints
                        )
                    )
                }
            }
            continuityJoins.append(
                contentsOf: try constrainedEndpointContinuityJoins(
                    featureID: featureID,
                    sketch: sketch,
                    document: document
                )
            )
        }

        return result(
            displayUnit: displayUnit,
            curves: curves,
            continuityJoins: continuityJoins,
            message: "Curve analysis completed with \(curves.count) source curve references."
        )
    }

    public func analyze(
        document: DesignDocument,
        featureID: FeatureID,
        entityID: SketchEntityID,
        displayUnit: LengthDisplayUnit,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> CurveAnalysisResult {
        try validate(document: document, objectRegistry: objectRegistry)

        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              case .sketch(let sketch) = feature.operation,
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Curve analysis source curve could not be resolved."
            )
        }

        let sceneNodeID = sceneNodeIDsByFeatureID(in: document)[featureID]?.description
        var curves: [CurveAnalysisResult.CurveEntry] = []
        if let entry = try curveEntry(
            featureID: featureID,
            featureName: feature.name,
            sceneNodeID: sceneNodeID,
            entityID: entityID,
            entity: entity,
            document: document
        ) {
            curves.append(entry)
        }

        let entityDescription = entityID.description
        var continuityJoins: [CurveAnalysisResult.ContinuityJoin] = []
        if case .spline(let spline) = entity {
            let controlPoints = try spline.controlPoints.map { point in
                try resolvedPoint(point, document: document)
            }
            continuityJoins.append(
                contentsOf: splineContinuityJoins(
                    featureID: featureID,
                    entityID: entityID,
                    controlPoints: controlPoints
                )
            )
        }
        continuityJoins.append(
            contentsOf: try constrainedEndpointContinuityJoins(
                featureID: featureID,
                sketch: sketch,
                document: document
            ).filter { join in
                join.firstEntityID == entityDescription || join.secondEntityID == entityDescription
            }
        )

        return result(
            displayUnit: displayUnit,
            curves: curves,
            continuityJoins: continuityJoins,
            message: "Curve analysis completed for source curve \(entityID.description)."
        )
    }

    private func validate(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before curve analysis: \(String(describing: error))"
            )
        }
    }

    private func result(
        displayUnit: LengthDisplayUnit,
        curves: [CurveAnalysisResult.CurveEntry],
        continuityJoins: [CurveAnalysisResult.ContinuityJoin],
        message: String
    ) -> CurveAnalysisResult {
        return CurveAnalysisResult(
            displayUnit: displayUnit,
            counts: CurveAnalysisResult.Counts(
                curveCount: curves.count,
                sampleCount: curves.reduce(0) { $0 + $1.samples.count },
                continuityJoinCount: continuityJoins.count
            ),
            curves: curves,
            continuityJoins: continuityJoins,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: message
                ),
            ]
        )
    }

    private func curveEntry(
        featureID: FeatureID,
        featureName: String?,
        sceneNodeID: String?,
        entityID: SketchEntityID,
        entity: SketchEntity,
        document: DesignDocument
    ) throws -> CurveAnalysisResult.CurveEntry? {
        let selectionComponentID = sceneNodeID.map { _ in
            SelectionComponentID.sketchEntity(featureID: featureID, entityID: entityID).rawValue
        }
        let samples: [CurveEvaluationSample]
        let curveKind: CurveAnalysisResult.CurveKind
        switch entity {
        case .point:
            return nil
        case .line(let line):
            samples = sampler.lineSamples(
                start: try resolvedPoint(line.start, document: document),
                end: try resolvedPoint(line.end, document: document)
            )
            curveKind = .line
        case .circle(let circle):
            samples = sampler.circleSamples(
                center: try resolvedPoint(circle.center, document: document),
                radius: try resolvedValue(circle.radius, kind: .length, document: document)
            )
            curveKind = .circle
        case .arc(let arc):
            samples = sampler.arcSamples(
                center: try resolvedPoint(arc.center, document: document),
                radius: try resolvedValue(arc.radius, kind: .length, document: document),
                startAngle: try resolvedValue(arc.startAngle, kind: .angle, document: document),
                endAngle: try resolvedValue(arc.endAngle, kind: .angle, document: document)
            )
            curveKind = .arc
        case .spline(let spline):
            let controlPoints = try spline.controlPoints.map { point in
                try resolvedPoint(point, document: document)
            }
            samples = sampler.splineSamples(for: controlPoints)
            curveKind = .spline
        }
        guard samples.isEmpty == false else {
            return nil
        }
        return CurveAnalysisResult.CurveEntry(
            sourceFeatureID: featureID.description,
            sourceFeatureName: featureName,
            sceneNodeID: sceneNodeID,
            entityID: entityID.description,
            curveKind: curveKind,
            selectionComponentID: selectionComponentID,
            samples: samples,
            maxAbsCurvature: samples.map { abs($0.curvature) }.max() ?? 0.0,
            approximateLength: sampler.approximateLength(of: samples)
        )
    }

    private func splineContinuityJoins(
        featureID: FeatureID,
        entityID: SketchEntityID,
        controlPoints: [CADCore.Point2D]
    ) -> [CurveAnalysisResult.ContinuityJoin] {
        guard controlPoints.count >= 7,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            return []
        }
        let segmentCount = (controlPoints.count - 1) / 3
        var joins: [CurveAnalysisResult.ContinuityJoin] = []
        joins.reserveCapacity(max(segmentCount - 1, 0))
        for segmentIndex in 0 ..< (segmentCount - 1) {
            guard let first = sampler.splineSegmentSample(
                for: controlPoints,
                segmentIndex: segmentIndex,
                t: 1.0
            ),
            let second = sampler.splineSegmentSample(
                for: controlPoints,
                segmentIndex: segmentIndex + 1,
                t: 0.0
            ) else {
                continue
            }
            let positionGap = distance(first.point, second.point)
            let tangentAngle = angleBetween(first.tangent, second.tangent)
            let curvatureGap = abs(first.curvature - second.curvature)
            joins.append(
                CurveAnalysisResult.ContinuityJoin(
                    sourceFeatureID: featureID.description,
                    joinKind: .internalSplineKnot,
                    firstEntityID: entityID.description,
                    firstReference: "splineControlPoint:\(entityID.description):\(segmentIndex * 3 + 3)",
                    firstParameter: first.parameter,
                    secondEntityID: entityID.description,
                    secondReference: "splineControlPoint:\(entityID.description):\(segmentIndex * 3 + 3)",
                    secondParameter: second.parameter,
                    constraintKinds: ["splineKnot"],
                    requiredContinuity: nil,
                    continuity: continuityLevel(
                        positionGap: positionGap,
                        tangentAngle: tangentAngle,
                        curvatureGap: curvatureGap
                    ),
                    positionGap: positionGap,
                    tangentAngle: tangentAngle,
                    curvatureGap: curvatureGap
                )
            )
        }
        return joins
    }

    private func constrainedEndpointContinuityJoins(
        featureID: FeatureID,
        sketch: Sketch,
        document: DesignDocument
    ) throws -> [CurveAnalysisResult.ContinuityJoin] {
        var pendingByPair: [EndpointPairKey: PendingEndpointJoin] = [:]

        for constraint in sketch.constraints {
            switch constraint {
            case let .coincident(first, second):
                try mergeEndpointJoin(
                    first: endpointSample(for: first, sketch: sketch, document: document),
                    second: endpointSample(for: second, sketch: sketch, document: document),
                    constraintKind: "coincident",
                    requiredContinuity: .g0,
                    into: &pendingByPair
                )
            case let .tangentSplineEndpoints(constraint):
                try mergeEndpointJoin(
                    first: endpointSample(for: constraint.first, sketch: sketch, document: document),
                    second: endpointSample(for: constraint.second, sketch: sketch, document: document),
                    constraintKind: "tangentSplineEndpoints",
                    requiredContinuity: .g1,
                    into: &pendingByPair
                )
            case let .smoothSplineEndpoints(constraint):
                try mergeEndpointJoin(
                    first: endpointSample(for: constraint.first, sketch: sketch, document: document),
                    second: endpointSample(for: constraint.second, sketch: sketch, document: document),
                    constraintKind: "smoothSplineEndpoints",
                    requiredContinuity: .g2,
                    into: &pendingByPair
                )
            case .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .fixed:
                continue
            }
        }
        for source in document.productMetadata.joinedCurveGroupSources.values where source.featureID == featureID {
            try mergeEndpointJoin(
                first: endpointSample(for: source.firstJoinedReference, sketch: sketch, document: document),
                second: endpointSample(for: source.secondJoinedReference, sketch: sketch, document: document),
                constraintKind: "joinedCurveGroup",
                requiredContinuity: curveAnalysisContinuityLevel(source.continuity),
                into: &pendingByPair
            )
        }

        return pendingByPair.values
            .sorted {
                if $0.first.referenceDescription == $1.first.referenceDescription {
                    return $0.second.referenceDescription < $1.second.referenceDescription
                }
                return $0.first.referenceDescription < $1.first.referenceDescription
            }
            .map { pending in
                endpointContinuityJoin(
                    featureID: featureID,
                    pending: pending
                )
            }
    }

    private func mergeEndpointJoin(
        first: EndpointSample?,
        second: EndpointSample?,
        constraintKind: String,
        requiredContinuity: CurveAnalysisResult.ContinuityLevel,
        into pendingByPair: inout [EndpointPairKey: PendingEndpointJoin]
    ) throws {
        guard let first, let second else {
            return
        }
        let key = EndpointPairKey(first.referenceDescription, second.referenceDescription)
        if var existing = pendingByPair[key] {
            existing.constraintKinds.insert(constraintKind)
            existing.requiredContinuity = maxContinuity(existing.requiredContinuity, requiredContinuity)
            pendingByPair[key] = existing
            return
        }
        pendingByPair[key] = PendingEndpointJoin(
            first: first,
            second: second,
            constraintKinds: [constraintKind],
            requiredContinuity: requiredContinuity
        )
    }

    private func endpointContinuityJoin(
        featureID: FeatureID,
        pending: PendingEndpointJoin
    ) -> CurveAnalysisResult.ContinuityJoin {
        let positionGap = distance(pending.first.sample.point, pending.second.sample.point)
        let tangentAngle = angleBetween(
            pending.first.sample.tangent,
            pending.second.sample.tangent,
            allowsReversedDirection: true
        )
        let curvatureGap = curvatureDifference(
            pending.first.sample.curvature,
            pending.second.sample.curvature,
            allowsReversedDirection: true
        )
        return CurveAnalysisResult.ContinuityJoin(
            sourceFeatureID: featureID.description,
            joinKind: .constrainedEndpoint,
            firstEntityID: pending.first.entityID.description,
            firstReference: pending.first.referenceDescription,
            firstParameter: pending.first.sample.parameter,
            secondEntityID: pending.second.entityID.description,
            secondReference: pending.second.referenceDescription,
            secondParameter: pending.second.sample.parameter,
            constraintKinds: pending.constraintKinds.sorted(),
            requiredContinuity: pending.requiredContinuity,
            continuity: continuityLevel(
                positionGap: positionGap,
                tangentAngle: tangentAngle,
                curvatureGap: curvatureGap
            ),
            positionGap: positionGap,
            tangentAngle: tangentAngle,
            curvatureGap: curvatureGap
        )
    }

    private func endpointSample(
        for reference: SketchReference,
        sketch: Sketch,
        document: DesignDocument
    ) throws -> EndpointSample? {
        switch reference {
        case let .lineStart(entityID):
            guard case .line(let line) = sketch.entities[entityID] else {
                return nil
            }
            let samples = sampler.lineSamples(
                start: try resolvedPoint(line.start, document: document),
                end: try resolvedPoint(line.end, document: document)
            )
            guard let sample = samples.first else {
                return nil
            }
            return EndpointSample(
                entityID: entityID,
                referenceDescription: referenceDescription(reference),
                sample: sample
            )
        case let .lineEnd(entityID):
            guard case .line(let line) = sketch.entities[entityID] else {
                return nil
            }
            let samples = sampler.lineSamples(
                start: try resolvedPoint(line.start, document: document),
                end: try resolvedPoint(line.end, document: document)
            )
            guard let sample = samples.last else {
                return nil
            }
            return EndpointSample(
                entityID: entityID,
                referenceDescription: referenceDescription(reference),
                sample: sample
            )
        case let .arcStart(entityID):
            guard case .arc(let arc) = sketch.entities[entityID] else {
                return nil
            }
            let samples = try arcSamples(for: arc, document: document)
            guard let sample = samples.first else {
                return nil
            }
            return EndpointSample(
                entityID: entityID,
                referenceDescription: referenceDescription(reference),
                sample: sample
            )
        case let .arcEnd(entityID):
            guard case .arc(let arc) = sketch.entities[entityID] else {
                return nil
            }
            let samples = try arcSamples(for: arc, document: document)
            guard let sample = samples.last else {
                return nil
            }
            return EndpointSample(
                entityID: entityID,
                referenceDescription: referenceDescription(reference),
                sample: sample
            )
        case let .splineControlPoint(entityID, index):
            guard case .spline(let spline) = sketch.entities[entityID] else {
                return nil
            }
            let controlPoints = try spline.controlPoints.map { point in
                try resolvedPoint(point, document: document)
            }
            guard controlPoints.count >= 4,
                  (controlPoints.count - 1).isMultiple(of: 3) else {
                return nil
            }
            let segmentCount = (controlPoints.count - 1) / 3
            let sample: CurveEvaluationSample?
            if index == 0 {
                sample = sampler.splineSegmentSample(
                    for: controlPoints,
                    segmentIndex: 0,
                    t: 0.0
                )
            } else if index == controlPoints.count - 1 {
                sample = sampler.splineSegmentSample(
                    for: controlPoints,
                    segmentIndex: segmentCount - 1,
                    t: 1.0
                )
            } else {
                return nil
            }
            guard let sample else {
                return nil
            }
            return EndpointSample(
                entityID: entityID,
                referenceDescription: referenceDescription(reference),
                sample: sample
            )
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return nil
        }
    }

    private func endpointSample(
        for reference: SketchSplineEndpointReference,
        sketch: Sketch,
        document: DesignDocument
    ) throws -> EndpointSample? {
        guard case .spline(let spline) = sketch.entities[reference.splineID] else {
            return nil
        }
        let controlPointIndex: Int
        switch reference.endpoint {
        case .start:
            controlPointIndex = 0
        case .end:
            controlPointIndex = spline.controlPoints.count - 1
        }
        return try endpointSample(
            for: .splineControlPoint(entity: reference.splineID, index: controlPointIndex),
            sketch: sketch,
            document: document
        )
    }

    private func continuityLevel(
        positionGap: Double,
        tangentAngle: Double,
        curvatureGap: Double
    ) -> CurveAnalysisResult.ContinuityLevel {
        guard positionGap <= positionTolerance else {
            return .disconnected
        }
        guard tangentAngle <= tangentTolerance else {
            return .g0
        }
        guard curvatureGap <= curvatureTolerance else {
            return .g1
        }
        return .g2
    }

    private func sceneNodeIDsByFeatureID(in document: DesignDocument) -> [FeatureID: SceneNodeID] {
        var mapping: [FeatureID: SceneNodeID] = [:]
        for (sceneNodeID, sceneNode) in document.productMetadata.sceneNodes {
            guard sceneNode.reference?.kind == .sketch,
                  let featureID = sceneNode.reference?.featureID else {
                continue
            }
            mapping[featureID] = sceneNodeID
        }
        return mapping
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        document: DesignDocument
    ) throws -> CADCore.Point2D {
        CADCore.Point2D(
            x: try resolvedValue(point.x, kind: .length, document: document),
            y: try resolvedValue(point.y, kind: .length, document: document)
        )
    }

    private func resolvedValue(
        _ expression: CADExpression,
        kind: QuantityKind,
        document: DesignDocument
    ) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == kind else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Curve analysis expected \(kind.rawValue) but found \(quantity.kind.rawValue)."
            )
        }
        return quantity.value
    }

    private func arcSamples(
        for arc: SketchArc,
        document: DesignDocument
    ) throws -> [CurveEvaluationSample] {
        try sampler.arcSamples(
            center: resolvedPoint(arc.center, document: document),
            radius: resolvedValue(arc.radius, kind: .length, document: document),
            startAngle: resolvedValue(arc.startAngle, kind: .angle, document: document),
            endAngle: resolvedValue(arc.endAngle, kind: .angle, document: document)
        )
    }

    private func referenceDescription(_ reference: SketchReference) -> String {
        switch reference {
        case let .entity(entityID):
            return "entity:\(entityID.description)"
        case let .lineStart(entityID):
            return "lineStart:\(entityID.description)"
        case let .lineEnd(entityID):
            return "lineEnd:\(entityID.description)"
        case let .circleCenter(entityID):
            return "circleCenter:\(entityID.description)"
        case let .circleRadius(entityID):
            return "circleRadius:\(entityID.description)"
        case let .arcCenter(entityID):
            return "arcCenter:\(entityID.description)"
        case let .arcStart(entityID):
            return "arcStart:\(entityID.description)"
        case let .arcEnd(entityID):
            return "arcEnd:\(entityID.description)"
        case let .arcRadius(entityID):
            return "arcRadius:\(entityID.description)"
        case let .splineControlPoint(entityID, index):
            return "splineControlPoint:\(entityID.description):\(index)"
        }
    }

    private func curveAnalysisContinuityLevel(
        _ continuity: SketchCurveJoinContinuity
    ) -> CurveAnalysisResult.ContinuityLevel {
        switch continuity {
        case .g0:
            return .g0
        case .g1:
            return .g1
        case .g2:
            return .g2
        }
    }

    private func maxContinuity(
        _ lhs: CurveAnalysisResult.ContinuityLevel,
        _ rhs: CurveAnalysisResult.ContinuityLevel
    ) -> CurveAnalysisResult.ContinuityLevel {
        continuityRank(lhs) >= continuityRank(rhs) ? lhs : rhs
    }

    private func continuityRank(_ level: CurveAnalysisResult.ContinuityLevel) -> Int {
        switch level {
        case .disconnected:
            return 0
        case .g0:
            return 1
        case .g1:
            return 2
        case .g2:
            return 3
        }
    }

    private func distance(_ lhs: CADCore.Point2D, _ rhs: CADCore.Point2D) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func angleBetween(
        _ lhs: CADCore.Point2D,
        _ rhs: CADCore.Point2D,
        allowsReversedDirection: Bool = false
    ) -> Double {
        let dot = min(max(lhs.x * rhs.x + lhs.y * rhs.y, -1.0), 1.0)
        let angle = acos(dot)
        guard allowsReversedDirection else {
            return angle
        }
        return min(angle, abs(Double.pi - angle))
    }

    private func curvatureDifference(
        _ lhs: Double,
        _ rhs: Double,
        allowsReversedDirection: Bool
    ) -> Double {
        if allowsReversedDirection {
            return abs(abs(lhs) - abs(rhs))
        }
        return abs(lhs - rhs)
    }
}
