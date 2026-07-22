import Foundation
import RupaCore

struct WorkspaceSketchEntityInspectorStateBuilder {
    var document: DesignDocument
    var selection: SelectionModel
    var displayUnit: LengthDisplayUnit
    var objectRegistry: ObjectTypeRegistry
    var curveCurvatureDisplays: [SelectionComponentID: CurveCurvatureDisplay] = [:]

    func selectedEntityResult() -> Result<InspectorSketchEntity?, Error> {
        do {
            return .success(try selectedEntity())
        } catch {
            return .failure(error)
        }
    }

    func selectedEntity() throws -> InspectorSketchEntity? {
        guard let target = selection.primaryTarget,
              case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityBaseReference else {
            return nil
        }
        guard let sceneNode = document.productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              sceneNode.reference?.featureID == reference.featureID,
              let feature = document.cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation,
              let entity = sketch.entities[reference.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selected source curve could not be resolved."
            )
        }
        let analysis = try curveAnalysis(
            featureID: reference.featureID,
            entityID: reference.entityID
        )
        let joinedCurveSourceID = document.productMetadata.joinedCurveSources.values.first { source in
            source.featureID == reference.featureID && source.retainedEntityID == reference.entityID
        }?.id
        let joinedCurveGroupSource = document.productMetadata.joinedCurveGroupSources.values.first { source in
            source.featureID == reference.featureID && source.memberEntityIDs.contains(reference.entityID)
        }

