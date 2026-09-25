import Foundation
import SwiftCAD
import RupaCoreTypes

public struct MeasurementService {
    private let pipelineOverride: CADPipeline?
    private let tolerance: ModelingTolerance
    private let splineTessellator: CubicBezierSplineTessellator

    public init(
        pipeline: CADPipeline? = nil,
        tolerance: ModelingTolerance = .standard
    ) {
        self.pipelineOverride = pipeline
        self.tolerance = tolerance
        self.splineTessellator = CubicBezierSplineTessellator(tolerance: tolerance)
    }

    public func measure(
        document: DesignDocument,
        ruler: RulerConfiguration,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> MeasurementResult {
        try measure(
            document: document,
            ruler: ruler,
            selectedSceneNodeIDs: nil,
            scope: .document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
    }

    public func measure(
        document: DesignDocument,
        selection: SelectionModel,
        ruler: RulerConfiguration,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> MeasurementResult {
        guard !selection.selectedSceneNodeIDs.isEmpty else {
            return try measure(
                document: document,
                ruler: ruler,
                objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation,
                currentGeneration: currentGeneration
            )
        }
        return try measure(
            document: document,
            ruler: ruler,
            selectedSceneNodeIDs: Set(selection.selectedSceneNodeIDs),
            scope: .selection,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
    }

    private func measure(
        document: DesignDocument,
        ruler: RulerConfiguration,
        selectedSceneNodeIDs: Set<SceneNodeID>?,
        scope: MeasurementResult.Scope,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) throws -> MeasurementResult {
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        let occurrences = try hierarchy.resolvedOccurrences()
        var selectedNodeClosure: Set<SceneNodeID>?
        if let selectedSceneNodeIDs {
            var closure: Set<SceneNodeID> = []
            for id in selectedSceneNodeIDs {
                guard hierarchy.node(id) != nil else {
                    throw EditorError(code: .referenceUnresolved, message: "Measurement selection contains a missing scene node.")
                }
                closure.formUnion(hierarchy.subtreeIDs(of: id))
            }
            selectedNodeClosure = closure
        }
        let selectedOccurrences = occurrences.filter {
            selectedNodeClosure?.contains($0.sceneNodeID) ?? true
        }
        let selectedFeatureIDs: Set<FeatureID>? = selectedSceneNodeIDs.map { _ in
            Set(selectedOccurrences.compactMap {
                document.productMetadata.sceneNodes[$0.sourceSceneNodeID]?.reference?.featureID
            })
        }
        var counts = MeasurementResult.Counts()
        var profiles: [MeasurementResult.Profile] = []
        var solids: [MeasurementResult.Solid] = []
        var sheets: [MeasurementResult.Sheet] = []
        var bounds = MeasurementBoundsAccumulator()
        var profileCache: [FeatureID: MeasuredProfile] = [:]
        // Source-space points of features that contribute bounds but no measured solid, sheet or
        // profile; the placement projection maps them like every other measured geometry.
        var boundsOnlySources: [(featureID: FeatureID, points: [Point3D])] = []
        // Source-space bounds of measured sketches and curves; placed occurrences re-derive their
        // own bounds, and an unpresented source contributes these in the world frame.
        var sketchCurveSourceBounds: [FeatureID: MeasurementResult.Bounds] = [:]
        var includedProfileFeatureIDs: Set<FeatureID> = []
        var includedSketchFeatureIDs: Set<FeatureID> = []
        var includedSourceFeatureIDs: Set<FeatureID> = []
        var diagnostics: [EditorDiagnostic] = []
        var didAttemptEvaluation = false
        var cachedEvaluatedDocument: EvaluatedDocument?
        let supersededBodyFeatureIDs = bodyFeatureIDsSupersededByDirectEdits(
            in: document.cadDocument
        )

        func shouldMeasure(_ featureID: FeatureID) -> Bool {
            guard let selectedFeatureIDs else {
                return true
            }
            return selectedFeatureIDs.contains(featureID)
        }

        func isSupersededInDocumentScope(_ featureID: FeatureID) -> Bool {
            selectedFeatureIDs == nil && supersededBodyFeatureIDs.contains(featureID)
        }

        func evaluatedDocument() -> EvaluatedDocument? {
            if didAttemptEvaluation {
                return cachedEvaluatedDocument
            }
            didAttemptEvaluation = true
            do {
                cachedEvaluatedDocument = try DocumentEvaluationContextResolver(
                    pipeline: pipelineOverride
                ).evaluatedDocument(
                    document: document,
                    objectRegistry: objectRegistry,
                    currentEvaluation: currentEvaluation,
                    currentGeneration: currentGeneration,
                    failurePrefix: "Measurement could not read evaluated geometry"
                )
            } catch {
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .warning,
                        message: "Measurement could not read evaluated geometry: \(String(describing: error))"
                    )
                )
                cachedEvaluatedDocument = nil
            }
            return cachedEvaluatedDocument
        }

        func includeProfile(
            _ profile: MeasuredProfile,
            featureID: FeatureID
        ) {
            guard includedProfileFeatureIDs.insert(featureID).inserted else {
                return
            }
            profiles.append(profile.result)
            bounds.include(profile.result.bounds)
        }

        func includeSketch(
            featureID: FeatureID,
            sketch: Sketch,
            sketchBounds: MeasurementResult.Bounds?,
            profile: MeasuredProfile?
        ) {
            guard includedSketchFeatureIDs.insert(featureID).inserted else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            counts.sketches += 1
            counts.sketchPrimitives += sketch.entities.count
            if let sketchBounds {
                bounds.include(sketchBounds)
                sketchCurveSourceBounds[featureID] = sketchBounds
            }
            if let profile {
                includeProfile(profile, featureID: featureID)
            }
        }

        func includeCurveSource(
            featureID: FeatureID,
            node: FeatureNode
        ) throws {
            if case .sketch(let sketch) = node.operation {
                includeSketch(
                    featureID: featureID,
                    sketch: sketch,
                    sketchBounds: try boundsForSketch(
                        sketch,
                        parameters: document.cadDocument.parameters
                    ),
                    profile: nil
                )
                return
            }
            guard includedSourceFeatureIDs.insert(featureID).inserted else {
                return
            }
            if let curveBounds = boundsForEvaluatedCurves(evaluatedDocument()?.curves[featureID]) {
                bounds.include(curveBounds)
                sketchCurveSourceBounds[featureID] = curveBounds
            }
        }

        // Extracted per-operation bodies keep this frame small enough for
        // 512 KB worker stacks in unoptimized builds.
        func measureSketchCase(_ sketch: Sketch, node: FeatureNode, featureID: FeatureID) throws {
            let sketchBounds = try boundsForSketch(
                sketch,
                parameters: document.cadDocument.parameters
            )
            let profile = try measureProfile(
                featureID: featureID,
                featureName: node.name,
                sketch: sketch,
                parameters: document.cadDocument.parameters
            )
            if let profile {
                profileCache[featureID] = profile
            }
            if shouldMeasure(featureID) {
                includeSketch(
                    featureID: featureID,
                    sketch: sketch,
                    sketchBounds: sketchBounds,
                    profile: profile
                )
            }
        }

        func appendEvaluatedSheet(sourceFeatureID: FeatureID, node: FeatureNode, featureID: FeatureID) throws {
            var skipReason: String?
            let sheet = try measureEvaluatedSheet(
                featureID: featureID, featureName: node.name,
                sourceFeatureID: sourceFeatureID,
                sourceFeatureName: document.cadDocument.designGraph.nodes[sourceFeatureID]?.name,
                evaluatedDocument: evaluatedDocument(), unsupportedReason: &skipReason)
            guard let sheet else {
                let detail = skipReason.map { " \($0)" } ?? ""
                diagnostics.append(EditorDiagnostic(severity: .info,
                    message: "Measurement skipped a sheet outside the supported evaluation subset.\(detail)"))
                return
            }
            sheets.append(sheet)
            bounds.include(sheet.bounds)
        }

        func measureExtrudeCase(_ extrude: ExtrudeFeature, node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            if extrude.resultKind == .sheet {
                try appendEvaluatedSheet(sourceFeatureID: extrude.section.featureID, node: node, featureID: featureID)
                return
            }
            if extrude.operation != .newBody {
                var reason: String?
                guard let values = try measureEvaluatedBodySolids(featureID: featureID,
                    featureName: node.name, sourceFeatureID: extrude.section.featureID,
                    sourceFeatureName: document.cadDocument.designGraph.nodes[extrude.section.featureID]?.name,
                    evaluatedDocument: evaluatedDocument(), unsupportedReason: &reason) else {
                    throw EditorError(code: .commandInvalid,
                        message: "Extrusion Boolean measurement failed: \(reason ?? "Missing evaluated geometry").")
                }
                for solid in values { solids.append(solid); bounds.include(solid.bounds) }
                return
            }
            guard let sourceNode = document.cadDocument.designGraph.nodes[extrude.section.featureID],
                  case .sketch(let sourceSketch) = sourceNode.operation else {
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .warning,
                        message: "Measurement skipped an extrude feature with an unresolved profile reference."
                    )
                )
                return
            }
            let sourceSketchBounds = try boundsForSketch(
                sourceSketch,
                parameters: document.cadDocument.parameters
            )
            let profile = try profileCache[extrude.section.featureID] ?? measureProfile(
                featureID: extrude.section.featureID,
                featureName: sourceNode.name,
                sketch: sourceSketch,
                parameters: document.cadDocument.parameters
            )
            guard let profile else {
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .warning,
                        message: "Measurement skipped an extrude feature with an unsupported profile."
                    )
                )
                return
            }
            profileCache[extrude.section.featureID] = profile
            includeSketch(
                featureID: extrude.section.featureID,
                sketch: sourceSketch,
                sketchBounds: sourceSketchBounds,
                profile: profile
            )
            // Volume and bounds come from the evaluated B-rep for every profile; only the authored
            // extrusion height is read from source parameters.
            var evaluatedSkipReason: String?
            var solid = try measureEvaluatedSolid(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: extrude.section.featureID,
                sourceFeatureName: sourceNode.name,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSkipReason
            )
            solid?.linearDimensions = [
                MeasurementResult.Solid.LinearDimension(
                    kind: .extrusionHeight,
                    meters: try extrusionHeightMeters(
                        profile: profile,
                        extrude: extrude,
                        parameters: document.cadDocument.parameters
                    )
                ),
            ]
            guard let solid else {
                let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped an extrude feature outside the supported exact solid evaluation subset.\(detail)"
                    )
                )
                return
            }
            solids.append(solid)
            bounds.include(solid.bounds)
        }

        func measureRevolveCase(_ revolve: RevolveFeature, node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            if revolve.resultKind == .sheet {
                try appendEvaluatedSheet(sourceFeatureID: revolve.section.featureID, node: node, featureID: featureID)
                return
            }
            guard let sourceNode = document.cadDocument.designGraph.nodes[revolve.section.featureID],
                  case .sketch(let sourceSketch) = sourceNode.operation else {
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .warning,
                        message: "Measurement skipped a revolve feature with an unresolved profile reference."
                    )
                )
                return
            }
            let sourceSketchBounds = try boundsForSketch(
                sourceSketch,
                parameters: document.cadDocument.parameters
            )
            let profile = try profileCache[revolve.section.featureID] ?? measureProfile(
                featureID: revolve.section.featureID,
                featureName: sourceNode.name,
                sketch: sourceSketch,
                parameters: document.cadDocument.parameters
            )
            guard let profile else {
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .warning,
                        message: "Measurement skipped a revolve feature with an unsupported profile."
                    )
                )
                return
            }
            profileCache[revolve.section.featureID] = profile
            includeSketch(
                featureID: revolve.section.featureID,
                sketch: sourceSketch,
                sketchBounds: sourceSketchBounds,
                profile: profile
            )
            var evaluatedSkipReason: String?
            let solid = try measureEvaluatedSolid(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: revolve.section.featureID,
                sourceFeatureName: sourceNode.name,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSkipReason
            )
            guard let solid else {
                let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped a revolve feature outside the supported solid evaluation subset.\(detail)"
                    )
                )
                return
            }
            solids.append(solid)
            bounds.include(solid.bounds)
        }

        func measureSweepCase(_ sweep: SweepFeature, node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            guard let sectionReference = sweep.sections.first,
                  let sourceNode = document.cadDocument.designGraph.nodes[sectionReference.featureID],
                  let pathNode = document.cadDocument.designGraph.nodes[sweep.path.featureID] else {
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .warning,
                        message: "Measurement skipped a sweep feature with unresolved section or path references."
                    )
                )
                return
            }
            let pathSketch: Sketch?
            if case .sketch(let sketch) = pathNode.operation {
                pathSketch = sketch
            } else {
                pathSketch = nil
            }
            let pathLengthMeters = try pathLength(
                featureID: sweep.path.featureID,
                sketch: pathSketch,
                parameters: document.cadDocument.parameters,
                evaluatedDocument: pathSketch == nil ? evaluatedDocument() : nil
            )
            let measuredProfile: MeasuredProfile?
            switch sectionReference {
            case .profile(let profileReference):
                guard case .sketch(let sourceSketch) = sourceNode.operation else {
                    diagnostics.append(
                        EditorDiagnostic(
                            severity: .warning,
                            message: "Measurement skipped a sweep feature with an unresolved profile section."
                        )
                    )
                    return
                }
                let profile = try profileCache[profileReference.featureID] ?? measureProfile(
                    featureID: profileReference.featureID,
                    featureName: sourceNode.name,
                    sketch: sourceSketch,
                    parameters: document.cadDocument.parameters
                )
                guard let profile else {
                    diagnostics.append(
                        EditorDiagnostic(
                            severity: .warning,
                            message: "Measurement skipped a sweep feature with an unsupported profile section."
                        )
                    )
                    return
                }
                profileCache[profileReference.featureID] = profile
                measuredProfile = profile
                includeSketch(
                    featureID: profileReference.featureID,
                    sketch: sourceSketch,
                    sketchBounds: try boundsForSketch(
                        sourceSketch,
                        parameters: document.cadDocument.parameters
                    ),
                    profile: profile
                )
            case .curve:
                measuredProfile = nil
                try includeCurveSource(
                    featureID: sectionReference.featureID,
                    node: sourceNode
                )
            }
            try includeCurveSource(
                featureID: sweep.path.featureID,
                node: pathNode
            )
            for guide in sweep.guides {
                guard let guideNode = document.cadDocument.designGraph.nodes[guide.featureID] else {
                    diagnostics.append(
                        EditorDiagnostic(
                            severity: .warning,
                            message: "Measurement skipped a sweep guide with an unresolved curve reference."
                        )
                    )
                    continue
                }
                try includeCurveSource(
                    featureID: guide.featureID,
                    node: guideNode
                )
            }
            if sweep.options.resultKind == .sheet {
                var evaluatedSweepSkipReason: String?
                let sheet = try measureEvaluatedSweepSheet(
                    featureID: featureID,
                    featureName: node.name,
                    sourceFeatureID: sectionReference.featureID,
                    sourceFeatureName: sourceNode.name,
                    sweep: sweep,
                    pathLengthMeters: pathLengthMeters,
                    parameters: document.cadDocument.parameters,
                    evaluatedDocument: evaluatedDocument(),
                    unsupportedReason: &evaluatedSweepSkipReason
                )
                guard let sheet else {
                    let detail = evaluatedSweepSkipReason.map { " \($0)" } ?? ""
                    diagnostics.append(
                        EditorDiagnostic(
                            severity: .info,
                            message: "Measurement skipped a sweep sheet outside the supported evaluation subset.\(detail)"
                        )
                    )
                    return
                }
                sheets.append(sheet)
                bounds.include(sheet.bounds)
                return
            }
            guard let profile = measuredProfile else {
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .warning,
                        message: "Measurement skipped a solid sweep feature without a closed profile section."
                    )
                )
                return
            }
            var evaluatedSweepSkipReason: String?
            var measuredSolids = try measureEvaluatedSweepSolids(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: sectionReference.featureID,
                sourceFeatureName: sourceNode.name,
                sweep: sweep,
                pathLengthMeters: pathLengthMeters,
                parameters: document.cadDocument.parameters,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSweepSkipReason
            )
            // A straight sweep also reports its authored normal height and path length; its
            // volume and bounds remain the evaluated B-rep's.
            if let dimensions = try straightSweepDimensions(
                profile: profile,
                sweep: sweep,
                pathSketch: pathSketch,
                parameters: document.cadDocument.parameters
            ), measuredSolids?.count == 1 {
                measuredSolids?[0].linearDimensions = dimensions
            }
            guard let measuredSolids, !measuredSolids.isEmpty else {
                let detail = evaluatedSweepSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped a sweep feature outside the supported solid evaluation subset.\(detail)"
                    )
                )
                return
            }
            for solid in measuredSolids {
                solids.append(solid)
                bounds.include(solid.bounds)
            }
        }

        func measureLoftCase(_ loft: LoftFeature, node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            for section in loft.sections {
                guard let sourceNode = document.cadDocument.designGraph.nodes[section.featureID],
                      case .sketch(let sourceSketch) = sourceNode.operation else {
                    diagnostics.append(
                        EditorDiagnostic(
                            severity: .warning,
                            message: "Measurement skipped a loft section with an unresolved profile reference."
                        )
                    )
                    continue
                }
                let profile = try profileCache[section.featureID] ?? measureProfile(
                    featureID: section.featureID,
                    featureName: sourceNode.name,
                    sketch: sourceSketch,
                    parameters: document.cadDocument.parameters
                )
                profileCache[section.featureID] = profile
                includeSketch(
                    featureID: section.featureID,
                    sketch: sourceSketch,
                    sketchBounds: try boundsForSketch(
                        sourceSketch,
                        parameters: document.cadDocument.parameters
                    ),
                    profile: profile
                )
            }
            let sourceFeatureID = loft.sections.first?.featureID ?? featureID
            let sourceNode = document.cadDocument.designGraph.nodes[sourceFeatureID]
            if loft.options.resultKind == .sheet {
                var evaluatedSkipReason: String?
                let sheet = try measureEvaluatedSheet(
                    featureID: featureID,
                    featureName: node.name,
                    sourceFeatureID: sourceFeatureID,
                    sourceFeatureName: sourceNode?.name,
                    evaluatedDocument: evaluatedDocument(),
                    unsupportedReason: &evaluatedSkipReason
                )
                guard let sheet else {
                    let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                    diagnostics.append(
                        EditorDiagnostic(
                            severity: .info,
                            message: "Measurement skipped a loft sheet outside the supported evaluation subset.\(detail)"
                        )
                    )
                    return
                }
                sheets.append(sheet)
                bounds.include(sheet.bounds)
                return
            }
            var evaluatedSkipReason: String?
            let solid = try measureEvaluatedSolid(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: sourceFeatureID,
                sourceFeatureName: sourceNode?.name,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSkipReason
            )
            guard let solid else {
                let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped a loft solid outside the supported evaluation subset.\(detail)"
                    )
                )
                return
            }
            solids.append(solid)
            bounds.include(solid.bounds)
        }

        func measureBooleanCase(_ boolean: BooleanFeature, node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            let sourceFeatureID = boolean.targets.first?.featureID ?? boolean.tool.featureID
            let sourceNode = document.cadDocument.designGraph.nodes[sourceFeatureID]
            var evaluatedSkipReason: String?
            let solid = try measureEvaluatedSolid(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: sourceFeatureID,
                sourceFeatureName: sourceNode?.name,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSkipReason
            )
            guard let solid else {
                let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped Boolean solid outside the supported evaluation subset.\(detail)"
                    )
                )
                return
            }
            solids.append(solid)
            bounds.include(solid.bounds)
        }

        func measurePolySplineCase(_ polySpline: PolySplineFeature, node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            boundsOnlySources.append((featureID, polySpline.sourceMesh.positions))
            diagnostics.append(
                EditorDiagnostic(
                    severity: .info,
                    message: "Measurement included PolySpline source bounds; B-spline sheet area and curvature measurement remain unsupported."
                )
            )
        }

        func measureBSplineSurfaceCase(_ surfaceFeature: BSplineSurfaceFeature, node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            boundsOnlySources.append((featureID, surfaceFeature.surface.controlPoints.flatMap { $0 }))
            diagnostics.append(
                EditorDiagnostic(
                    severity: .info,
                    message: "Measurement included B-spline surface control-net bounds; exact sheet area and curvature measurement remain unsupported."
                )
            )
        }

        func measureFaceLoopOffsetCase(node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            guard case .faceLoopOffset(let faceLoopOffset) = node.operation else {
                return
            }
            let sourceNode = document.cadDocument.designGraph.nodes[faceLoopOffset.target.featureID]
            var evaluatedSkipReason: String?
            let solid = try measureEvaluatedSolid(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: faceLoopOffset.target.featureID,
                sourceFeatureName: sourceNode?.name,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSkipReason
            )
            guard let solid else {
                let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped Offset Face Loop direct-edit solid.\(detail)"
                    )
                )
                return
            }
            solids.append(solid)
            bounds.include(solid.bounds)
        }

        func measureEdgeOffsetCase(node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            guard case .edgeOffset(let edgeOffset) = node.operation else {
                return
            }
            let sourceNode = document.cadDocument.designGraph.nodes[edgeOffset.target.featureID]
            var evaluatedSkipReason: String?
            let solid = try measureEvaluatedSolid(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: edgeOffset.target.featureID,
                sourceFeatureName: sourceNode?.name,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSkipReason
            )
            guard let solid else {
                let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped Offset Edge direct-edit solid.\(detail)"
                    )
                )
                return
            }
            solids.append(solid)
            bounds.include(solid.bounds)
        }

        func measureFaceKnifeCase(_ faceKnife: FaceKnifeFeature, node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            let sourceNode = document.cadDocument.designGraph.nodes[faceKnife.target.featureID]
            var evaluatedSkipReason: String?
            let solid = try measureEvaluatedSolid(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: faceKnife.target.featureID,
                sourceFeatureName: sourceNode?.name,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSkipReason
            )
            guard let solid else {
                let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped Face Knife direct-edit solid.\(detail)"
                    )
                )
                return
            }
            solids.append(solid)
            bounds.include(solid.bounds)
        }

        func measureFaceDraftCase(_ faceDraft: FaceDraftFeature, node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            let sourceNode = document.cadDocument.designGraph.nodes[faceDraft.target.featureID]
            var evaluatedSkipReason: String?
            let solid = try measureEvaluatedSolid(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: faceDraft.target.featureID,
                sourceFeatureName: sourceNode?.name,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSkipReason
            )
            guard let solid else {
                let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped Draft Face direct-edit solid.\(detail)"
                    )
                )
                return
            }
            solids.append(solid)
            bounds.include(solid.bounds)
        }

        func measureFaceDeleteCase(_ faceDelete: FaceDeleteFeature, node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            let sourceNode = document.cadDocument.designGraph.nodes[faceDelete.target.featureID]
            var evaluatedSkipReason: String?
            let sheet = try measureEvaluatedSheet(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: faceDelete.target.featureID,
                sourceFeatureName: sourceNode?.name,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSkipReason
            )
            guard let sheet else {
                let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped Face Delete direct-edit sheet.\(detail)"
                    )
                )
                return
            }
            sheets.append(sheet)
            bounds.include(sheet.bounds)
        }

        func measureSurfaceFillCase(_ surfaceFill: SurfaceFillFeature, node: FeatureNode, featureID: FeatureID) throws {
            guard !isSupersededInDocumentScope(featureID), shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            let sourceNode = document.cadDocument.designGraph.nodes[surfaceFill.targetFeatureID]
            var evaluatedSkipReason: String?
            let sheet = try measureEvaluatedSheet(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: surfaceFill.targetFeatureID,
                sourceFeatureName: sourceNode?.name,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSkipReason
            )
            guard let sheet else {
                let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped Surface Fill sheet.\(detail)"
                    )
                )
                return
            }
            sheets.append(sheet)
            bounds.include(sheet.bounds)
        }

        func measureEvaluatedBodyOperationCase(
            node: FeatureNode,
            featureID: FeatureID,
            sourceFeatureID: FeatureID,
            operationName: String
        ) throws {
            guard !isSupersededInDocumentScope(featureID) else {
                return
            }
            guard shouldMeasure(featureID) else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            let sourceNode = document.cadDocument.designGraph.nodes[sourceFeatureID]
            var evaluatedSkipReason: String?
            let measuredSolids = try measureEvaluatedBodySolids(
                featureID: featureID,
                featureName: node.name,
                sourceFeatureID: sourceFeatureID,
                sourceFeatureName: sourceNode?.name,
                evaluatedDocument: evaluatedDocument(),
                unsupportedReason: &evaluatedSkipReason
            )
            guard let measuredSolids, !measuredSolids.isEmpty else {
                let detail = evaluatedSkipReason.map { " \($0)" } ?? ""
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement skipped \(operationName) solid output.\(detail)"
                    )
                )
                return
            }
            for solid in measuredSolids {
                solids.append(solid)
                bounds.include(solid.bounds)
            }
        }

        for featureID in document.cadDocument.designGraph.order {
            guard let node = document.cadDocument.designGraph.nodes[featureID] else {
                continue
            }
            guard !node.isSuppressed else {
                continue
            }

            switch node.operation {
            case .sketch(let sketch):
                try measureSketchCase(sketch, node: node, featureID: featureID)
            case .extrude(let extrude):
                try measureExtrudeCase(extrude, node: node, featureID: featureID)
            case .revolve(let revolve):
                try measureRevolveCase(revolve, node: node, featureID: featureID)
            case .sweep(let sweep):
                try measureSweepCase(sweep, node: node, featureID: featureID)
            case .loft(let loft):
                try measureLoftCase(loft, node: node, featureID: featureID)
            case .boolean(let boolean):
                try measureBooleanCase(boolean, node: node, featureID: featureID)
            case .polySpline(let polySpline):
                try measurePolySplineCase(polySpline, node: node, featureID: featureID)
            case .constrainedSurface:
                guard !isSupersededInDocumentScope(featureID), shouldMeasure(featureID) else { continue }
                includedSourceFeatureIDs.insert(featureID)
                var skipReason: String?
                if let sheet = try measureEvaluatedSheet(featureID: featureID, featureName: node.name,
                    sourceFeatureID: featureID, sourceFeatureName: node.name,
                    evaluatedDocument: evaluatedDocument(), unsupportedReason: &skipReason) {
                    sheets.append(sheet)
                    bounds.include(sheet.bounds)
                } else {
                    diagnostics.append(EditorDiagnostic(severity: .info,
                        message: "Measurement skipped Constrained Surface. \(skipReason ?? "No evaluated sheet.")"))
                }
            case .bSplineSurface(let surfaceFeature):
                try measureBSplineSurfaceCase(surfaceFeature, node: node, featureID: featureID)
            case .faceLoopOffset:
                try measureFaceLoopOffsetCase(node: node, featureID: featureID)
            case .edgeOffset:
                try measureEdgeOffsetCase(node: node, featureID: featureID)
            case .faceKnife(let faceKnife):
                try measureFaceKnifeCase(faceKnife, node: node, featureID: featureID)
            case .faceDraft(let faceDraft):
                try measureFaceDraftCase(faceDraft, node: node, featureID: featureID)
            case .faceDelete(let faceDelete):
                try measureFaceDeleteCase(faceDelete, node: node, featureID: featureID)
            case .surfaceFill(let surfaceFill):
                try measureSurfaceFillCase(surfaceFill, node: node, featureID: featureID)
            case .mirror(let mirror):
                try measureEvaluatedBodyOperationCase(
                    node: node,
                    featureID: featureID,
                    sourceFeatureID: mirror.target.featureID,
                    operationName: "Mirror"
                )
            case .joinBodies(let join):
                guard let sourceFeatureID = join.targets.first?.featureID else {
                    throw EditorError(
                        code: .commandFailed,
                        message: "Measurement found a Join Bodies feature without source bodies."
                    )
                }
                try measureEvaluatedBodyOperationCase(
                    node: node,
                    featureID: featureID,
                    sourceFeatureID: sourceFeatureID,
                    operationName: "Join Bodies"
                )
            case .unjoinBody(let unjoin):
                try measureEvaluatedBodyOperationCase(
                    node: node,
                    featureID: featureID,
                    sourceFeatureID: unjoin.target.featureID,
                    operationName: "Unjoin Body"
                )
            case .importedBRep:
                try measureEvaluatedBodyOperationCase(
                    node: node,
                    featureID: featureID,
                    sourceFeatureID: featureID,
                    operationName: "Imported CAD"
                )
            case .involuteGear:
                try measureEvaluatedBodyOperationCase(node: node, featureID: featureID,
                    sourceFeatureID: featureID, operationName: "Involute Gear")
            case .primitive:
                try measureEvaluatedBodyOperationCase(
                    node: node,
                    featureID: featureID,
                    sourceFeatureID: featureID,
                    operationName: "Primitive"
                )
            case .bridgeCurve, .spatialPath:
                continue
            case .curveEdit:
                continue
            case .curveOffset:
                continue
            case .curveTrim:
                continue
            case .patchSurface,
                 .faceOffset,
                 .faceMove,
                 .edgeMove,
                 .vertexMove,
                 .linearPattern,
                 .radialPattern,
                 .gridPattern,
                 .curveDrivenPattern,
                 .chamfer,
                 .fillet,
                 .g2Blend,
                 .setbackCorner,
                 .shell,
                 .thicken,
                 .bridgeSurface,
                 .curveExtend,
                 .curveMatch,
                 .surfaceOffset,
                 .surfaceTrim,
                 .surfaceExtend,
                 .surfaceMatch,
                 .projectCurve:
                continue
            }
        }

        if scope == .document {
            counts.sourceFeatures = document.cadDocument.designGraph.order.count
        } else {
            counts.sourceFeatures = includedSourceFeatureIDs.count
            if selectedFeatureIDs?.isEmpty == true {
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Selection measurement found no measurable feature references."
                    )
                )
            } else if includedSourceFeatureIDs.isEmpty {
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .warning,
                        message: "Selection measurement could not resolve any selected source features."
                    )
                )
            }
        }

        try projectMeasurements(
            profiles: &profiles, solids: &solids, sheets: &sheets, bounds: &bounds,
            boundsOnlySources: boundsOnlySources,
            sketchCurveSourceBounds: sketchCurveSourceBounds,
            hierarchy: hierarchy, occurrences: occurrences, selectedOccurrences: selectedOccurrences,
            isSelection: selectedSceneNodeIDs != nil, document: document,
            evaluatedDocument: evaluatedDocument
        )

        counts.profiles = profiles.count
        counts.solids = solids.count
        counts.sheets = sheets.count
        let totals = MeasurementResult.Totals(
            profileAreaSquareMeters: profiles.reduce(0.0) {
                $0 + $1.areaSquareMeters
            },
            sheetAreaSquareMeters: sheets.reduce(0.0) {
                $0 + $1.surfaceAreaSquareMeters
            },
            solidVolumeCubicMeters: solids.reduce(0.0) {
                $0 + $1.volumeCubicMeters
            }
        )
        if profiles.contains(where: { $0.areaMethod == .sampledCurve }) {
            diagnostics.append(EditorDiagnostic(
                severity: .info,
                code: .measurementSampledProfileApproximation,
                message: "Profile area and bounds marked sampledCurve are approximations derived from curve samples."
            ))
        }
        if sheets.contains(where: {
            $0.surfaceAreaMethod == .tessellatedMesh
                || $0.boundsMethod == .tessellatedMesh
        }) {
            diagnostics.append(EditorDiagnostic(
                severity: .info,
                code: .measurementTessellatedSheetApproximation,
                message: "Sheet area and bounds marked tessellatedMesh are approximations derived from the display mesh."
            ))
        }
        if solids.contains(where: { solid in
            solid.surfaceAreaMethod == .tessellatedMesh
                || solid.boundsMethod == .tessellatedMesh
        }) {
            diagnostics.append(EditorDiagnostic(
                severity: .info,
                code: .measurementTessellatedSolidApproximation,
                message: "Solid volume uses exact B-rep evaluation; reported solid surface area and bounds marked tessellatedMesh are approximations derived from the display mesh."
            ))
        }
        let workspacePrecisionService = WorkspacePrecisionDiagnosticService()
        let workspacePrecision = workspacePrecisionService.report(
            for: bounds.bounds,
            ruler: ruler,
            tolerance: tolerance
        )
        diagnostics += workspacePrecisionService.diagnostics(
            for: workspacePrecision,
            displayUnit: ruler.displayUnit
        )
        let workspaceScaleRecommendationService = WorkspaceScaleRecommendationService()
        let workspaceScaleRecommendation = workspaceScaleRecommendationService.recommendation(
            for: bounds.bounds,
            currentRuler: ruler
        )
        diagnostics += workspaceScaleRecommendationService.diagnostics(
            for: workspaceScaleRecommendation
        )

        return MeasurementResult(
            scope: scope,
            displayUnit: ruler.displayUnit,
            counts: counts,
            bounds: bounds.bounds,
            totals: totals,
            profiles: profiles,
            solids: solids,
            sheets: sheets,
            diagnostics: diagnostics,
            workspacePrecision: workspacePrecision,
            workspaceScaleRecommendation: workspaceScaleRecommendation
        )
    }

    private func projectMeasurements(
        profiles: inout [MeasurementResult.Profile],
        solids: inout [MeasurementResult.Solid],
        sheets: inout [MeasurementResult.Sheet],
        bounds: inout MeasurementBoundsAccumulator,
        boundsOnlySources: [(featureID: FeatureID, points: [Point3D])],
        sketchCurveSourceBounds: [FeatureID: MeasurementResult.Bounds],
        hierarchy: SceneNodeHierarchy,
        occurrences: [SceneNodeHierarchy.Occurrence],
        selectedOccurrences: [SceneNodeHierarchy.Occurrence],
        isSelection: Bool,
        document: DesignDocument,
        evaluatedDocument: () -> EvaluatedDocument?
    ) throws {
        let nodes = document.productMetadata.sceneNodes
        let features = Dictionary(uniqueKeysWithValues: document.cadDocument.designGraph.nodes.map {
            ($0.key.description, $0.value)
        })
        // Measured geometry is placed by the occurrences of its presenting scene node. A feature
        // without one has no product placement and is measured once in the world frame, the same
        // rule the viewport and section analysis apply.
        func isUnpresented(_ featureID: String) -> Bool {
            guard let feature = features[featureID] else {
                return false
            }
            return hierarchy.presentingSceneNodeID(for: feature.id) == nil
        }
        func presentationOccurrences(
            of featureID: String,
            in candidates: [SceneNodeHierarchy.Occurrence]
        ) -> [SceneNodeHierarchy.Occurrence] {
            guard let feature = features[featureID] else {
                return []
            }
            return hierarchy.presentationOccurrences(of: feature.id, in: candidates)
        }
        var placedBounds = MeasurementBoundsAccumulator()
        var placedProfiles: [MeasurementResult.Profile] = []
        for profile in profiles {
            guard let feature = features[profile.featureID], case .sketch(let sketch) = feature.operation else {
                throw EditorError(code: .referenceUnresolved, message: "A measured profile requires its sketch source.")
            }
            if isUnpresented(profile.featureID) {
                placedProfiles.append(profile)
                if !isSelection {
                    placedBounds.include(profile.bounds)
                }
                continue
            }
            // Dependency profiles remain source information when the selection names only a body.
            let selectedPlacements = presentationOccurrences(of: profile.featureID, in: selectedOccurrences)
            let placements = selectedPlacements.isEmpty
                ? presentationOccurrences(of: profile.featureID, in: occurrences).filter {
                    $0.componentInstanceID == nil
                }
                : selectedPlacements
            for occurrence in placements {
                var result = profile
                result.occurrenceID = occurrence.id
                if occurrence.worldTransform != .identity {
                    let frame = try placedFrame(for: sketch.plane, transform: occurrence.worldTransform)
                    result.area = .init(value: result.area.value * frame.u.cross(frame.v).length, method: result.area.method)
                    guard result.area.value.isFinite else {
                        throw EditorError(code: .commandFailed, message: "Placed profile area is not representable.")
                    }
                    guard let sketchBounds = try boundsForSketch(
                        sketch, parameters: document.cadDocument.parameters,
                        transform: occurrence.worldTransform
                    ) else {
                        throw EditorError(code: .commandFailed, message: "A placed profile has no measurable bounds.")
                    }
                    result.measuredBounds = .init(value: sketchBounds, method: result.measuredBounds.method)
                }
                placedProfiles.append(result)
                if !isSelection || !selectedPlacements.isEmpty {
                    placedBounds.include(result.bounds)
                }
            }
        }
        var placedSolids: [MeasurementResult.Solid] = []
        var solidOrdinals: [String: Int] = [:]
        for solid in solids {
            let ordinal = solidOrdinals[solid.featureID, default: 0]
            solidOrdinals[solid.featureID] = ordinal + 1
            if !isSelection && isUnpresented(solid.featureID) {
                placedSolids.append(solid)
                placedBounds.include(solid.bounds)
                continue
            }
            for occurrence in presentationOccurrences(of: solid.featureID, in: selectedOccurrences) {
                var result = solid
                result.occurrenceID = occurrence.id
                let transform = occurrence.worldTransform
                if transform != .identity {
                    guard let feature = features[solid.featureID], let evaluated = evaluatedDocument() else {
                        throw EditorError(code: .evaluationFailed, message: "Placed solid measurement requires evaluated geometry.")
                    }
                    let references = evaluatedBodyReferences(for: feature.id, in: evaluated)
                    guard references.indices.contains(ordinal), let mesh = evaluated.meshes[references[ordinal].bodyID] else {
                        throw EditorError(code: .referenceUnresolved, message: "Placed solid measurement cannot resolve its body output.")
                    }
                    let measurement = try evaluatedMeshMeasurement(mesh, transform: transform)
                    let determinant = try volumeScale(of: transform)
                    result.volume = .init(value: result.volume.value * determinant, method: result.volume.method)
                    guard result.volume.value.isFinite else {
                        throw EditorError(code: .commandFailed, message: "Placed solid volume is not representable.")
                    }
                    result.surfaceArea = .init(value: measurement.surfaceAreaSquareMeters, method: .tessellatedMesh)
                    result.measuredBounds = .init(value: measurement.bounds, method: .tessellatedMesh)
                    for index in result.linearDimensions.indices {
                        let dimension = result.linearDimensions[index]
                        switch dimension.kind {
                        case .extrusionHeight, .sweepNormalHeight:
                            guard let source = features[solid.sourceFeatureID], case .sketch(let sketch) = source.operation else {
                                throw EditorError(code: .referenceUnresolved, message: "Placed height requires its source plane.")
                            }
                            let frame = try placedFrame(for: sketch.plane, transform: transform)
                            result.linearDimensions[index].meters *= determinant / frame.u.cross(frame.v).length
                        case .sweepPathLength:
                            result.linearDimensions[index].meters = try placedSweepLength(
                                dimension.meters, feature: feature, document: document,
                                evaluated: evaluated, transform: transform
                            )
                        }
                    }
                }
                placedSolids.append(result)
                placedBounds.include(result.bounds)
            }
        }
        var placedSheets: [MeasurementResult.Sheet] = []
        for sheet in sheets {
            if !isSelection && isUnpresented(sheet.featureID) {
                placedSheets.append(sheet)
                placedBounds.include(sheet.bounds)
                continue
            }
            for occurrence in presentationOccurrences(of: sheet.featureID, in: selectedOccurrences) {
                var result = sheet
                result.occurrenceID = occurrence.id
                let transform = occurrence.worldTransform
                if transform != .identity {
                    guard let feature = features[sheet.featureID], let evaluated = evaluatedDocument(),
                          let reference = evaluatedBodyReferences(for: feature.id, in: evaluated).first,
                          let mesh = evaluated.meshes[reference.bodyID] else {
                        throw EditorError(code: .referenceUnresolved, message: "Placed sheet measurement requires its evaluated body.")
                    }
                    let measurement = try evaluatedMeshMeasurement(mesh, transform: transform)
                    result.surfaceArea = .init(value: measurement.surfaceAreaSquareMeters, method: .tessellatedMesh)
                    result.measuredBounds = .init(value: measurement.bounds, method: .tessellatedMesh)
                    for index in result.linearDimensions.indices {
                        result.linearDimensions[index].meters = try placedSweepLength(
                            result.linearDimensions[index].meters, feature: feature, document: document,
                            evaluated: evaluated, transform: transform
                        )
                    }
                }
                placedSheets.append(result)
                placedBounds.include(result.bounds)
            }
        }
        for source in boundsOnlySources {
            if hierarchy.presentingSceneNodeID(for: source.featureID) == nil {
                guard !isSelection else { continue }
                for point in source.points {
                    placedBounds.include(point)
                }
                continue
            }
            for occurrence in hierarchy.presentationOccurrences(of: source.featureID, in: selectedOccurrences) {
                let placement = try ScenePlacement(occurrence.worldTransform)
                for point in source.points {
                    placedBounds.include(placement.point(point))
                }
            }
        }
        if !isSelection {
            for (featureID, sourceBounds) in sketchCurveSourceBounds
            where hierarchy.presentingSceneNodeID(for: featureID) == nil {
                placedBounds.include(sourceBounds)
            }
        }
        // Open sketches and curves contribute bounds even when they have no closed profile.
        for occurrence in selectedOccurrences {
            guard let featureID = nodes[occurrence.sourceSceneNodeID]?.reference?.featureID,
                  let feature = document.cadDocument.designGraph.nodes[featureID],
                  !feature.isSuppressed else { continue }
            if case .sketch(let sketch) = feature.operation {
                if let sketchBounds = try boundsForSketch(
                    sketch, parameters: document.cadDocument.parameters, transform: occurrence.worldTransform
                ) { placedBounds.include(sketchBounds) }
            } else if nodes[occurrence.sourceSceneNodeID]?.reference?.kind == .feature,
                      let curves = evaluatedDocument()?.curves[featureID] {
                for curve in curves {
                    for point in curve.points {
                        placedBounds.include(try occurrence.worldTransform.applied(to: point))
                    }
                }
            }
        }
        profiles = placedProfiles
        solids = placedSolids
        sheets = placedSheets
        bounds = placedBounds
    }

    private func volumeScale(of transform: Transform3D) throws -> Double {
        let x = try transform.applyingLinearPart(to: .unitX)
        let y = try transform.applyingLinearPart(to: .unitY)
        let z = try transform.applyingLinearPart(to: .unitZ)
        let scale = abs(x.dot(y.cross(z)))
        guard scale.isFinite, scale > 0 else {
            throw EditorError(code: .commandFailed, message: "Placement volume scale is not representable.")
        }
        return scale
    }

    private func placedFrame(for plane: SketchPlane, transform: Transform3D) throws -> PlaneFrame {
        let frame = try planeFrame(for: plane)
        if transform == .identity { return frame }
        return PlaneFrame(
            origin: try transform.applied(to: frame.origin),
            normal: try transform.applyingNormal(to: frame.normal),
            u: try transform.applyingLinearPart(to: frame.u),
            v: try transform.applyingLinearPart(to: frame.v)
        )
    }

    private func placedSweepLength(
        _ sourceLength: Double, feature: FeatureNode, document: DesignDocument,
        evaluated: EvaluatedDocument, transform: Transform3D
    ) throws -> Double {
        guard case .sweep(let sweep) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "Placed sweep length requires its path source.")
        }
        let segments = try SweepEvaluationPlanService().orderedPathSegments(
            for: sweep, document: document.cadDocument,
            evaluatedDocument: evaluated, tolerance: tolerance
        )
        let affine = try transform.coordinateMap(to: .identity)
        guard let affine else { return sourceLength }
        let resolver = DefaultCurveArcLengthResolver()
        var remaining = sourceLength
        var length = 0.0
        for segment in segments where remaining > tolerance.distance {
            let curve = segment.curve
            if let exact = curve.exactCurve {
                let interval: ScalarInterval
                switch curve.parameterDomain {
                case .closed(let lower, let upper): interval = try ScalarInterval(lower: lower, upper: upper)
                case .periodic(let period): interval = try ScalarInterval(lower: 0, upper: period)
                case .unbounded:
                    throw EditorError(code: .commandInvalid, message: "A measured sweep path must be bounded.")
                }
                let parameterization = try resolver.parameterization(of: exact, over: interval, tolerance: tolerance)
                let available = parameterization.lengthEnclosure.midpoint
                guard available.isFinite, available > 0 else {
                    throw EditorError(code: .commandInvalid, message: "A measured path contains a degenerate span.")
                }
                let consumed = min(remaining, available)
                let fraction = consumed / available
                let end = try parameterization.parameterEnclosure(
                    atArcLengthFraction: segment.isReversed ? 1 - fraction : fraction
                ).parameter
                let span = try ScalarInterval(
                    lower: segment.isReversed ? end : interval.lower,
                    upper: segment.isReversed ? interval.upper : end
                )
                let image = try Curve3D.affineImage(AffineImageCurve3D(source: exact, transform: affine, tolerance: tolerance))
                length += try resolver.enclosure(
                    of: image, over: span, tolerance: tolerance
                ).midpoint
                remaining -= consumed
            } else {
                let points = segment.isReversed ? Array(curve.points.reversed()) : curve.points
                for index in points.indices.dropFirst() where remaining > tolerance.distance {
                    let delta = points[index] - points[index - 1]
                    let available = delta.length
                    guard available > 0, available.isFinite else {
                        throw EditorError(code: .commandInvalid, message: "A measured path contains a degenerate span.")
                    }
                    let consumed = min(remaining, available)
                    length += try transform.applyingLinearPart(to: delta * (consumed / available)).length
                    remaining -= consumed
                }
            }
        }
        guard remaining <= tolerance.distance, length.isFinite else {
            throw EditorError(code: .commandFailed, message: "Placed sweep length could not resolve the retained path span.")
        }
        return length
    }

    private func bodyFeatureIDsSupersededByDirectEdits(in document: CADDocument) -> Set<FeatureID> {
        var result: Set<FeatureID> = []
        for featureID in document.designGraph.order {
            guard let node = document.designGraph.nodes[featureID],
                  !node.isSuppressed else {
                continue
            }
            result.formUnion(node.operation.supersededBodyFeatureIDs)
        }
        return result
    }

    private func measureProfile(
        featureID: FeatureID,
        featureName: String?,
        sketch: Sketch,
        parameters: ParameterTable
    ) throws -> MeasuredProfile? {
        let frame = try planeFrame(for: sketch.plane)
        let circles = sketch.entities.values.compactMap(\.circle)
        if circles.count == 1, sketch.entities.count == 1, let circle = circles.first {
            let center2D = try resolvedPoint(circle.center, parameters: parameters)
            let center3D = frame.map(center2D)
            let radius = try resolvedLength(circle.radius, parameters: parameters)
            guard radius > tolerance.distance else {
                return nil
            }
            let bounds = circleBounds(center: center3D, radius: radius, frame: frame)
            let result = MeasurementResult.Profile(
                featureID: featureID.description,
                featureName: featureName,
                kind: .circle,
                area: .init(value: Double.pi * radius * radius, method: .analytic),
                bounds: .init(value: bounds, method: .analytic)
            )
            return MeasuredProfile(
                result: result,
                plane: sketch.plane,
                frame: frame,
                baseBounds: bounds
            )
        }

        let segments = try resolvedProfileSegments(
            in: sketch,
            parameters: parameters
        )
        guard !segments.isEmpty else {
            return nil
        }
        guard let loop = orderedClosedLoop(from: segments) else {
            return nil
        }
        let area = abs(polygonArea(loop))
        guard area > tolerance.distance * tolerance.distance else {
            return nil
        }
        var loopBounds = MeasurementBoundsAccumulator()
        for point in loop {
            loopBounds.include(frame.map(point))
        }
        guard let bounds = loopBounds.bounds else {
            return nil
        }
        let profileKind: MeasurementResult.Profile.Kind = segments.contains {
            $0.kind != .line
        } ? .curveLoop : .lineLoop
        let measurementMethod: MeasurementResult.MeasurementMethod = profileKind == .curveLoop
            ? .sampledCurve
            : .analytic
        let result = MeasurementResult.Profile(
            featureID: featureID.description,
            featureName: featureName,
            kind: profileKind,
            area: .init(value: area, method: measurementMethod),
            bounds: .init(value: bounds, method: measurementMethod)
        )
        return MeasuredProfile(
            result: result,
            plane: sketch.plane,
            frame: frame,
            baseBounds: bounds
        )
    }

    /// The authored extrusion height measured along the profile normal.
    private func extrusionHeightMeters(
        profile: MeasuredProfile,
        extrude: ExtrudeFeature,
        parameters: ParameterTable
    ) throws -> Double {
        let range = try extrude.resolvedAxialRange(tolerance: tolerance) {
            try parameters.resolvedValue(for: $0)
        }
        let distance = range.upperBound - range.lowerBound
        let extrusionDirection = try directionVector(
            for: extrude.direction,
            frame: profile.frame
        )
        let normalComponent = extrusionDirection.dot(profile.frame.normal)
        guard abs(normalComponent) > tolerance.angle else {
            throw EditorError(
                code: .commandFailed,
                message: "Measurement cannot compute the height of an extrude direction parallel to the profile plane."
            )
        }
        return abs(distance * normalComponent)
    }

    /// The authored normal height and path length of a straight, untwisted, unscaled sweep.
    private func straightSweepDimensions(
        profile: MeasuredProfile,
        sweep: SweepFeature,
        pathSketch: Sketch?,
        parameters: ParameterTable
    ) throws -> [MeasurementResult.Solid.LinearDimension]? {
        guard sweep.sections.count == 1,
              sweep.guides.isEmpty,
              sweep.options.resultKind == .solid,
              sweep.options.booleanOperation == .newBody,
              sweep.options.keepTools == false,
              profile.result.kind != .curveLoop,
              let pathSketch else {
            return nil
        }
        let twistAngle = try resolvedAngle(sweep.options.twistAngle, parameters: parameters)
        guard sweep.options.twistLaw == nil,
              sweep.options.approximationTolerance == nil,
              abs(twistAngle) <= tolerance.angle else {
            return nil
        }
        let endScale = try resolvedScalar(sweep.options.endScale, parameters: parameters)
        guard abs(endScale - 1.0) <= tolerance.distance else {
            return nil
        }
        let distanceFraction = try resolvedScalar(sweep.options.distanceFraction, parameters: parameters)
        guard distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            return nil
        }
        guard let pathVector = try straightOpenPathVector(pathSketch, parameters: parameters) else {
            return nil
        }
        let fullDistance = pathVector.length
        guard fullDistance > tolerance.distance else {
            return nil
        }
        let direction = try pathVector.normalized(tolerance: tolerance.distance)
        let sweepDistance = fullDistance * distanceFraction
        let sweepVector = direction * sweepDistance
        let height = abs(sweepVector.dot(profile.frame.normal))
        guard height > tolerance.distance else {
            return nil
        }

        return [
            MeasurementResult.Solid.LinearDimension(kind: .sweepNormalHeight, meters: height),
            MeasurementResult.Solid.LinearDimension(kind: .sweepPathLength, meters: sweepDistance),
        ]
    }

    private func measureEvaluatedSweepSolids(
        featureID: FeatureID,
        featureName: String?,
        sourceFeatureID: FeatureID,
        sourceFeatureName: String?,
        sweep: SweepFeature,
        pathLengthMeters: Double?,
        parameters: ParameterTable,
        evaluatedDocument: EvaluatedDocument?,
        unsupportedReason: inout String?
    ) throws -> [MeasurementResult.Solid]? {
        guard sweep.options.resultKind == .solid else {
            unsupportedReason = "The sweep result kind is not solid."
            return nil
        }
        guard let evaluatedDocument else {
            unsupportedReason = "Evaluated geometry is unavailable."
            return nil
        }
        let bodyReferences = evaluatedBodyReferences(for: featureID, in: evaluatedDocument)
        guard !bodyReferences.isEmpty else {
            unsupportedReason = "The evaluated document is missing sweep generated body names."
            return nil
        }
        let distanceFraction = try resolvedScalar(sweep.options.distanceFraction, parameters: parameters)
        guard distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            unsupportedReason = "The sweep distance fraction is outside the measurable range."
            return nil
        }
        guard let pathLength = pathLengthMeters else {
            unsupportedReason = "The sweep path length could not be measured."
            return nil
        }
        var solids: [MeasurementResult.Solid] = []
        for bodyReference in bodyReferences {
            guard let body = evaluatedDocument.brep.bodies[bodyReference.bodyID],
                  body.kind == .solid else {
                unsupportedReason = "The evaluated sweep body is not a solid."
                return nil
            }
            guard let mesh = evaluatedDocument.meshes[bodyReference.bodyID] else {
                unsupportedReason = "The evaluated document is missing a sweep generated body mesh."
                return nil
            }
            let meshMeasurement = try evaluatedMeshMeasurement(mesh)
            guard let volumeCubicMeters = try evaluatedBRepVolume(
                bodyID: bodyReference.bodyID,
                in: evaluatedDocument.brep,
                unsupportedReason: &unsupportedReason
            ) else {
                return nil
            }
            guard volumeCubicMeters > tolerance.distance * tolerance.distance * tolerance.distance else {
                unsupportedReason = "An evaluated sweep solid volume is below tolerance."
                return nil
            }
            solids.append(
                MeasurementResult.Solid(
                    featureID: featureID.description,
                    featureName: featureName,
                    sourceFeatureID: sourceFeatureID.description,
                    sourceFeatureName: sourceFeatureName,
                    linearDimensions: [
                        MeasurementResult.Solid.LinearDimension(
                            kind: .sweepPathLength,
                            meters: pathLength * distanceFraction
                        ),
                    ],
                    volume: .init(value: volumeCubicMeters, method: .exactBRep),
                    surfaceArea: .init(
                        value: meshMeasurement.surfaceAreaSquareMeters,
                        method: .tessellatedMesh
                    ),
                    bounds: .init(
                        value: meshMeasurement.bounds,
                        method: .tessellatedMesh
                    )
                )
            )
        }
        return solids
    }

    private func measureEvaluatedSweepSheet(
        featureID: FeatureID,
        featureName: String?,
        sourceFeatureID: FeatureID,
        sourceFeatureName: String?,
        sweep: SweepFeature,
        pathLengthMeters: Double?,
        parameters: ParameterTable,
        evaluatedDocument: EvaluatedDocument?,
        unsupportedReason: inout String?
    ) throws -> MeasurementResult.Sheet? {
        guard sweep.options.resultKind == .sheet else {
            unsupportedReason = "The sweep result kind is not sheet."
            return nil
        }
        guard let evaluatedDocument else {
            unsupportedReason = "Evaluated geometry is unavailable."
            return nil
        }
        let bodyID = try evaluatedBodyID(for: featureID, in: evaluatedDocument)
        guard let body = evaluatedDocument.brep.bodies[bodyID],
              body.kind == .sheet else {
            unsupportedReason = "The evaluated sweep body is not a sheet."
            return nil
        }
        guard let mesh = evaluatedDocument.meshes[bodyID] else {
            unsupportedReason = "The evaluated document is missing the sweep generated body mesh."
            return nil
        }
        let distanceFraction = try resolvedScalar(sweep.options.distanceFraction, parameters: parameters)
        guard distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            unsupportedReason = "The sweep distance fraction is outside the measurable range."
            return nil
        }
        guard let pathLength = pathLengthMeters else {
            unsupportedReason = "The sweep path length could not be measured."
            return nil
        }
        let meshMeasurement = try evaluatedMeshMeasurement(mesh)
        guard meshMeasurement.surfaceAreaSquareMeters > tolerance.distance * tolerance.distance else {
            unsupportedReason = "The evaluated sweep sheet area is below tolerance."
            return nil
        }
        return MeasurementResult.Sheet(
            featureID: featureID.description,
            featureName: featureName,
            sourceFeatureID: sourceFeatureID.description,
            sourceFeatureName: sourceFeatureName,
            linearDimensions: [
                MeasurementResult.Sheet.LinearDimension(
                    kind: .sweepPathLength,
                    meters: pathLength * distanceFraction
                ),
            ],
            surfaceArea: .init(
                value: meshMeasurement.surfaceAreaSquareMeters,
                method: .tessellatedMesh
            ),
            bounds: .init(value: meshMeasurement.bounds, method: .tessellatedMesh)
        )
    }

    private func measureEvaluatedSheet(
        featureID: FeatureID,
        featureName: String?,
        sourceFeatureID: FeatureID,
        sourceFeatureName: String?,
        evaluatedDocument: EvaluatedDocument?,
        unsupportedReason: inout String?
    ) throws -> MeasurementResult.Sheet? {
        guard let evaluatedDocument else {
            unsupportedReason = "Evaluated geometry is unavailable."
            return nil
        }
        let bodyID = try evaluatedBodyID(for: featureID, in: evaluatedDocument)
        guard let body = evaluatedDocument.brep.bodies[bodyID],
              body.kind == .sheet else {
            unsupportedReason = "The evaluated body is not a sheet."
            return nil
        }
        guard let mesh = evaluatedDocument.meshes[bodyID] else {
            unsupportedReason = "The evaluated document is missing the generated body mesh."
            return nil
        }
        let meshMeasurement = try evaluatedMeshMeasurement(mesh)
        guard meshMeasurement.surfaceAreaSquareMeters > tolerance.distance * tolerance.distance else {
            unsupportedReason = "The evaluated sheet area is below tolerance."
            return nil
        }
        return MeasurementResult.Sheet(
            featureID: featureID.description,
            featureName: featureName,
            sourceFeatureID: sourceFeatureID.description,
            sourceFeatureName: sourceFeatureName,
            linearDimensions: [],
            surfaceArea: .init(
                value: meshMeasurement.surfaceAreaSquareMeters,
                method: .tessellatedMesh
            ),
            bounds: .init(value: meshMeasurement.bounds, method: .tessellatedMesh)
        )
    }

    private func measureEvaluatedSolid(
        featureID: FeatureID,
        featureName: String?,
        sourceFeatureID: FeatureID,
        sourceFeatureName: String?,
        evaluatedDocument: EvaluatedDocument?,
        unsupportedReason: inout String?
    ) throws -> MeasurementResult.Solid? {
        guard let evaluatedDocument else {
            unsupportedReason = "Evaluated geometry is unavailable."
            return nil
        }
        let bodyID = try evaluatedBodyID(for: featureID, in: evaluatedDocument)
        guard let mesh = evaluatedDocument.meshes[bodyID] else {
            unsupportedReason = "The evaluated document is missing the generated body mesh."
            return nil
        }
        let meshMeasurement = try evaluatedMeshMeasurement(mesh)
        guard let volumeCubicMeters = try evaluatedBRepVolume(
            bodyID: bodyID,
            in: evaluatedDocument.brep,
            unsupportedReason: &unsupportedReason
        ) else {
            return nil
        }
        guard volumeCubicMeters > tolerance.distance * tolerance.distance * tolerance.distance else {
            unsupportedReason = "The evaluated solid volume is below tolerance."
            return nil
        }
        return MeasurementResult.Solid(
            featureID: featureID.description,
            featureName: featureName,
            sourceFeatureID: sourceFeatureID.description,
            sourceFeatureName: sourceFeatureName,
            linearDimensions: [],
            volume: .init(value: volumeCubicMeters, method: .exactBRep),
            surfaceArea: .init(
                value: meshMeasurement.surfaceAreaSquareMeters,
                method: .tessellatedMesh
            ),
            bounds: .init(
                value: meshMeasurement.bounds,
                method: .tessellatedMesh
            )
        )
    }

    private func measureEvaluatedBodySolids(
        featureID: FeatureID,
        featureName: String?,
        sourceFeatureID: FeatureID,
        sourceFeatureName: String?,
        evaluatedDocument: EvaluatedDocument?,
        unsupportedReason: inout String?
    ) throws -> [MeasurementResult.Solid]? {
        guard let evaluatedDocument else {
            unsupportedReason = "Evaluated geometry is unavailable."
            return nil
        }
        let bodyReferences = evaluatedBodyReferences(
            for: featureID,
            in: evaluatedDocument
        )
        guard !bodyReferences.isEmpty else {
            unsupportedReason = "The evaluated document is missing generated body names."
            return nil
        }
        var solids: [MeasurementResult.Solid] = []
        solids.reserveCapacity(bodyReferences.count)
        for bodyReference in bodyReferences {
            guard let body = evaluatedDocument.brep.bodies[bodyReference.bodyID],
                  body.kind == .solid else {
                unsupportedReason = "An evaluated body output is not a solid."
                return nil
            }
            guard let mesh = evaluatedDocument.meshes[bodyReference.bodyID] else {
                unsupportedReason = "The evaluated document is missing a generated body mesh."
                return nil
            }
            let meshMeasurement = try evaluatedMeshMeasurement(mesh)
            guard let volumeCubicMeters = try evaluatedBRepVolume(
                bodyID: bodyReference.bodyID,
                in: evaluatedDocument.brep,
                unsupportedReason: &unsupportedReason
            ) else {
                return nil
            }
            guard volumeCubicMeters > tolerance.distance * tolerance.distance * tolerance.distance else {
                unsupportedReason = "An evaluated solid volume is below tolerance."
                return nil
            }
            solids.append(MeasurementResult.Solid(
                featureID: featureID.description,
                featureName: featureName,
                sourceFeatureID: sourceFeatureID.description,
                sourceFeatureName: sourceFeatureName,
                linearDimensions: [],
                volume: .init(value: volumeCubicMeters, method: .exactBRep),
                surfaceArea: .init(
                    value: meshMeasurement.surfaceAreaSquareMeters,
                    method: .tessellatedMesh
                ),
                bounds: .init(
                    value: meshMeasurement.bounds,
                    method: .tessellatedMesh
                )
            ))
        }
        return solids
    }

    private func evaluatedBodyID(
        for featureID: FeatureID,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> BodyID {
        try evaluatedPrimaryBodyReference(
            for: featureID,
            in: evaluatedDocument
        ).bodyID
    }

    private func evaluatedPrimaryBodyReference(
        for featureID: FeatureID,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> EvaluatedBodyReference {
        let bodyIdentity = evaluatedPrimaryBodyIdentity(for: featureID)
        let topologyReference = try evaluatedDocument.subshapes.reference(for: bodyIdentity)
        guard case .body(let bodyID) = topologyReference else {
            throw KernelError(
                phase: .evaluation,
                code: .topologyFailure,
                featureID: featureID,
                subshapeID: bodyIdentity,
                tolerance: nil,
                message: "The generated body identity resolves to non-body topology."
            )
        }
        return EvaluatedBodyReference(subshapeID: bodyIdentity, bodyID: bodyID)
    }

    private func evaluatedBodyReferences(
        for featureID: FeatureID,
        in evaluatedDocument: EvaluatedDocument
    ) -> [EvaluatedBodyReference] {
        let primaryIdentity = evaluatedPrimaryBodyIdentity(for: featureID)
        let candidates: [EvaluatedBodyReference] = evaluatedDocument.subshapes.entries.compactMap { entry in
            guard entry.key.featureID == featureID,
                  case .body(let bodyID) = entry.value else {
                return nil
            }
            return EvaluatedBodyReference(subshapeID: entry.key, bodyID: bodyID)
        }.sorted { lhs, rhs in
            if lhs.subshapeID == primaryIdentity {
                return true
            }
            if rhs.subshapeID == primaryIdentity {
                return false
            }
            return GeneratedSubshapeIdentity.areInIncreasingOrder(lhs.subshapeID, rhs.subshapeID)
        }
        var includedBodyIDs: Set<BodyID> = []
        return candidates.filter { reference in
            includedBodyIDs.insert(reference.bodyID).inserted
        }
    }

    private func evaluatedPrimaryBodyIdentity(for featureID: FeatureID) -> SubshapeID {
        SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
    }


    private func evaluatedMeshMeasurement(_ mesh: Mesh, transform: Transform3D = .identity) throws -> EvaluatedMeshMeasurement {
        guard !mesh.positions.isEmpty,
              !mesh.indices.isEmpty,
              mesh.indices.count.isMultiple(of: 3) else {
            throw EditorError(
                code: .commandFailed,
                message: "Measurement expected a non-empty triangle mesh."
            )
        }
        var bounds = MeasurementBoundsAccumulator()
        for point in mesh.positions {
            bounds.include(try transform.applied(to: point))
        }
        guard let measuredBounds = bounds.bounds else {
            throw EditorError(code: .commandFailed, message: "Measurement could not resolve finite mesh bounds.")
        }

        var surfaceArea = 0.0
        var index = 0
        while index + 2 < mesh.indices.count {
            let firstIndex = Int(mesh.indices[index])
            let secondIndex = Int(mesh.indices[index + 1])
            let thirdIndex = Int(mesh.indices[index + 2])
            guard firstIndex < mesh.positions.count,
                  secondIndex < mesh.positions.count,
                  thirdIndex < mesh.positions.count else {
                throw EditorError(
                    code: .commandFailed,
                    message: "Measurement encountered a mesh index outside the position table."
                )
            }
            let first = try transform.applied(to: mesh.positions[firstIndex])
            let second = try transform.applied(to: mesh.positions[secondIndex])
            let third = try transform.applied(to: mesh.positions[thirdIndex])
            let triangleNormal = (second - first).cross(third - first)
            surfaceArea += triangleNormal.length * 0.5
            index += 3
        }

        guard surfaceArea.isFinite else {
            throw EditorError(code: .commandFailed, message: "Placed mesh area is not representable.")
        }
        return EvaluatedMeshMeasurement(
            surfaceAreaSquareMeters: surfaceArea,
            bounds: measuredBounds
        )
    }

    private func evaluatedBRepVolume(
        bodyID: BodyID,
        in model: BRepModel,
        unsupportedReason: inout String?
    ) throws -> Double? {
        do {
            return try model.volume(of: bodyID, tolerance: tolerance)
        } catch let error as KernelError where error.code == .unsupportedCapability {
            unsupportedReason = "Exact B-rep volume is unavailable: \(error.message)"
            return nil
        }
    }

    private func boundsForSketch(
        _ sketch: Sketch,
        parameters: ParameterTable,
        transform: Transform3D = .identity
    ) throws -> MeasurementResult.Bounds? {
        let frame = try placedFrame(for: sketch.plane, transform: transform)
        var bounds = MeasurementBoundsAccumulator()
        for entity in sketch.entities.values {
            switch entity {
            case .point(let point):
                bounds.include(frame.map(try resolvedPoint(point, parameters: parameters)))
            case .line(let line):
                bounds.include(frame.map(try resolvedPoint(line.start, parameters: parameters)))
                bounds.include(frame.map(try resolvedPoint(line.end, parameters: parameters)))
            case .circle(let circle):
                let center = frame.map(try resolvedPoint(circle.center, parameters: parameters))
                let radius = try resolvedLength(circle.radius, parameters: parameters)
                bounds.include(circleBounds(center: center, radius: radius, frame: frame))
            case .arc(let arc):
                for point in try arcBoundsPoints(arc, parameters: parameters, frame: frame) {
                    bounds.include(frame.map(point))
                }
            case .spline(let spline):
                for point in try splineSamplePoints(spline, parameters: parameters) {
                    bounds.include(frame.map(point))
                }
            }
        }
        return bounds.bounds
    }

    private func boundsForEvaluatedCurves(_ curves: [EvaluatedCurve]?) -> MeasurementResult.Bounds? {
        guard let curves else {
            return nil
        }
        var bounds = MeasurementBoundsAccumulator()
        for curve in curves {
            for point in curve.points {
                bounds.include(point)
            }
        }
        return bounds.bounds
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        parameters: ParameterTable
    ) throws -> MeasurementPoint2D {
        MeasurementPoint2D(
            x: try resolvedLength(point.x, parameters: parameters),
            y: try resolvedLength(point.y, parameters: parameters)
        )
    }

    private func resolvedLength(
        _ expression: CADExpression,
        parameters: ParameterTable
    ) throws -> Double {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw EditorError(
                code: .commandFailed,
                message: "Measurement expected a length expression."
            )
        }
        return quantity.value
    }

    private func resolvedAngle(
        _ expression: CADExpression,
        parameters: ParameterTable
    ) throws -> Double {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == .angle else {
            throw EditorError(
                code: .commandFailed,
                message: "Measurement expected an angle expression."
            )
        }
        return quantity.value
    }

    private func resolvedScalar(
        _ expression: CADExpression,
        parameters: ParameterTable
    ) throws -> Double {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == .scalar else {
            throw EditorError(
                code: .commandFailed,
                message: "Measurement expected a scalar expression."
            )
        }
        return quantity.value
    }

    private func straightOpenPathVector(
        _ sketch: Sketch,
        parameters: ParameterTable
    ) throws -> Vector3D? {
        let lines = sketch.entities.values.compactMap(\.line)
        guard lines.count == 1,
              sketch.entities.count == 1,
              let line = lines.first else {
            return nil
        }
        let frame = try planeFrame(for: sketch.plane)
        let start = frame.map(try resolvedPoint(line.start, parameters: parameters))
        let end = frame.map(try resolvedPoint(line.end, parameters: parameters))
        return end - start
    }

    private func pathLength(
        featureID: FeatureID,
        sketch: Sketch?,
        parameters: ParameterTable,
        evaluatedDocument: EvaluatedDocument?
    ) throws -> Double? {
        if let sketch {
            return try pathLength(
                sketch,
                sourceFeatureID: featureID,
                parameters: parameters
            )
        }
        guard let curves = evaluatedDocument?.curves[featureID] else {
            return nil
        }
        return try pathLength(curves)
    }

    private func pathLength(_ curves: [EvaluatedCurve]) throws -> Double? {
        guard curves.isEmpty == false else {
            return nil
        }
        let evaluator = EvaluatedCurvePathEvaluator(tolerance: tolerance)
        let totalLength = try evaluator.length(of: curves)
        return totalLength > tolerance.distance ? totalLength : nil
    }

    private func pathLength(
        _ sketch: Sketch,
        sourceFeatureID: FeatureID,
        parameters: ParameterTable
    ) throws -> Double? {
        let resolvedParameters = try ParameterResolver().resolve(parameters)
        let curves = try SketchCurveExtractor(tolerance: tolerance).extractCurves(
            from: sketch,
            sourceFeatureID: sourceFeatureID,
            parameters: resolvedParameters
        )
        return try pathLength(curves)
    }

    private func resolvedProfileSegments(
        in sketch: Sketch,
        parameters: ParameterTable
    ) throws -> [ResolvedProfileSegment] {
        var segments: [ResolvedProfileSegment] = []
        for entity in sketch.entities.values {
            switch entity {
            case .line(let line):
                segments.append(ResolvedProfileSegment(
                    kind: .line,
                    points: [
                        try resolvedPoint(line.start, parameters: parameters),
                        try resolvedPoint(line.end, parameters: parameters),
                    ]
                ))
            case .arc(let arc):
                segments.append(try resolvedArcSegment(arc, parameters: parameters))
            case .spline(let spline):
                let points = try splineSamplePoints(spline, parameters: parameters)
                if spline.isClosed {
                    guard let first = points.first,
                          let last = points.last,
                          isClose(first, last) else {
                        return []
                    }
                }
                guard points.count >= 2 else {
                    return []
                }
                segments.append(ResolvedProfileSegment(kind: .spline, points: points))
            case .point, .circle:
                return []
            }
        }
        return segments
    }

    private func splineSamplePoints(
        _ spline: SketchSpline,
        parameters: ParameterTable
    ) throws -> [MeasurementPoint2D] {
        guard spline.controlPoints.count >= 4,
              (spline.controlPoints.count - 1).isMultiple(of: 3) else {
            return []
        }
        let controlPoints = try spline.controlPoints.map { point in
            try resolvedPoint(point, parameters: parameters)
        }
        let kernelControlPoints: [CADCore.Point2D] = controlPoints.map { point in
            CADCore.Point2D(x: point.x, y: point.y)
        }
        return try splineTessellator.points(for: kernelControlPoints).map { point in
            MeasurementPoint2D(x: point.x, y: point.y)
        }
    }

    private func resolvedArcSegment(
        _ arc: SketchArc,
        parameters: ParameterTable
    ) throws -> ResolvedProfileSegment {
        let center = try resolvedPoint(arc.center, parameters: parameters)
        let radius = try resolvedLength(arc.radius, parameters: parameters)
        let startAngle = try resolvedAngle(arc.startAngle, parameters: parameters)
        let span = normalizedAngleSpan(
            startAngle: startAngle,
            endAngle: try resolvedAngle(arc.endAngle, parameters: parameters)
        )
        guard radius > tolerance.distance, span > tolerance.angle else {
            return ResolvedProfileSegment(kind: .arc, points: [])
        }
        let fullCircleSegmentCount = 64
        let segmentCount = max(
            Int(ceil(Double(fullCircleSegmentCount) * span / (Double.pi * 2.0))),
            2
        )
        let points = (0 ... segmentCount).map { index in
            let ratio = Double(index) / Double(segmentCount)
            let angle = startAngle + span * ratio
            return MeasurementPoint2D(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
        return ResolvedProfileSegment(kind: .arc, points: points)
    }

    private func orderedClosedLoop(from segments: [ResolvedProfileSegment]) -> [MeasurementPoint2D]? {
        var remaining = segments.filter { $0.points.count >= 2 }
        guard let first = remaining.first else {
            return nil
        }
        remaining.removeFirst()
        var points = first.points
        guard let start = points.first,
              let firstEnd = points.last else {
            return nil
        }
        var current = firstEnd

        while !remaining.isEmpty {
            guard let index = remaining.firstIndex(where: { segment in
                isClose(segment.start, current) || isClose(segment.end, current)
            }) else {
                return nil
            }
            let segment = remaining.remove(at: index)
            let segmentPoints = isClose(segment.start, current)
                ? segment.points
                : Array(segment.points.reversed())
            guard let segmentEnd = segmentPoints.last else {
                return nil
            }
            current = segmentEnd
            points.append(contentsOf: segmentPoints.dropFirst())
        }

        guard isClose(current, start) else {
            return nil
        }
        if let last = points.last, isClose(last, start) {
            points.removeLast()
        }
        return points.count >= 3 ? points : nil
    }

    private func arcBoundsPoints(
        _ arc: SketchArc,
        parameters: ParameterTable,
        frame: PlaneFrame
    ) throws -> [MeasurementPoint2D] {
        let center = try resolvedPoint(arc.center, parameters: parameters)
        let radius = try resolvedLength(arc.radius, parameters: parameters)
        let startAngle = try resolvedAngle(arc.startAngle, parameters: parameters)
        let span = normalizedAngleSpan(
            startAngle: startAngle,
            endAngle: try resolvedAngle(arc.endAngle, parameters: parameters)
        )
        var angles = [startAngle, startAngle + span]
        for (u, v) in [(frame.u.x, frame.v.x), (frame.u.y, frame.v.y), (frame.u.z, frame.v.z)] {
            let angle = atan2(v, u)
            for extremum in [angle, angle + Double.pi] {
                var offset = (extremum - startAngle).truncatingRemainder(dividingBy: 2 * Double.pi)
                if offset < 0 { offset += 2 * Double.pi }
                if offset <= span { angles.append(startAngle + offset) }
            }
        }
        return angles.map { angle in
            MeasurementPoint2D(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private func arcSamplingAngles(startAngle: Double, span: Double) -> [Double] {
        let fullCircle = Double.pi * 2.0
        var angles = [startAngle, startAngle + span]
        let cardinalAngles = [0.0, Double.pi / 2.0, Double.pi, Double.pi * 1.5, fullCircle]
        for baseAngle in cardinalAngles {
            var angle = baseAngle
            while angle < startAngle - tolerance.angle {
                angle += fullCircle
            }
            if angle <= startAngle + span + tolerance.angle {
                angles.append(angle)
            }
        }
        return angles
    }

    private func normalizedAngleSpan(startAngle: Double, endAngle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= tolerance.angle {
            span += fullCircle
        }
        while span > fullCircle + tolerance.angle {
            span -= fullCircle
        }
        return min(span, fullCircle)
    }

    private func polygonArea(_ points: [MeasurementPoint2D]) -> Double {
        guard let origin = points.first else {
            return 0.0
        }
        var twiceArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            // Rebase to a local origin before the shoelace products so the area
            // stays exact even when the polygon sits far from the world origin.
            // The raw formula multiplies coordinates near 1e12, whose products
            // (~1e24, ulp ~1.3e8) cancel catastrophically and collapse the true
            // area to zero for site-planning-scale models. Area is translation
            // invariant, so subtracting the first vertex is exact.
            let currentX = current.x - origin.x
            let currentY = current.y - origin.y
            let nextX = next.x - origin.x
            let nextY = next.y - origin.y
            twiceArea += currentX * nextY - nextX * currentY
        }
        return twiceArea / 2.0
    }

    private func isClose(_ lhs: MeasurementPoint2D, _ rhs: MeasurementPoint2D) -> Bool {
        guard lhs.x.isFinite,
              lhs.y.isFinite,
              rhs.x.isFinite,
              rhs.y.isFinite else {
            return false
        }
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return hypot(dx, dy) <= connectionTolerance(between: lhs, and: rhs)
    }

    private func connectionTolerance(
        between lhs: MeasurementPoint2D,
        and rhs: MeasurementPoint2D
    ) -> Double {
        let xResolution = coordinateResolutionTolerance(lhs.x, rhs.x)
        let yResolution = coordinateResolutionTolerance(lhs.y, rhs.y)
        // Far-origin endpoints can only be distinguished down to the local
        // coordinate ULP, which may exceed the modeling distance tolerance.
        return tolerance.distance + hypot(xResolution, yResolution)
    }

    private func coordinateResolutionTolerance(_ lhs: Double, _ rhs: Double) -> Double {
        2.0 * max(
            abs(lhs.nextUp - lhs),
            abs(lhs - lhs.nextDown),
            abs(rhs.nextUp - rhs),
            abs(rhs - rhs.nextDown)
        )
    }

    private func planeFrame(for plane: SketchPlane) throws -> PlaneFrame {
        switch plane {
        case .xy:
            return PlaneFrame(
                origin: .origin,
                normal: .unitZ,
                u: .unitX,
                v: .unitY
            )
        case .yz:
            return PlaneFrame(
                origin: .origin,
                normal: .unitX,
                u: .unitY,
                v: .unitZ
            )
        case .zx:
            return PlaneFrame(
                origin: .origin,
                normal: .unitY,
                u: .unitZ,
                v: .unitX
            )
        case .plane(let plane):
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
            let v = normal.cross(u)
            return PlaneFrame(
                origin: plane.origin,
                normal: normal,
                u: u,
                v: v
            )
        }
    }

    private func directionVector(
        for direction: ExtrudeDirection,
        frame: PlaneFrame
    ) throws -> Vector3D {
        switch direction {
        case .normal, .symmetric:
            return frame.normal
        case .vector(let vector):
            return try vector.normalized(tolerance: tolerance.distance)
        }
    }

    private func circleBounds(
        center: Point3D,
        radius: Double,
        frame: PlaneFrame
    ) -> MeasurementResult.Bounds {
        let xExtent = radius * hypot(frame.u.x, frame.v.x)
        let yExtent = radius * hypot(frame.u.y, frame.v.y)
        let zExtent = radius * hypot(frame.u.z, frame.v.z)
        return MeasurementResult.Bounds(
            minX: center.x - xExtent,
            minY: center.y - yExtent,
            minZ: center.z - zExtent,
            maxX: center.x + xExtent,
            maxY: center.y + yExtent,
            maxZ: center.z + zExtent
        )
    }
}

private struct MeasuredProfile {
    var result: MeasurementResult.Profile
    var plane: SketchPlane
    var frame: PlaneFrame
    var baseBounds: MeasurementResult.Bounds
}

private struct EvaluatedMeshMeasurement {
    var surfaceAreaSquareMeters: Double
    var bounds: MeasurementResult.Bounds
}

private struct EvaluatedBodyReference {
    var subshapeID: SubshapeID
    var bodyID: BodyID
}

private struct PlaneFrame {
    var origin: Point3D
    var normal: Vector3D
    var u: Vector3D
    var v: Vector3D

    func map(_ point: MeasurementPoint2D) -> Point3D {
        origin + (u * point.x) + (v * point.y)
    }
}

private enum ResolvedProfileSegmentKind: Equatable {
    case line
    case arc
    case spline
}

private struct ResolvedProfileSegment {
    var kind: ResolvedProfileSegmentKind
    var points: [MeasurementPoint2D]

    var start: MeasurementPoint2D {
        points[0]
    }

    var end: MeasurementPoint2D {
        points[points.count - 1]
    }
}

private struct MeasurementPoint2D: Equatable {
    var x: Double
    var y: Double
}

private extension MeasurementResult.Bounds {
    func translated(by vector: Vector3D) -> MeasurementResult.Bounds {
        MeasurementResult.Bounds(
            minX: minX + vector.x,
            minY: minY + vector.y,
            minZ: minZ + vector.z,
            maxX: maxX + vector.x,
            maxY: maxY + vector.y,
            maxZ: maxZ + vector.z
        )
    }
}

private extension SketchEntity {
    var line: SketchLine? {
        if case .line(let line) = self {
            return line
        }
        return nil
    }

    var circle: SketchCircle? {
        if case .circle(let circle) = self {
            return circle
        }
        return nil
    }
}
