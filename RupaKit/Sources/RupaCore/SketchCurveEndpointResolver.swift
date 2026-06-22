import Foundation
import SwiftCAD

struct SketchCurveEndpointResolver: Sendable {
    private let evaluator: SketchCurveEvaluator

    init(evaluator: SketchCurveEvaluator = SketchCurveEvaluator()) {
        self.evaluator = evaluator
    }

    func sample(
        for endpoint: BridgeCurveEndpoint,
        sketch: Sketch,
        document: DesignDocument
    ) throws -> SketchCurveEndpointSample? {
        guard let parameterExpression = endpoint.parameter else {
            guard var sample = try sample(
                for: endpoint.reference,
                sketch: sketch,
                document: document
            ) else {
                return nil
            }
            if endpoint.reversesSense {
                sample.outgoingTangent = reversed(sample.outgoingTangent)
            }
            return sample
        }

        let parameter = try resolvedParameter(
            parameterExpression,
            document: document,
            owner: "Bridge curve endpoint parameter"
        )
        guard let entityID = entityID(forParametricReference: endpoint.reference),
              let entity = sketch.entities[entityID] else {
            return nil
        }
        let pointReference = endpointPointReference(
            entityID: entityID,
            entity: entity,
            parameter: parameter
        )
        let sample: CurveEvaluationSample?
        let kind: SketchCurveEndpointSample.EndpointKind
        switch entity {
        case .line(let line):
            sample = try lineSample(
                for: line,
                parameter: parameter,
                document: document
            )
            kind = .line(entityID)
        case .arc(let arc):
            sample = try arcSample(
                for: arc,
                parameter: parameter,
                document: document
            )
            kind = .arc(entityID)
        case .spline(let spline):
            sample = try splineSample(
                for: spline,
                parameter: parameter,
                document: document
            )
            kind = .spline(splineEndpointReference(entityID: entityID, parameter: parameter))
        case .point,
             .circle:
            return nil
        }
        guard let sample else {
            return nil
        }
        let outgoingTangent = endpoint.reversesSense
            ? reversed(sample.tangent)
            : sample.tangent
        return SketchCurveEndpointSample(
            entityID: entityID,
            kind: kind,
            referenceDescription: endpointDescription(endpoint, resolvedParameter: parameter),
            reference: endpoint.reference,
            pointReference: pointReference,
            sample: sample,
            outgoingTangent: outgoingTangent
        )
    }