        switch entity {
        case .point(let point):
            return InspectorSketchEntity(
                target: target,
                sourceFeatureID: reference.featureID,
                entityID: reference.entityID,
                sourceFeatureName: feature.name,
                entityKind: "point",
                analysis: analysis,
                center: try resolvedPoint(point)
            )
        case .line(let line):
            return InspectorSketchEntity(
                target: target,
                sourceFeatureID: reference.featureID,
                entityID: reference.entityID,
                sourceFeatureName: feature.name,
                entityKind: "line",
                analysis: analysis,
                joinedCurveSourceID: joinedCurveSourceID,
                joinedCurveGroupSourceID: joinedCurveGroupSource?.id,
                joinedCurveGroupContinuity: joinedCurveGroupSource?.continuity,
                start: try resolvedPoint(line.start),
                end: try resolvedPoint(line.end)
            )
        case .circle(let circle):
            return InspectorSketchEntity(
                target: target,
                sourceFeatureID: reference.featureID,
                entityID: reference.entityID,
                sourceFeatureName: feature.name,
                entityKind: "circle",
                analysis: analysis,
                center: try resolvedPoint(circle.center),
                radius: try resolvedValue(circle.radius, kind: .length)
            )
        case .arc(let arc):
            let center = try resolvedPoint(arc.center)
            let radius = try resolvedValue(arc.radius, kind: .length)
            let startAngle = try resolvedValue(arc.startAngle, kind: .angle)
            let endAngle = try resolvedValue(arc.endAngle, kind: .angle)
            return InspectorSketchEntity(
                target: target,
                sourceFeatureID: reference.featureID,
                entityID: reference.entityID,
                sourceFeatureName: feature.name,
                entityKind: "arc",
                analysis: analysis,
                joinedCurveGroupSourceID: joinedCurveGroupSource?.id,
                joinedCurveGroupContinuity: joinedCurveGroupSource?.continuity,
                start: pointOnCircle(center: center, radius: radius, angle: startAngle),
                end: pointOnCircle(center: center, radius: radius, angle: endAngle),
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle
            )
        case .spline(let spline):
            let controlPoints = try spline.controlPoints.map { point in
                try resolvedPoint(point)
            }
            let smoothIndexes = Set(
                sketch.constraints.compactMap { constraint -> Int? in
                    guard case let .smoothSplineControlPoint(entityID, index) = constraint,
                          entityID == reference.entityID else {
                        return nil
                    }
                    return index
                }
            )
            return InspectorSketchEntity(
                target: target,
                sourceFeatureID: reference.featureID,
                entityID: reference.entityID,
                sourceFeatureName: feature.name,
                entityKind: "spline",
                analysis: analysis,
                bridgeCurve: try bridgeCurve(
                    featureID: reference.featureID,
                    entityID: reference.entityID,
                    target: target
                ),
                start: controlPoints.first,
                end: controlPoints.last,
                controlPoints: controlPoints,
                smoothSplineControlPointIndexes: smoothIndexes,
                tangentLineCandidates: try lineCandidates(in: sketch, excluding: reference.entityID),
                tangentSplineEndpointCandidates: try splineEndpointCandidates(in: sketch, excluding: reference.entityID),
                startTangentLineIDs: splineEndpointTangentLineIDs(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .start
                ),
                endTangentLineIDs: splineEndpointTangentLineIDs(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .end
                ),
                startTangentSplineEndpoints: tangentSplineEndpointReferences(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .start
                ),
                endTangentSplineEndpoints: tangentSplineEndpointReferences(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .end
                ),
                startSmoothSplineEndpoints: smoothSplineEndpointReferences(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .start
                ),
                endSmoothSplineEndpoints: smoothSplineEndpointReferences(
                    in: sketch,
                    splineID: reference.entityID,
                    endpoint: .end
                )
            )
        }
    }

    func entityKind(for target: SelectionTarget) -> String? {
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityReference,
              let sceneNode = document.productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              sceneNode.reference?.featureID == reference.featureID,
              let feature = document.cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation,
              let entity = sketch.entities[reference.entityID] else {
            return nil
        }
        switch entity {
        case .point:
            return "point"
        case .line:
            return "line"
        case .circle:
            return "circle"
        case .arc:
            return "arc"
        case .spline:
            return "spline"
        }
    }

    func joinState(for entity: InspectorSketchEntity) -> SketchCurveJoinInspectorState {
        var entityKindsByTarget: [SelectionTarget: String] = [:]
        for target in selection.selectedTargets {
            entityKindsByTarget[target] = entityKind(for: target)
        }
        return SketchCurveJoinInspectorState(
            entityKind: entity.entityKind,
            sourceFeatureID: entity.sourceFeatureID,
            entityID: entity.entityID,
            target: entity.target,
            joinedCurveSourceID: entity.joinedCurveSourceID,
            joinedCurveGroupSourceID: entity.joinedCurveGroupSourceID,
            selectedTargets: selection.selectedTargets,
            entityKindsByTarget: entityKindsByTarget
        )
    }

    func operationState(for entity: InspectorSketchEntity) -> WorkspaceSketchCurveOperationControlsState {
        let joinState = joinState(for: entity)
        return WorkspaceSketchCurveOperationControlsState(
            canExtend: canExtend(entity),
            canOffsetVertex: vertexOffsetHandle(for: entity) != nil,
            canApplyCornerTreatment: canApplyCornerTreatment(entity),
            canJoin: joinState.canJoin,
            canUnjoin: joinState.canUnjoin,
            canAlignVertex: vertexAlignmentReferenceTarget(for: entity) != nil,
            canProject: curveProjectionTargets(for: entity).isEmpty == false
        )
    }

    func cutterTarget(excluding target: SelectionTarget) -> SelectionTarget? {
        selection.selectedTargets.first { candidate in
            guard candidate != target,
                  case .sketchEntity = candidate.component,
                  let kind = entityKind(for: candidate),
                  ["line", "circle", "arc"].contains(kind) else {
                return false
            }
            return true
        }
    }

    func cornerTreatmentAdjacentTarget(excluding target: SelectionTarget) -> SelectionTarget? {
        selection.selectedTargets.first { candidate in
            guard candidate != target,
                  case .sketchEntity = candidate.component,
                  let kind = entityKind(for: candidate),
                  ["line", "arc"].contains(kind) else {
                return false
            }
            return true
        }
    }

    func vertexOffsetHandle(for entity: InspectorSketchEntity) -> SketchEntityPointHandle? {
        SketchVertexOffsetInspectorState(
            entityKind: entity.entityKind,
            entityID: entity.entityID,
            target: entity.target
        )
        .handle
    }

    func vertexAlignmentReferenceTarget(for entity: InspectorSketchEntity) -> SelectionTarget? {
        guard isVertexAlignmentTarget(entity.target, entityKind: entity.entityKind) else {
            return nil
        }
        let referenceTargets = selection.selectedTargets.filter { target in
            guard target != entity.target,
                  let entityKind = baseEntityKind(for: target) else {
                return false
            }
            return isVertexAlignmentTarget(target, entityKind: entityKind)
        }
        guard referenceTargets.count == 1 else {
            return nil
        }
        return referenceTargets.first
    }

    func curveProjectionTargets(for entity: InspectorSketchEntity) -> [SelectionTarget] {
        var projectedTargets: [SelectionTarget] = []
        var seen = Set<String>()
        for target in selection.selectedTargets {
            guard let curveTarget = wholeCurveTarget(for: target) else {
                continue
            }
            let key = "\(curveTarget.sceneNodeID.description):\(String(describing: curveTarget.component))"
            if seen.insert(key).inserted {
                projectedTargets.append(curveTarget)
            }
        }
        if projectedTargets.isEmpty,
           let fallback = wholeCurveTarget(for: entity.target) {
            projectedTargets.append(fallback)
        }
        return projectedTargets
    }

    func wholeCurveTarget(for target: SelectionTarget) -> SelectionTarget? {
        guard case .sketchEntity(let componentID) = target.component,
              let reference = sketchEntityReference(in: componentID) else {
            return nil
        }
        let curveTarget = SelectionTarget(
            sceneNodeID: target.sceneNodeID,
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(
                    featureID: reference.featureID,
                    entityID: reference.entityID
                )
            )
        )
        guard let kind = entityKind(for: curveTarget),
              ["line", "circle", "arc", "spline"].contains(kind) else {
            return nil
        }
        return curveTarget
    }

    private func canExtend(_ entity: InspectorSketchEntity) -> Bool {
        guard case .sketchEntity(let componentID) = entity.target.component else {
            return false
        }
        if let reference = componentID.sketchPointHandleReference {
            guard reference.entityID == entity.entityID else {
                return false
            }
            switch (entity.entityKind, reference.handle) {
            case ("line", .lineStart),
                 ("line", .lineEnd),
                 ("arc", .arcStart),
                 ("arc", .arcEnd):
                return true
            default:
                return false
            }
        }
        if let reference = componentID.sketchControlPointReference {
            guard entity.entityKind == "spline",
                  reference.entityID == entity.entityID else {
                return false
            }
            return reference.index == 0 || reference.index == entity.controlPoints.count - 1
        }
        return false
    }

    private func canApplyCornerTreatment(_ entity: InspectorSketchEntity) -> Bool {
        guard case .sketchEntity(let componentID) = entity.target.component,
              entity.entityKind == "line" || entity.entityKind == "arc" else {
            return false
        }
        if let reference = componentID.sketchPointHandleReference,
           reference.entityID == entity.entityID {
            switch reference.handle {
            case .lineStart,
                 .lineEnd:
                return entity.entityKind == "line"
            case .arcStart,
                 .arcEnd:
                return entity.entityKind == "arc"
            case .point,
                 .circleCenter,
                 .arcCenter:
                return false
            }
        }
        guard componentID.sketchEntityReference?.entityID == entity.entityID else {
            return false
        }
        return cornerTreatmentAdjacentTarget(excluding: entity.target) != nil
    }

    private func isVertexAlignmentTarget(
        _ target: SelectionTarget,
        entityKind: String
    ) -> Bool {
        guard case .sketchEntity(let componentID) = target.component else {
            return false
        }
        if let reference = componentID.sketchPointHandleReference {
            switch (entityKind, reference.handle) {
            case ("point", .point),
                 ("line", .lineStart),
                 ("line", .lineEnd),
                 ("arc", .arcStart),
                 ("arc", .arcEnd):
                return true
            default:
                return false
            }
        }
        if let reference = componentID.sketchControlPointReference,
           entityKind == "spline",
           let controlPointCount = splineControlPointCount(for: target) {
            return reference.index == 0 || reference.index == controlPointCount - 1
        }
        return false
    }

    private func baseEntityKind(for target: SelectionTarget) -> String? {
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityBaseReference,
              let sceneNode = document.productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              sceneNode.reference?.featureID == reference.featureID,
              let feature = document.cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation,
              let entity = sketch.entities[reference.entityID] else {
            return nil
        }
        switch entity {
        case .point:
            return "point"
        case .line:
            return "line"
        case .circle:
            return "circle"
        case .arc:
            return "arc"
        case .spline:
            return "spline"
        }
    }

    private func splineControlPointCount(for target: SelectionTarget) -> Int? {
        guard case .sketchEntity(let componentID) = target.component,
              let reference = sketchEntityReference(in: componentID),
              let sceneNode = document.productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              sceneNode.reference?.featureID == reference.featureID,
              let feature = document.cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation,
              case .spline(let spline) = sketch.entities[reference.entityID] else {
            return nil
        }
        return spline.controlPoints.count
    }

    private func sketchEntityReference(
        in componentID: SelectionComponentID
    ) -> (featureID: FeatureID, entityID: SketchEntityID)? {
        if let reference = componentID.sketchEntityReference {
            return reference
        }
        if let reference = componentID.sketchPointHandleReference {
            return (reference.featureID, reference.entityID)
        }
        if let reference = componentID.sketchControlPointReference {
            return (reference.featureID, reference.entityID)
        }
        return nil
    }

    private func bridgeCurve(
        featureID: FeatureID,
        entityID: SketchEntityID,
        target: SelectionTarget
    ) throws -> InspectorBridgeCurve? {
        guard let source = document.productMetadata.bridgeCurveSources.values.first(where: {
            $0.featureID == featureID && $0.entityID == entityID
        }) else {
            return nil
        }
        return InspectorBridgeCurve(
            sourceID: source.id,
            target: SelectionTarget(
                sceneNodeID: target.sceneNodeID,
                component: .sketchEntity(
                    SelectionComponentID.sketchEntity(
                        featureID: source.featureID,
                        entityID: source.entityID
                    )
                )
            ),
            firstEndpoint: source.firstEndpoint,
            secondEndpoint: source.secondEndpoint,
            continuity: source.continuity,
            trimsSourceCurves: source.trimsSourceCurves,
            curvatureDisplay: curveCurvatureDisplays[
                .sketchEntity(featureID: source.featureID, entityID: source.entityID)
            ],
            firstParameter: try bridgeCurveParameter(source.firstEndpoint),
            secondParameter: try bridgeCurveParameter(source.secondEndpoint),
            firstTension: try bridgeCurveTension(source.firstEndpoint.tension),
            secondTension: try bridgeCurveTension(source.secondEndpoint.tension)
        )
    }

    private func bridgeCurveParameter(_ endpoint: BridgeCurveEndpoint) throws -> Double {
        if let parameter = endpoint.parameter {
            return try resolvedValue(parameter, kind: .scalar)
        }
        switch endpoint.reference {
        case .lineStart,
             .arcStart:
            return 0.0
        case .lineEnd,
             .arcEnd:
            return 1.0
        case .splineControlPoint(_, let index):
            return index == 0 ? 0.0 : 1.0
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return 0.0
        }
    }

    private func bridgeCurveTension(_ tension: BridgeCurveTension) throws -> InspectorBridgeCurveTension {
        InspectorBridgeCurveTension(
            first: try resolvedValue(tension.first, kind: .scalar),
            second: try resolvedValue(tension.second, kind: .scalar),
            third: try resolvedValue(tension.third, kind: .scalar)
        )
    }

    private func curveAnalysis(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) throws -> InspectorCurveAnalysis? {
        let result = try CurveAnalysisService(samplesPerSegment: 16).analyze(
            document: document,
            featureID: featureID,
            entityID: entityID,
            displayUnit: displayUnit,
            objectRegistry: objectRegistry
        )
        guard let curve = result.curves.first else {
            return nil
        }
        return InspectorCurveAnalysis(
            sampleCount: curve.samples.count,
            approximateLength: curve.approximateLength,
            maxAbsCurvature: curve.maxAbsCurvature,
            continuityJoins: result.continuityJoins.enumerated().map { index, join in
                InspectorCurveContinuityJoin(
                    id: "\(join.sourceFeatureID):\(join.firstReference):\(join.secondReference):\(index)",
                    joinKind: join.joinKind,
                    requiredContinuity: join.requiredContinuity,
                    actualContinuity: join.continuity,
                    positionGap: join.positionGap,
                    tangentAngle: join.tangentAngle,
                    curvatureGap: join.curvatureGap,
                    constraintKinds: join.constraintKinds,
                    firstReference: join.firstReference,
                    secondReference: join.secondReference
                )
            }
        )
    }

    private func lineCandidates(
        in sketch: Sketch,
        excluding entityID: SketchEntityID
    ) throws -> [InspectorSketchLineCandidate] {
        try sketch.entities.compactMap { candidateID, entity -> InspectorSketchLineCandidate? in
            guard candidateID != entityID,
                  case let .line(line) = entity else {
                return nil
            }
            return InspectorSketchLineCandidate(
                id: candidateID,
                start: try resolvedPoint(line.start),
                end: try resolvedPoint(line.end)
            )
        }
        .sorted { lhs, rhs in
            lhs.id.description.localizedStandardCompare(rhs.id.description) == .orderedAscending
        }
    }

    private func splineEndpointCandidates(
        in sketch: Sketch,
        excluding entityID: SketchEntityID
    ) throws -> [InspectorSplineEndpointCandidate] {
        try sketch.entities.flatMap { candidateID, entity -> [InspectorSplineEndpointCandidate] in
            guard candidateID != entityID,
                  case let .spline(spline) = entity,
                  spline.controlPoints.count >= 4,
                  let start = spline.controlPoints.first,
                  let end = spline.controlPoints.last else {
                return []
            }
            let resolvedStart = try resolvedPoint(start)
            let resolvedStartHandle = try resolvedPoint(spline.controlPoints[1])
            let resolvedEnd = try resolvedPoint(end)
            let resolvedEndHandle = try resolvedPoint(
                spline.controlPoints[spline.controlPoints.count - 2]
            )
            return [
                InspectorSplineEndpointCandidate(
                    splineID: candidateID,
                    endpoint: .start,
                    point: resolvedStart,
                    tangent: SketchEntitySummaryResult.Point(
                        x: resolvedStartHandle.x - resolvedStart.x,
                        y: resolvedStartHandle.y - resolvedStart.y
                    )
                ),
                InspectorSplineEndpointCandidate(
                    splineID: candidateID,
                    endpoint: .end,
                    point: resolvedEnd,
                    tangent: SketchEntitySummaryResult.Point(
                        x: resolvedEnd.x - resolvedEndHandle.x,
                        y: resolvedEnd.y - resolvedEndHandle.y
                    )
                ),
            ]
        }
        .sorted { lhs, rhs in
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private func splineEndpointTangentLineIDs(
        in sketch: Sketch,
        splineID: SketchEntityID,
        endpoint: SketchSplineEndpoint
    ) -> Set<SketchEntityID> {
        Set(sketch.constraints.compactMap { constraint -> SketchEntityID? in
            guard case let .splineEndpointTangent(tangency) = constraint,
                  tangency.splineEndpoint.splineID == splineID,
                  tangency.splineEndpoint.endpoint == endpoint else {
                return nil
            }
            return tangency.line
        })
    }

    private func tangentSplineEndpointReferences(
        in sketch: Sketch,
        splineID: SketchEntityID,
        endpoint: SketchSplineEndpoint
    ) -> Set<SketchSplineEndpointReference> {
        let selectedEndpoint = SketchSplineEndpointReference(splineID: splineID, endpoint: endpoint)
        return Set(sketch.constraints.compactMap { constraint -> SketchSplineEndpointReference? in
            guard case let .tangentSplineEndpoints(tangency) = constraint else {
                return nil
            }
            if tangency.first == selectedEndpoint {
                return tangency.second
            }
            if tangency.second == selectedEndpoint {
                return tangency.first
            }
            return nil
        })
    }

    private func smoothSplineEndpointReferences(
        in sketch: Sketch,
        splineID: SketchEntityID,
        endpoint: SketchSplineEndpoint
    ) -> Set<SketchSplineEndpointReference> {
        let selectedEndpoint = SketchSplineEndpointReference(splineID: splineID, endpoint: endpoint)
        return Set(sketch.constraints.compactMap { constraint -> SketchSplineEndpointReference? in
            guard case let .smoothSplineEndpoints(tangency) = constraint else {
                return nil
            }
            if tangency.first == selectedEndpoint {
                return tangency.second
            }
            if tangency.second == selectedEndpoint {
                return tangency.first
            }
            return nil
        })
    }

    private func resolvedPoint(_ point: SketchPoint) throws -> SketchEntitySummaryResult.Point {
        SketchEntitySummaryResult.Point(
            x: try resolvedValue(point.x, kind: .length),
            y: try resolvedValue(point.y, kind: .length)
        )
    }

    private func resolvedValue(
        _ expression: CADExpression,
        kind: QuantityKind
    ) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == kind else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Selected source curve expected \(kind.rawValue) but found \(quantity.kind.rawValue)."
            )
        }
        return quantity.value
    }

    private func pointOnCircle(
        center: SketchEntitySummaryResult.Point,
        radius: Double,
        angle: Double
    ) -> SketchEntitySummaryResult.Point {
        SketchEntitySummaryResult.Point(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}
