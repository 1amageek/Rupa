import Foundation
import SwiftCAD

public struct MeasurementService {
    private let tolerance: ModelingTolerance
    private let splineTessellator: CubicBezierSplineTessellator

    public init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
        self.splineTessellator = CubicBezierSplineTessellator(tolerance: tolerance)
    }

    public func measure(document: DesignDocument) throws -> MeasurementResult {
        try measure(
            document: document,
            selectedFeatureIDs: nil,
            scope: .document
        )
    }

    public func measure(
        document: DesignDocument,
        selection: SelectionModel
    ) throws -> MeasurementResult {
        guard !selection.selectedSceneNodeIDs.isEmpty else {
            return try measure(document: document)
        }
        let selectedFeatureIDs = Set(
            selection.selectedSceneNodeReferences(in: document).compactMap(\.featureID)
        )
        return try measure(
            document: document,
            selectedFeatureIDs: selectedFeatureIDs,
            scope: .selection
        )
    }

    private func measure(
        document: DesignDocument,
        selectedFeatureIDs: Set<FeatureID>?,
        scope: MeasurementResult.Scope
    ) throws -> MeasurementResult {
        var counts = MeasurementResult.Counts()
        var profiles: [MeasurementResult.Profile] = []
        var solids: [MeasurementResult.Solid] = []
        var totals = MeasurementResult.Totals()
        var bounds = BoundsAccumulator()
        var profileCache: [FeatureID: MeasuredProfile] = [:]
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
                cachedEvaluatedDocument = try CADPipeline
                    .modelingDefault(for: document)
                    .evaluate(document.cadDocument)
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
            totals.profileAreaSquareMeters += profile.result.areaSquareMeters
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
            }
            if let profile {
                includeProfile(profile, featureID: featureID)
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
            case .extrude(let extrude):
                guard !isSupersededInDocumentScope(featureID) else {
                    continue
                }
                guard shouldMeasure(featureID) else {
                    continue
                }
                includedSourceFeatureIDs.insert(featureID)
                guard let sourceNode = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
                      case .sketch(let sourceSketch) = sourceNode.operation else {
                    diagnostics.append(
                        EditorDiagnostic(
                            severity: .warning,
                            message: "Measurement skipped an extrude feature with an unresolved profile reference."
                        )
                    )
                    continue
                }
                let sourceSketchBounds = try boundsForSketch(
                    sourceSketch,
                    parameters: document.cadDocument.parameters
                )
                let profile = try profileCache[extrude.profile.featureID] ?? measureProfile(
                    featureID: extrude.profile.featureID,
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
                    continue
                }
                profileCache[extrude.profile.featureID] = profile
                includeSketch(
                    featureID: extrude.profile.featureID,
                    sketch: sourceSketch,
                    sketchBounds: sourceSketchBounds,
                    profile: profile
                )
                let solid = try measureSolid(
                    featureID: featureID,
                    featureName: node.name,
                    sourceFeatureID: extrude.profile.featureID,
                    sourceFeatureName: sourceNode.name,
                    profile: profile,
                    extrude: extrude,
                    parameters: document.cadDocument.parameters
                )
                counts.solids += 1
                solids.append(solid)
                totals.solidVolumeCubicMeters += solid.volumeCubicMeters
                bounds.include(solid.bounds)
            case .sweep(let sweep):
                guard !isSupersededInDocumentScope(featureID) else {
                    continue
                }
                guard shouldMeasure(featureID) else {
                    continue
                }
                includedSourceFeatureIDs.insert(featureID)
                guard let profileReference = sweep.profiles.first,
                      let sourceNode = document.cadDocument.designGraph.nodes[profileReference.featureID],
                      case .sketch(let sourceSketch) = sourceNode.operation,
                      let pathNode = document.cadDocument.designGraph.nodes[sweep.path.featureID],
                      case .sketch(let pathSketch) = pathNode.operation else {
                    diagnostics.append(
                        EditorDiagnostic(
                            severity: .warning,
                            message: "Measurement skipped a sweep feature with unresolved profile or path references."
                        )
                    )
                    continue
                }
                let sourceSketchBounds = try boundsForSketch(
                    sourceSketch,
                    parameters: document.cadDocument.parameters
                )
                let pathSketchBounds = try boundsForSketch(
                    pathSketch,
                    parameters: document.cadDocument.parameters
                )
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
                            message: "Measurement skipped a sweep feature with an unsupported profile."
                        )
                    )
                    continue
                }
                profileCache[profileReference.featureID] = profile
                includeSketch(
                    featureID: profileReference.featureID,
                    sketch: sourceSketch,
                    sketchBounds: sourceSketchBounds,
                    profile: profile
                )
                includeSketch(
                    featureID: sweep.path.featureID,
                    sketch: pathSketch,
                    sketchBounds: pathSketchBounds,
                    profile: nil
                )
                for guide in sweep.guides {
                    guard let guideNode = document.cadDocument.designGraph.nodes[guide.featureID],
                          case .sketch(let guideSketch) = guideNode.operation else {
                        diagnostics.append(
                            EditorDiagnostic(
                                severity: .warning,
                                message: "Measurement skipped a sweep guide with an unresolved sketch reference."
                            )
                        )
                        continue
                    }
                    let guideSketchBounds = try boundsForSketch(
                        guideSketch,
                        parameters: document.cadDocument.parameters
                    )
                    includeSketch(
                        featureID: guide.featureID,
                        sketch: guideSketch,
                        sketchBounds: guideSketchBounds,
                        profile: nil
                    )
                }
                let straightSolid = try measureStraightSweepSolid(
                    featureID: featureID,
                    featureName: node.name,
                    sourceFeatureID: profileReference.featureID,
                    sourceFeatureName: sourceNode.name,
                    profile: profile,
                    sweep: sweep,
                    pathSketch: pathSketch,
                    parameters: document.cadDocument.parameters
                )
                var evaluatedSweepSkipReason: String?
                let solid = try straightSolid ?? measureEvaluatedSweepSolid(
                        featureID: featureID,
                        featureName: node.name,
                        sourceFeatureID: profileReference.featureID,
                        sourceFeatureName: sourceNode.name,
                        sweep: sweep,
                        pathSketch: pathSketch,
                        parameters: document.cadDocument.parameters,
                        evaluatedDocument: evaluatedDocument(),
                        unsupportedReason: &evaluatedSweepSkipReason
                    )
                guard let solid else {
                    let detail = evaluatedSweepSkipReason.map { " \($0)" } ?? ""
                    diagnostics.append(
                        EditorDiagnostic(
                            severity: .info,
                            message: "Measurement skipped a sweep feature outside the supported solid evaluation subset.\(detail)"
                        )
                    )
                    continue
                }
                counts.solids += 1
                solids.append(solid)
                totals.solidVolumeCubicMeters += solid.volumeCubicMeters
                bounds.include(solid.bounds)
            case .polySpline(let polySpline):
                guard !isSupersededInDocumentScope(featureID) else {
                    continue
                }
                guard shouldMeasure(featureID) else {
                    continue
                }
                includedSourceFeatureIDs.insert(featureID)
                for point in polySpline.sourceMesh.positions {
                    bounds.include(point)
                }
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .info,
                        message: "Measurement included PolySpline source bounds; B-spline sheet area and curvature measurement remain unsupported."
                    )
                )
            case .faceLoopOffset:
                guard !isSupersededInDocumentScope(featureID) else {
                    continue
                }
                guard shouldMeasure(featureID) else {
                    continue
                }
                includedSourceFeatureIDs.insert(featureID)
                guard case .faceLoopOffset(let faceLoopOffset) = node.operation else {
                    continue
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
                    continue
                }
                counts.solids += 1
                solids.append(solid)
                totals.solidVolumeCubicMeters += solid.volumeCubicMeters
                bounds.include(solid.bounds)
            case .edgeOffset:
                guard !isSupersededInDocumentScope(featureID) else {
                    continue
                }
                guard shouldMeasure(featureID) else {
                    continue
                }
                includedSourceFeatureIDs.insert(featureID)
                guard case .edgeOffset(let edgeOffset) = node.operation else {
                    continue
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
                    continue
                }
                counts.solids += 1
                solids.append(solid)
                totals.solidVolumeCubicMeters += solid.volumeCubicMeters
                bounds.include(solid.bounds)
            case .faceKnife(let faceKnife):
                guard !isSupersededInDocumentScope(featureID) else {
                    continue
                }
                guard shouldMeasure(featureID) else {
                    continue
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
                    continue
                }
                counts.solids += 1
                solids.append(solid)
                totals.solidVolumeCubicMeters += solid.volumeCubicMeters
                bounds.include(solid.bounds)
            case .bridgeCurve:
                continue
            case .curveEdit:
                continue
            case .curveOffset:
                continue
            case .curveTrim:
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

        counts.profiles = profiles.count
        return MeasurementResult(
            scope: scope,
            displayUnit: document.displayUnit,
            counts: counts,
            bounds: bounds.bounds,
            totals: totals,
            profiles: profiles,
            solids: solids,
            diagnostics: diagnostics
        )
    }

    private func bodyFeatureIDsSupersededByDirectEdits(in document: CADDocument) -> Set<FeatureID> {
        var result: Set<FeatureID> = []
        for featureID in document.designGraph.order {
            guard let node = document.designGraph.nodes[featureID],
                  !node.isSuppressed else {
                continue
            }
            if let supersededFeatureID = node.operation.supersededBodyFeatureID {
                result.insert(supersededFeatureID)
            }
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
                areaSquareMeters: Double.pi * radius * radius,
                bounds: bounds
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
        var loopBounds = BoundsAccumulator()
        for point in loop {
            loopBounds.include(frame.map(point))
        }
        guard let bounds = loopBounds.bounds else {
            return nil
        }
        let result = MeasurementResult.Profile(
            featureID: featureID.description,
            featureName: featureName,
            kind: segments.contains { $0.kind != .line } ? .curveLoop : .lineLoop,
            areaSquareMeters: area,
            bounds: bounds
        )
        return MeasuredProfile(
            result: result,
            plane: sketch.plane,
            frame: frame,
            baseBounds: bounds
        )
    }

    private func measureSolid(
        featureID: FeatureID,
        featureName: String?,
        sourceFeatureID: FeatureID,
        sourceFeatureName: String?,
        profile: MeasuredProfile,
        extrude: ExtrudeFeature,
        parameters: ParameterTable
    ) throws -> MeasurementResult.Solid {
        let distance = try resolvedLength(extrude.distance, parameters: parameters)
        let extrusionDirection = try directionVector(
            for: extrude.direction,
            frame: profile.frame
        )
        let normalComponent = extrusionDirection.dot(profile.frame.normal)
        guard abs(normalComponent) > tolerance.angle else {
            throw EditorError(
                code: .commandFailed,
                message: "Measurement cannot compute volume for an extrude direction parallel to the profile plane."
            )
        }

        let bottomOffset: Vector3D
        let topOffset: Vector3D
        switch extrude.direction {
        case .symmetric:
            bottomOffset = extrusionDirection * (-distance / 2.0)
            topOffset = extrusionDirection * (distance / 2.0)
        case .normal, .vector:
            bottomOffset = .zero
            topOffset = extrusionDirection * distance
        }

        var bounds = BoundsAccumulator()
        bounds.include(profile.baseBounds.translated(by: bottomOffset))
        bounds.include(profile.baseBounds.translated(by: topOffset))
        guard let solidBounds = bounds.bounds else {
            throw EditorError(
                code: .commandFailed,
                message: "Measurement could not compute solid bounds."
            )
        }

        let height = abs(distance * normalComponent)
        return MeasurementResult.Solid(
            featureID: featureID.description,
            featureName: featureName,
            sourceFeatureID: sourceFeatureID.description,
            sourceFeatureName: sourceFeatureName,
            linearDimensions: [
                MeasurementResult.Solid.LinearDimension(
                    kind: .extrusionHeight,
                    meters: height
                ),
            ],
            volumeCubicMeters: profile.result.areaSquareMeters * height,
            bounds: solidBounds
        )
    }

    private func measureStraightSweepSolid(
        featureID: FeatureID,
        featureName: String?,
        sourceFeatureID: FeatureID,
        sourceFeatureName: String?,
        profile: MeasuredProfile,
        sweep: SweepFeature,
        pathSketch: Sketch,
        parameters: ParameterTable
    ) throws -> MeasurementResult.Solid? {
        guard sweep.profiles.count == 1,
              sweep.guides.isEmpty,
              sweep.options.resultKind == .solid,
              sweep.options.booleanOperation == .newBody,
              sweep.options.keepTools == false else {
            return nil
        }
        let twistAngle = try resolvedAngle(sweep.options.twistAngle, parameters: parameters)
        guard abs(twistAngle) <= tolerance.angle else {
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

        var bounds = BoundsAccumulator()
        bounds.include(profile.baseBounds)
        bounds.include(profile.baseBounds.translated(by: sweepVector))
        guard let solidBounds = bounds.bounds else {
            throw EditorError(
                code: .commandFailed,
                message: "Measurement could not compute sweep solid bounds."
            )
        }
        return MeasurementResult.Solid(
            featureID: featureID.description,
            featureName: featureName,
            sourceFeatureID: sourceFeatureID.description,
            sourceFeatureName: sourceFeatureName,
            linearDimensions: [
                MeasurementResult.Solid.LinearDimension(
                    kind: .sweepNormalHeight,
                    meters: height
                ),
                MeasurementResult.Solid.LinearDimension(
                    kind: .sweepPathLength,
                    meters: sweepDistance
                ),
            ],
            volumeCubicMeters: profile.result.areaSquareMeters * height,
            bounds: solidBounds
        )
    }

    private func measureEvaluatedSweepSolid(
        featureID: FeatureID,
        featureName: String?,
        sourceFeatureID: FeatureID,
        sourceFeatureName: String?,
        sweep: SweepFeature,
        pathSketch: Sketch,
        parameters: ParameterTable,
        evaluatedDocument: EvaluatedDocument?,
        unsupportedReason: inout String?
    ) throws -> MeasurementResult.Solid? {
        guard sweep.options.resultKind == .solid else {
            unsupportedReason = "The sweep result kind is not solid."
            return nil
        }
        guard let evaluatedDocument else {
            unsupportedReason = "Evaluated geometry is unavailable."
            return nil
        }
        guard let bodyID = evaluatedBodyID(for: featureID, in: evaluatedDocument) else {
            unsupportedReason = "The evaluated document is missing the sweep generated body name."
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
        guard let pathLength = try pathLength(pathSketch, parameters: parameters) else {
            unsupportedReason = "The sweep path length could not be measured."
            return nil
        }
        let meshMeasurement = try evaluatedMeshMeasurement(mesh)
        let brepVolume = try evaluatedBRepVolume(bodyID: bodyID, in: evaluatedDocument.brep)
        let volumeCubicMeters = brepVolume ?? meshMeasurement.volumeCubicMeters
        guard volumeCubicMeters > tolerance.distance * tolerance.distance * tolerance.distance else {
            unsupportedReason = "The evaluated sweep solid volume is below tolerance."
            return nil
        }
        return MeasurementResult.Solid(
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
            volumeCubicMeters: volumeCubicMeters,
            surfaceAreaSquareMeters: meshMeasurement.surfaceAreaSquareMeters,
            bounds: meshMeasurement.bounds
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
        guard let bodyID = evaluatedBodyID(for: featureID, in: evaluatedDocument) else {
            unsupportedReason = "The evaluated document is missing the generated body name."
            return nil
        }
        guard let mesh = evaluatedDocument.meshes[bodyID] else {
            unsupportedReason = "The evaluated document is missing the generated body mesh."
            return nil
        }
        let meshMeasurement = try evaluatedMeshMeasurement(mesh)
        let brepVolume = try evaluatedBRepVolume(bodyID: bodyID, in: evaluatedDocument.brep)
        let volumeCubicMeters = brepVolume ?? meshMeasurement.volumeCubicMeters
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
            volumeCubicMeters: volumeCubicMeters,
            surfaceAreaSquareMeters: meshMeasurement.surfaceAreaSquareMeters,
            bounds: meshMeasurement.bounds
        )
    }

    private func evaluatedBodyID(
        for featureID: FeatureID,
        in evaluatedDocument: EvaluatedDocument
    ) -> BodyID? {
        let bodyName = PersistentName(components: [
            .feature(featureID),
            .generated(GeneratedSubshapeRole.body.rawValue),
        ])
        guard case .body(let bodyID) = evaluatedDocument.generatedNames[bodyName] else {
            return nil
        }
        return bodyID
    }

    private func evaluatedMeshMeasurement(_ mesh: Mesh) throws -> EvaluatedMeshMeasurement {
        guard !mesh.positions.isEmpty,
              !mesh.indices.isEmpty,
              mesh.indices.count.isMultiple(of: 3) else {
            throw EditorError(
                code: .commandFailed,
                message: "Measurement expected a non-empty triangle mesh."
            )
        }
        var bounds = BoundsAccumulator()
        for point in mesh.positions {
            bounds.include(point)
        }
        guard let measuredBounds = bounds.bounds else {
            return EvaluatedMeshMeasurement(
                surfaceAreaSquareMeters: 0.0,
                volumeCubicMeters: 0.0,
                bounds: MeasurementResult.Bounds(
                    minX: 0.0,
                    minY: 0.0,
                    minZ: 0.0,
                    maxX: 0.0,
                    maxY: 0.0,
                    maxZ: 0.0
                )
            )
        }

        var surfaceArea = 0.0
        var signedVolume = 0.0
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
            let first = mesh.positions[firstIndex]
            let second = mesh.positions[secondIndex]
            let third = mesh.positions[thirdIndex]
            let triangleNormal = (second - first).cross(third - first)
            surfaceArea += triangleNormal.length * 0.5
            signedVolume += vector(first).dot(vector(second).cross(vector(third))) / 6.0
            index += 3
        }

        return EvaluatedMeshMeasurement(
            surfaceAreaSquareMeters: surfaceArea,
            volumeCubicMeters: abs(signedVolume),
            bounds: measuredBounds
        )
    }

    private func evaluatedBRepVolume(
        bodyID: BodyID,
        in model: BRepModel
    ) throws -> Double? {
        guard let body = model.bodies[bodyID] else {
            throw EditorError(
                code: .commandFailed,
                message: "Measurement expected an evaluated B-rep body for the sweep feature."
            )
        }
        guard body.kind == .solid else {
            return nil
        }

        var signedVolume = 0.0
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw EditorError(
                    code: .commandFailed,
                    message: "Measurement encountered a missing B-rep shell."
                )
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else {
                    throw EditorError(
                        code: .commandFailed,
                        message: "Measurement encountered a missing B-rep face."
                    )
                }
                guard face.loops.count == 1,
                      let loopID = face.loops.first,
                      let loop = model.loops[loopID],
                      loop.role == .outer,
                      try isLineOnly(loop: loop, in: model) else {
                    return nil
                }
                var points = try model.orderedPoints(for: loopID)
                if (shell.orientation == .reversed) != (face.orientation == .reversed) {
                    points.reverse()
                }
                signedVolume += try signedVolumeContribution(points)
            }
        }

        let volume = abs(signedVolume)
        guard volume.isFinite else {
            return nil
        }
        return volume
    }

    private func isLineOnly(loop: Loop, in model: BRepModel) throws -> Bool {
        for orientedEdge in loop.edges {
            guard let edge = model.edges[orientedEdge.edgeID],
                  let curve = model.geometry.curves[edge.curveID] else {
                throw EditorError(
                    code: .commandFailed,
                    message: "Measurement encountered missing B-rep edge geometry."
                )
            }
            guard case .line = curve else {
                return false
            }
        }
        return true
    }

    private func signedVolumeContribution(_ points: [Point3D]) throws -> Double {
        guard points.count >= 3 else {
            throw EditorError(
                code: .commandFailed,
                message: "Measurement encountered a degenerate B-rep face."
            )
        }
        let anchor = vector(points[0])
        var signedVolume = 0.0
        for index in 1..<(points.count - 1) {
            signedVolume += anchor.dot(
                vector(points[index]).cross(vector(points[index + 1]))
            ) / 6.0
        }
        return signedVolume
    }

    private func vector(_ point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }

    private func boundsForSketch(
        _ sketch: Sketch,
        parameters: ParameterTable
    ) throws -> MeasurementResult.Bounds? {
        let frame = try planeFrame(for: sketch.plane)
        var bounds = BoundsAccumulator()
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
                for point in try arcBoundsPoints(arc, parameters: parameters) {
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

    private func resolvedPoint(
        _ point: SketchPoint,
        parameters: ParameterTable
    ) throws -> Point2D {
        Point2D(
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
        _ sketch: Sketch,
        parameters: ParameterTable
    ) throws -> Double? {
        let frame = try planeFrame(for: sketch.plane)
        var totalLength = 0.0
        for entity in sketch.entities.values {
            switch entity {
            case .point:
                return nil
            case .line(let line):
                let start = frame.map(try resolvedPoint(line.start, parameters: parameters))
                let end = frame.map(try resolvedPoint(line.end, parameters: parameters))
                totalLength += (end - start).length
            case .circle(let circle):
                let radius = try resolvedLength(circle.radius, parameters: parameters)
                guard radius > tolerance.distance else {
                    return nil
                }
                totalLength += Double.pi * 2.0 * radius
            case .arc(let arc):
                let radius = try resolvedLength(arc.radius, parameters: parameters)
                let startAngle = try resolvedAngle(arc.startAngle, parameters: parameters)
                let endAngle = try resolvedAngle(arc.endAngle, parameters: parameters)
                let span = normalizedAngleSpan(startAngle: startAngle, endAngle: endAngle)
                guard radius > tolerance.distance, span > tolerance.angle else {
                    return nil
                }
                totalLength += radius * span
            case .spline(let spline):
                let points = try splineSamplePoints(spline, parameters: parameters)
                guard points.count >= 2 else {
                    return nil
                }
                for index in 0..<(points.count - 1) {
                    let start = frame.map(points[index])
                    let end = frame.map(points[index + 1])
                    totalLength += (end - start).length
                }
            }
        }
        return totalLength > tolerance.distance ? totalLength : nil
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
    ) throws -> [Point2D] {
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
            Point2D(x: point.x, y: point.y)
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
            return Point2D(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
        return ResolvedProfileSegment(kind: .arc, points: points)
    }

    private func orderedClosedLoop(from segments: [ResolvedProfileSegment]) -> [Point2D]? {
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
        parameters: ParameterTable
    ) throws -> [Point2D] {
        let center = try resolvedPoint(arc.center, parameters: parameters)
        let radius = try resolvedLength(arc.radius, parameters: parameters)
        let startAngle = try resolvedAngle(arc.startAngle, parameters: parameters)
        let span = normalizedAngleSpan(
            startAngle: startAngle,
            endAngle: try resolvedAngle(arc.endAngle, parameters: parameters)
        )
        let angles = arcSamplingAngles(startAngle: startAngle, span: span)
        return angles.map { angle in
            Point2D(
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

    private func polygonArea(_ points: [Point2D]) -> Double {
        var twiceArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            twiceArea += current.x * next.y - next.x * current.y
        }
        return twiceArea / 2.0
    }

    private func isClose(_ lhs: Point2D, _ rhs: Point2D) -> Bool {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot() <= tolerance.distance
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
    var volumeCubicMeters: Double
    var bounds: MeasurementResult.Bounds
}

private struct PlaneFrame {
    var origin: Point3D
    var normal: Vector3D
    var u: Vector3D
    var v: Vector3D

    func map(_ point: Point2D) -> Point3D {
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
    var points: [Point2D]

    var start: Point2D {
        points[0]
    }

    var end: Point2D {
        points[points.count - 1]
    }
}

private struct Point2D: Equatable {
    var x: Double
    var y: Double
}

private struct BoundsAccumulator {
    private(set) var bounds: MeasurementResult.Bounds?

    mutating func include(_ point: Point3D) {
        include(
            MeasurementResult.Bounds(
                minX: point.x,
                minY: point.y,
                minZ: point.z,
                maxX: point.x,
                maxY: point.y,
                maxZ: point.z
            )
        )
    }

    mutating func include(_ next: MeasurementResult.Bounds) {
        guard let current = bounds else {
            bounds = next
            return
        }
        bounds = MeasurementResult.Bounds(
            minX: min(current.minX, next.minX),
            minY: min(current.minY, next.minY),
            minZ: min(current.minZ, next.minZ),
            maxX: max(current.maxX, next.maxX),
            maxY: max(current.maxY, next.maxY),
            maxZ: max(current.maxZ, next.maxZ)
        )
    }
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