    func sample(
        for reference: SketchReference,
        sketch: Sketch,
        document: DesignDocument
    ) throws -> SketchCurveEndpointSample? {
        switch reference {
        case let .lineStart(entityID):
            guard case .line(let line) = sketch.entities[entityID] else {
                return nil
            }
            let samples = evaluator.lineSamples(
                start: try resolvedPoint(line.start, document: document),
                end: try resolvedPoint(line.end, document: document)
            )
            guard let sample = samples.first else {
                return nil
            }
            return SketchCurveEndpointSample(
                entityID: entityID,
                kind: .line(entityID),
                referenceDescription: referenceDescription(reference),
                reference: reference,
                pointReference: reference,
                sample: sample,
                outgoingTangent: reversed(sample.tangent)
            )
        case let .lineEnd(entityID):
            guard case .line(let line) = sketch.entities[entityID] else {
                return nil
            }
            let samples = evaluator.lineSamples(
                start: try resolvedPoint(line.start, document: document),
                end: try resolvedPoint(line.end, document: document)
            )
            guard let sample = samples.last else {
                return nil
            }
            return SketchCurveEndpointSample(
                entityID: entityID,
                kind: .line(entityID),
                referenceDescription: referenceDescription(reference),
                reference: reference,
                pointReference: reference,
                sample: sample,
                outgoingTangent: sample.tangent
            )
        case let .arcStart(entityID):
            guard case .arc(let arc) = sketch.entities[entityID] else {
                return nil
            }
            let samples = try arcSamples(for: arc, document: document)
            guard let sample = samples.first else {
                return nil
            }
            return SketchCurveEndpointSample(
                entityID: entityID,
                kind: .arc(entityID),
                referenceDescription: referenceDescription(reference),
                reference: reference,
                pointReference: reference,
                sample: sample,
                outgoingTangent: reversed(sample.tangent)
            )
        case let .arcEnd(entityID):
            guard case .arc(let arc) = sketch.entities[entityID] else {
                return nil
            }
            let samples = try arcSamples(for: arc, document: document)
            guard let sample = samples.last else {
                return nil
            }
            return SketchCurveEndpointSample(
                entityID: entityID,
                kind: .arc(entityID),
                referenceDescription: referenceDescription(reference),
                reference: reference,
                pointReference: reference,
                sample: sample,
                outgoingTangent: sample.tangent
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
            if index == 0 {
                guard let sample = evaluator.splineSegmentSample(
                    for: controlPoints,
                    segmentIndex: 0,
                    t: 0.0
                ) else {
                    return nil
                }
                return SketchCurveEndpointSample(
                    entityID: entityID,
                    kind: .spline(SketchSplineEndpointReference(splineID: entityID, endpoint: .start)),
                    referenceDescription: referenceDescription(reference),
                    reference: reference,
                    pointReference: reference,
                    sample: sample,
                    outgoingTangent: reversed(sample.tangent)
                )
            }
            if index == controlPoints.count - 1 {
                guard let sample = evaluator.splineSegmentSample(
                    for: controlPoints,
                    segmentIndex: segmentCount - 1,
                    t: 1.0
                ) else {
                    return nil
                }
                return SketchCurveEndpointSample(
                    entityID: entityID,
                    kind: .spline(SketchSplineEndpointReference(splineID: entityID, endpoint: .end)),
                    referenceDescription: referenceDescription(reference),
                    reference: reference,
                    pointReference: reference,
                    sample: sample,
                    outgoingTangent: sample.tangent
                )
            }
            return nil
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return nil
        }
    }

    func sample(
        for reference: SketchSplineEndpointReference,
        sketch: Sketch,
        document: DesignDocument
    ) throws -> SketchCurveEndpointSample? {
        guard case .spline(let spline) = sketch.entities[reference.splineID] else {
            return nil
        }
        let index: Int
        switch reference.endpoint {
        case .start:
            index = 0
        case .end:
            index = spline.controlPoints.count - 1
        }
        return try sample(
            for: .splineControlPoint(entity: reference.splineID, index: index),
            sketch: sketch,
            document: document
        )
    }

    func referenceDescription(_ reference: SketchReference) -> String {
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

    func endpointDescription(
        _ endpoint: BridgeCurveEndpoint,
        resolvedParameter: Double? = nil
    ) -> String {
        var description = referenceDescription(endpoint.reference)
        let parameterValue = resolvedParameter
            ?? endpoint.parameter.flatMap { expression in
                if case .constant(let quantity) = expression,
                   quantity.kind == .scalar {
                    return quantity.value
                }
                return nil
            }
        if let parameterValue {
            description += ":parameter:\(parameterValue)"
        }
        if endpoint.reversesSense {
            description += ":reversed"
        }
        return description
    }

    private func arcSamples(
        for arc: SketchArc,
        document: DesignDocument
    ) throws -> [CurveEvaluationSample] {
        try evaluator.arcSamples(
            center: resolvedPoint(arc.center, document: document),
            radius: resolvedValue(arc.radius, kind: .length, document: document),
            startAngle: resolvedValue(arc.startAngle, kind: .angle, document: document),
            endAngle: resolvedValue(arc.endAngle, kind: .angle, document: document)
        )
    }

    private func lineSample(
        for line: SketchLine,
        parameter: Double,
        document: DesignDocument
    ) throws -> CurveEvaluationSample? {
        let start = try resolvedPoint(line.start, document: document)
        let end = try resolvedPoint(line.end, document: document)
        let samples = evaluator.lineSamples(start: start, end: end)
        guard let first = samples.first else {
            return nil
        }
        return CurveEvaluationSample(
            parameter: parameter,
            point: CADCore.Point2D(
                x: start.x + (end.x - start.x) * parameter,
                y: start.y + (end.y - start.y) * parameter
            ),
            tangent: first.tangent,
            normal: first.normal,
            curvature: first.curvature
        )
    }

    private func arcSample(
        for arc: SketchArc,
        parameter: Double,
        document: DesignDocument
    ) throws -> CurveEvaluationSample? {
        let center = try resolvedPoint(arc.center, document: document)
        let radius = try resolvedValue(arc.radius, kind: .length, document: document)
        let startAngle = try resolvedValue(arc.startAngle, kind: .angle, document: document)
        let endAngle = try resolvedValue(arc.endAngle, kind: .angle, document: document)
        guard radius > 1.0e-12 else {
            return nil
        }
        let span = positiveAngleSpan(startAngle: startAngle, endAngle: endAngle)
        let angle = startAngle + span * parameter
        let cosine = cos(angle)
        let sine = sin(angle)
        let tangent = CADCore.Point2D(x: -sine, y: cosine)
        return CurveEvaluationSample(
            parameter: parameter,
            point: CADCore.Point2D(
                x: center.x + cosine * radius,
                y: center.y + sine * radius
            ),
            tangent: tangent,
            normal: CADCore.Point2D(x: -cosine, y: -sine),
            curvature: 1.0 / radius
        )
    }

    private func splineSample(
        for spline: SketchSpline,
        parameter: Double,
        document: DesignDocument
    ) throws -> CurveEvaluationSample? {
        let controlPoints = try spline.controlPoints.map { point in
            try resolvedPoint(point, document: document)
        }
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            return nil
        }
        let segmentCount = (controlPoints.count - 1) / 3
        let scaled = min(max(parameter, 0.0), 1.0) * Double(segmentCount)
        let segmentIndex = min(Int(floor(scaled)), segmentCount - 1)
        let localT = segmentIndex == segmentCount - 1 && parameter >= 1.0
            ? 1.0
            : scaled - Double(segmentIndex)
        return evaluator.splineSegmentSample(
            for: controlPoints,
            segmentIndex: segmentIndex,
            t: localT
        )
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
                message: "Sketch curve endpoint expected \(kind.rawValue) but found \(quantity.kind.rawValue)."
            )
        }
        return quantity.value
    }

    private func resolvedParameter(
        _ expression: CADExpression,
        document: DesignDocument,
        owner: String
    ) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .scalar,
              quantity.value.isFinite,
              quantity.value >= 0.0,
              quantity.value <= 1.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite scalar from 0 through 1."
            )
        }
        return quantity.value
    }

    private func entityID(forParametricReference reference: SketchReference) -> SketchEntityID? {
        switch reference {
        case let .entity(entityID),
             let .lineStart(entityID),
             let .lineEnd(entityID),
             let .arcStart(entityID),
             let .arcEnd(entityID),
             let .splineControlPoint(entityID, _):
            return entityID
        case .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return nil
        }
    }

    private func endpointPointReference(
        entityID: SketchEntityID,
        entity: SketchEntity,
        parameter: Double
    ) -> SketchReference? {
        let tolerance = 1.0e-12
        switch entity {
        case .line:
            if parameter <= tolerance {
                return .lineStart(entityID)
            }
            if parameter >= 1.0 - tolerance {
                return .lineEnd(entityID)
            }
        case .arc:
            if parameter <= tolerance {
                return .arcStart(entityID)
            }
            if parameter >= 1.0 - tolerance {
                return .arcEnd(entityID)
            }
        case .spline(let spline):
            if parameter <= tolerance {
                return .splineControlPoint(entity: entityID, index: 0)
            }
            if parameter >= 1.0 - tolerance {
                return .splineControlPoint(entity: entityID, index: spline.controlPoints.count - 1)
            }
        case .point,
             .circle:
            return nil
        }
        return nil
    }

    private func splineEndpointReference(
        entityID: SketchEntityID,
        parameter: Double
    ) -> SketchSplineEndpointReference? {
        let tolerance = 1.0e-12
        if parameter <= tolerance {
            return SketchSplineEndpointReference(splineID: entityID, endpoint: .start)
        }
        if parameter >= 1.0 - tolerance {
            return SketchSplineEndpointReference(splineID: entityID, endpoint: .end)
        }
        return nil
    }

    private func positiveAngleSpan(startAngle: Double, endAngle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        let tolerance = 1.0e-12
        var span = endAngle - startAngle
        while span <= tolerance {
            span += fullCircle
        }
        while span > fullCircle + tolerance {
            span -= fullCircle
        }
        return min(span, fullCircle)
    }

    private func reversed(_ vector: CADCore.Point2D) -> CADCore.Point2D {
        CADCore.Point2D(x: -vector.x, y: -vector.y)
    }
}
