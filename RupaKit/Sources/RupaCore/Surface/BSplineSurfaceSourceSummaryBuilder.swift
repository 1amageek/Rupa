import SwiftCAD

struct BSplineSurfaceSourceSummaryBuilder: Sendable {
    private let boundaryProfileBuilder = BSplineSurfaceBoundaryProfileBuilder()

    /// Unified per-edge trim view: authored loops come from the downstream
    /// `surfaceTrim` feature, rectangular domains synthesize one outer loop of
    /// constant-parameter boundary curves in the kernel's vMin/uMax/vMax/uMin
    /// order.
    private struct SummaryTrimEdge {
        var parameterCurve: SurfaceParameterCurve
        var role: String?

        func startParameter(tolerance: ModelingTolerance) throws -> SurfaceParameter {
            try parameterCurve.startParameter(tolerance: tolerance)
        }

        func endParameter(tolerance: ModelingTolerance) throws -> SurfaceParameter {
            try parameterCurve.endParameter(tolerance: tolerance)
        }
    }

    private struct SummaryTrimLoop {
        var role: SurfaceTrimLoopRole
        var edges: [SummaryTrimEdge]
        var isRectangularBoundaryLoop: Bool
    }

    private func summaryTrimLoops(
        authoredTrimLoops: [SurfaceTrimLoop],
        trimDomain: SurfaceParameterDomain2D
    ) -> [SummaryTrimLoop] {
        guard authoredTrimLoops.isEmpty else {
            return authoredTrimLoops.map { loop in
                SummaryTrimLoop(
                    role: loop.role,
                    edges: loop.parameterCurves.map {
                        SummaryTrimEdge(parameterCurve: $0, role: nil)
                    },
                    isRectangularBoundaryLoop: false
                )
            }
        }
        let uLower = trimDomain.uLowerBound
        let uUpper = trimDomain.uUpperBound
        let vLower = trimDomain.vLowerBound
        let vUpper = trimDomain.vUpperBound
        return [
            SummaryTrimLoop(
                role: .outer,
                edges: [
                    SummaryTrimEdge(
                        parameterCurve: .constantV(v: vLower, uStart: uLower, uEnd: uUpper),
                        role: BSplineSurfaceBoundarySide.vMin.rawValue
                    ),
                    SummaryTrimEdge(
                        parameterCurve: .constantU(u: uUpper, vStart: vLower, vEnd: vUpper),
                        role: BSplineSurfaceBoundarySide.uMax.rawValue
                    ),
                    SummaryTrimEdge(
                        parameterCurve: .constantV(v: vUpper, uStart: uUpper, uEnd: uLower),
                        role: BSplineSurfaceBoundarySide.vMax.rawValue
                    ),
                    SummaryTrimEdge(
                        parameterCurve: .constantU(u: uLower, vStart: vUpper, vEnd: vLower),
                        role: BSplineSurfaceBoundarySide.uMin.rawValue
                    ),
                ],
                isRectangularBoundaryLoop: true
            ),
        ]
    }

    private struct PatchBuildResult {
        var patch: SurfaceSourceSummaryResult.Patch
        var diagnostics: [SurfaceSourceSummaryResult.Diagnostic]
    }

    func source(
        featureID: FeatureID,
        feature: FeatureNode,
        surfaceFeature: BSplineSurfaceFeature,
        authoredTrimLoops: [SurfaceTrimLoop],
        authoredTrimTargetFace: StableSubshapeReference?,
        authoredTrimFeatureID: FeatureID?,
        sceneNodeID: SceneNodeID?,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay],
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay],
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry],
        tolerance: ModelingTolerance
    ) throws -> SurfaceSourceSummaryResult.Source? {
        let surface = surfaceFeature.surface
        let usesAuthoredTrimLoops = authoredTrimLoops.isEmpty == false
        let trimDomain = try surfaceFeature.resolvedParameterDomain(tolerance: tolerance)
        let trimsFullSurfaceDomain = usesAuthoredTrimLoops
            ? false
            : surfaceFeature.parameterDomain == nil
        let sourceTrimLoops = summaryTrimLoops(
            authoredTrimLoops: authoredTrimLoops,
            trimDomain: trimDomain
        )
        let boundaryEdgeCount = sourceTrimLoops
            .filter { $0.role == .outer }
            .reduce(0) { partial, loop in partial + loop.edges.count }
        let internalEdgeCount = sourceTrimLoops
            .filter { $0.role == .inner }
            .reduce(0) { partial, loop in partial + loop.edges.count }
        let patchBuildResult = try bSplinePatch(
            featureID: featureID,
            surface: surface,
            sourceTrimLoops: sourceTrimLoops,
            usesAuthoredTrimLoops: usesAuthoredTrimLoops,
            authoredTrimTargetFace: authoredTrimTargetFace,
            authoredTrimFeatureID: authoredTrimFeatureID,
            uBounds: (trimDomain.uLowerBound, trimDomain.uUpperBound),
            vBounds: (trimDomain.vLowerBound, trimDomain.vUpperBound),
            trimsFullSurfaceDomain: trimsFullSurfaceDomain,
            surfaceControlPointDisplays: surfaceControlPointDisplays,
            surfaceFrameDisplays: surfaceFrameDisplays,
            topologyEntriesByPersistentName: topologyEntriesByPersistentName,
            tolerance: tolerance
        )
        return SurfaceSourceSummaryResult.Source(
            featureID: featureID.description,
            name: feature.name ?? "B-spline Surface",
            sceneNodeID: sceneNodeID?.description,
            kind: "bSplineSurface",
            meshCounts: SurfaceSourceSummaryResult.MeshCounts(
                vertexCount: 0,
                usedVertexCount: 0,
                triangleCount: 0,
                indexedElementCount: 0,
                boundaryEdgeCount: boundaryEdgeCount,
                internalEdgeCount: internalEdgeCount
            ),
            options: SurfaceSourceSummaryResult.PolySplineOptionsSummary(
                roundedCorners: false,
                mergePatches: false,
                interpolateBoundaryExactly: true
            ),
            support: SurfaceSourceSummaryResult.SupportSummary(
                isSupported: true,
                candidateKind: "directBSplineSurface",
                supportedPatchCount: 1,
                candidatePatchCount: 1,
                failureMessage: nil
            ),
            patches: [patchBuildResult.patch],
            adjacencies: [],
            diagnostics: [
                SurfaceSourceSummaryResult.Diagnostic(
                    severity: "info",
                    code: "directBSplineSurface",
                    message: "Direct B-spline surface source is represented by its stored degree, knot vectors, weights, control net, and source-owned trim loops."
                ),
            ] + trimDomainDiagnostics(
                trimDomain: trimDomain,
                trimsFullSurfaceDomain: trimsFullSurfaceDomain,
                usesAuthoredTrimLoops: usesAuthoredTrimLoops
            ) + authoredTrimLoopDiagnostics(
                sourceTrimLoops: sourceTrimLoops,
                usesAuthoredTrimLoops: usesAuthoredTrimLoops
            ) + patchBuildResult.diagnostics
        )
    }

    private func bSplinePatch(
        featureID: FeatureID,
        surface: BSplineSurface3D,
        sourceTrimLoops: [SummaryTrimLoop],
        usesAuthoredTrimLoops: Bool,
        authoredTrimTargetFace: StableSubshapeReference?,
        authoredTrimFeatureID: FeatureID?,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        trimsFullSurfaceDomain: Bool,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay],
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay],
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry],
        tolerance: ModelingTolerance
    ) throws -> PatchBuildResult {
        let faceSubshapeID = subshapeIdentity(featureID: featureID, subshape: "patch:0:face")
        let faceEntry = topologyEntriesByPersistentName[faceSubshapeID]
        // An authored trim supersedes the source surface body, so its stable
        // target face keeps the patch addressable when the surface feature no
        // longer publishes the patch face itself.
        let stableFaceReference = faceEntry?.stableReference ?? authoredTrimTargetFace
        let surfaceReference = stableFaceReference.map(SurfaceReference.init(subshape:))
        let faceSelectionReference: SelectionReference? = surfaceReference.map {
            .surface(.whole($0))
        }
        let resolvedFaceSubshapeID = faceEntry?.subshapeID
            ?? authoredTrimTargetFace.map { GeneratedSubshapeIdentity.string(for: $0.subshapeID) }
        let resolvedFaceSelectionComponentID = faceEntry?.selectionComponentID
            ?? authoredTrimTargetFace.map {
                SelectionComponentID.generatedTopology($0.subshapeID).rawValue
            }
        let trimLoops = try trimLoops(
            featureID: featureID,
            authoredTrimFeatureID: authoredTrimFeatureID,
            surface: surface,
            surfaceReference: surfaceReference,
            sourceTrimLoops: sourceTrimLoops,
            usesAuthoredTrimLoops: usesAuthoredTrimLoops,
            uBounds: uBounds,
            vBounds: vBounds,
            trimsFullSurfaceDomain: trimsFullSurfaceDomain,
            topologyEntriesByPersistentName: topologyEntriesByPersistentName,
            tolerance: tolerance
        )
        let basis = basis(surface: surface, surfaceReference: surfaceReference)
        let frameSampleResult: SurfaceSourceFrameSampleBuilder.Result
        if let surfaceReference {
            frameSampleResult = SurfaceSourceFrameSampleBuilder().buildSamples(
                featureID: featureID,
                patchID: 0,
                surface: surface,
                surfaceReference: surfaceReference,
                uSpans: clippedSpans(basis.uSpans, to: uBounds),
                vSpans: clippedSpans(basis.vSpans, to: vBounds),
                surfaceFrameDisplays: surfaceFrameDisplays
            )
        } else {
            frameSampleResult = SurfaceSourceFrameSampleBuilder.Result()
        }

        return PatchBuildResult(patch: SurfaceSourceSummaryResult.Patch(
            patchID: 0,
            faceSubshapeID: resolvedFaceSubshapeID,
            faceSelectionComponentID: resolvedFaceSelectionComponentID,
            faceSelectionReference: faceSelectionReference,
            uDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: uBounds.lower, upperBound: uBounds.upper),
            vDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: vBounds.lower, upperBound: vBounds.upper),
            basis: basis,
            controlVertices: [],
            controlPoints: bSplineControlPoints(
                featureID: featureID,
                surface: surface,
                surfaceReference: surfaceReference,
                surfaceControlPointDisplays: surfaceControlPointDisplays
            ),
            trimLoops: trimLoops,
            frameSamples: frameSampleResult.samples,
            parameterAddresses: patchParameterAddresses(
                surfaceReference: surfaceReference,
                uBounds: uBounds,
                vBounds: vBounds
            )
        ), diagnostics: frameSampleResult.diagnostics)
    }

    private func bSplineControlPoints(
        featureID: FeatureID,
        surface: BSplineSurface3D,
        surfaceReference: SurfaceReference?,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay]
    ) -> [SurfaceSourceSummaryResult.ControlPoint] {
        var result: [SurfaceSourceSummaryResult.ControlPoint] = []
        result.reserveCapacity(surface.uControlPointCount * surface.vControlPointCount)
        for vIndex in 0..<surface.controlPoints.count {
            for uIndex in 0..<surface.controlPoints[vIndex].count {
                let point = surface.controlPoints[vIndex][uIndex]
                let weight = surface.weights.indices.contains(vIndex)
                    && surface.weights[vIndex].indices.contains(uIndex)
                    ? surface.weights[vIndex][uIndex]
                    : 1.0
                let isBoundary = uIndex == 0
                    || uIndex == surface.uControlPointCount - 1
                    || vIndex == 0
                    || vIndex == surface.vControlPointCount - 1
                let selectionReference = surfaceReference.map {
                    SelectionReference.surface(.controlPoint(SurfaceControlPointReference(
                        surface: $0,
                        uIndex: uIndex,
                        vIndex: vIndex
                    )))
                }
                result.append(SurfaceSourceSummaryResult.ControlPoint(
                    id: "feature:\(featureID.description)/patch:0/surfaceControlPoint:u\(uIndex):v\(vIndex)",
                    uIndex: uIndex,
                    vIndex: vIndex,
                    point: SurfaceSourceSummaryResult.Point(x: point.x, y: point.y, z: point.z),
                    weight: weight,
                    isBoundary: isBoundary,
                    isEditable: true,
                    selectionReference: selectionReference,
                    isPointDisplayVisible: selectionReference.map {
                        isSurfaceControlPointDisplayVisible(
                            $0,
                            in: surfaceControlPointDisplays
                        )
                    } ?? false
                ))
            }
        }
        return result
    }

    private func trimLoops(
        featureID: FeatureID,
        authoredTrimFeatureID: FeatureID?,
        surface: BSplineSurface3D,
        surfaceReference: SurfaceReference?,
        sourceTrimLoops: [SummaryTrimLoop],
        usesAuthoredTrimLoops: Bool,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        trimsFullSurfaceDomain: Bool,
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry],
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSourceSummaryResult.TrimLoop] {
        try sourceTrimLoops.enumerated().map { loopIndex, sourceLoop in
            let edges = try trimEdges(
                featureID: featureID,
                authoredTrimFeatureID: authoredTrimFeatureID,
                allSourceLoops: sourceTrimLoops,
                surface: surface,
                surfaceReference: surfaceReference,
                sourceLoop: sourceLoop,
                loopIndex: loopIndex,
                usesAuthoredTrimLoops: usesAuthoredTrimLoops,
                uBounds: uBounds,
                vBounds: vBounds,
                trimsFullSurfaceDomain: trimsFullSurfaceDomain,
                topologyEntriesByPersistentName: topologyEntriesByPersistentName,
                tolerance: tolerance
            )
            return SurfaceSourceSummaryResult.TrimLoop(
                role: sourceLoop.role.rawValue,
                parameterAddresses: try trimLoopParameterAddresses(
                    sourceLoop: sourceLoop,
                    loopIndex: loopIndex,
                    surfaceReference: surfaceReference,
                    uBounds: uBounds,
                    vBounds: vBounds,
                    tolerance: tolerance
                ),
                sourceVertexIndices: [],
                // Authored trim edge names resolve to the surfaceTrim
                // feature's generated "edge" subshapes in sewing traversal
                // order; entries absent from the live topology are omitted.
                edgePersistentNames: edges.compactMap { edge in
                    guard let persistentName = edge.persistentName,
                          topologyEntriesByPersistentName[persistentName] != nil else {
                        return nil
                    }
                    return persistentName
                },
                selectionReferences: edges.compactMap(\.selectionReference),
                edges: edges
            )
        }
    }

    private func trimEdges(
        featureID: FeatureID,
        authoredTrimFeatureID: FeatureID?,
        allSourceLoops: [SummaryTrimLoop],
        surface: BSplineSurface3D,
        surfaceReference: SurfaceReference?,
        sourceLoop: SummaryTrimLoop,
        loopIndex: Int,
        usesAuthoredTrimLoops: Bool,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        trimsFullSurfaceDomain: Bool,
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry],
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSourceSummaryResult.TrimLoop.Edge] {
        try sourceLoop.edges.indices.map { index in
            let sourceEdge = sourceLoop.edges[index]
            let subshape = trimEdgeSubshape(
                sourceLoop: sourceLoop,
                loopIndex: loopIndex,
                edgeIndex: index
            )
            // Authored trim edges live on the downstream surfaceTrim feature,
            // which names them with role "edge" in sewing traversal order.
            let edgePersistentName: String?
            if usesAuthoredTrimLoops {
                edgePersistentName = authoredTrimFeatureID.flatMap { trimFeatureID in
                    let name = GeneratedSubshapeIdentity.string(for: SubshapeID(
                        featureID: trimFeatureID,
                        role: "edge",
                        ordinal: authoredTrimEdgeOrdinal(
                            loops: allSourceLoops,
                            loopIndex: loopIndex,
                            edgeIndex: index
                        )
                    ))
                    return topologyEntriesByPersistentName[name] == nil ? nil : name
                }
            } else {
                edgePersistentName = subshapeIdentity(featureID: featureID, subshape: subshape)
            }
            let trimReference = surfaceReference.map {
                SurfaceTrimReference(
                    surface: $0,
                    loopIndex: loopIndex,
                    edgeIndex: index
                )
            }
            let selectionReference: SelectionReference? = if usesAuthoredTrimLoops {
                trimReference.map { .surface(.trim($0)) }
            } else if let edgePersistentName,
                      topologyEntriesByPersistentName[edgePersistentName] != nil {
                trimReference.map { .surface(.trim($0)) }
            } else {
                nil
            }
            let side = boundarySide(role: sourceEdge.role)
            let parameters = if let side, sourceLoop.isRectangularBoundaryLoop {
                trimEdgeParameters(
                    side: side,
                    surfaceReference: surfaceReference,
                    uBounds: uBounds,
                    vBounds: vBounds
                )
            } else {
                try trimEdgeParameters(
                    sourceEdge: sourceEdge,
                    loopIndex: loopIndex,
                    edgeIndex: index,
                    surfaceReference: surfaceReference,
                    tolerance: tolerance
                )
            }
            let levels = supportedBoundaryContinuityLevels(
                side: side,
                surface: surface,
                usesAuthoredTrimLoops: usesAuthoredTrimLoops,
                trimsFullSurfaceDomain: trimsFullSurfaceDomain,
                hasSelectionReference: selectionReference != nil
            )
            let boundaryDirection = side?.boundaryDirection
                ?? dominantBoundaryDirection(start: parameters.start, end: parameters.end)
            let inwardDirection = side?.inwardDirection
                ?? inferredInwardDirection(boundaryDirection: boundaryDirection)
            let boundaryControlPointReferences: [SelectionReference]
            let firstInwardControlPointReferences: [SelectionReference]
            let secondInwardControlPointReferences: [SelectionReference]
            if let side, trimsFullSurfaceDomain, usesAuthoredTrimLoops == false {
                boundaryControlPointReferences = controlPointReferences(
                    side: side,
                    inwardOffset: 0,
                    surface: surface,
                    surfaceReference: surfaceReference
                )
                firstInwardControlPointReferences = controlPointReferences(
                    side: side,
                    inwardOffset: 1,
                    surface: surface,
                    surfaceReference: surfaceReference
                )
                secondInwardControlPointReferences = controlPointReferences(
                    side: side,
                    inwardOffset: 2,
                    surface: surface,
                    surfaceReference: surfaceReference
                )
            } else {
                boundaryControlPointReferences = []
                firstInwardControlPointReferences = []
                secondInwardControlPointReferences = []
            }
            return SurfaceSourceSummaryResult.TrimLoop.Edge(
                index: index,
                role: sourceEdge.role ?? "trimEdge",
                persistentName: edgePersistentName,
                selectionReference: selectionReference,
                startParameter: parameters.start,
                endParameter: parameters.end,
                parameterCurve: parameterCurveSummary(
                    for: sourceEdge.parameterCurve,
                    trimReference: trimReference
                ),
                parameterCurveControlPoints: parameterCurveControlPoints(
                    for: sourceEdge.parameterCurve,
                    loopIndex: loopIndex,
                    edgeIndex: index,
                    surfaceReference: surfaceReference
                ),
                boundaryDirection: boundaryDirection,
                inwardDirection: inwardDirection,
                boundaryControlPointReferences: boundaryControlPointReferences,
                firstInwardControlPointReferences: firstInwardControlPointReferences,
                secondInwardControlPointReferences: secondInwardControlPointReferences,
                supportedBoundaryContinuityLevels: levels,
                supportsBoundaryContinuityMatching: levels.isEmpty == false,
                unsupportedReason: levels.isEmpty
                    ? unsupportedBoundaryContinuityReason(
                        side: side,
                        surface: surface,
                        usesAuthoredTrimLoops: usesAuthoredTrimLoops,
                        trimsFullSurfaceDomain: trimsFullSurfaceDomain,
                        hasSelectionReference: selectionReference != nil
                    )
                    : nil
            )
        }
    }

    private func parameterCurveSummary(
        for curve: SurfaceParameterCurve,
        trimReference: SurfaceTrimReference?
    ) -> SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurve {
        switch curve {
        case .affine, .harmonic, .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .periodicTranslation, .projectedAnalytic:
            return SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurve(
                kind: "analytic",
                unsupportedReason: "Analytic and certified trim p-curves are not editable source primitives."
            )
        case .constantU:
            return SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurve(
                kind: "constantU",
                unsupportedReason: "Constant trim p-curves do not have knot vectors."
            )
        case .constantV:
            return SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurve(
                kind: "constantV",
                unsupportedReason: "Constant trim p-curves do not have knot vectors."
            )
        case .polyline:
            return SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurve(
                kind: "polyline",
                unsupportedReason: "Polyline trim p-curves must be rebuilt as B-splines before knot insertion."
            )
        case let .bSpline(curve):
            let spans = parameterCurveSpans(
                knots: curve.knots,
                degree: curve.degree,
                trimReference: trimReference
            )
            let bounds: (lower: Double, upper: Double)?
            if case let .closed(lowerBound, upperBound) = curve.domain {
                bounds = (lowerBound, upperBound)
            } else {
                bounds = nil
            }
            return SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurve(
                kind: "bSpline",
                degree: curve.degree,
                order: curve.order,
                domainLowerBound: bounds?.lower,
                domainUpperBound: bounds?.upper,
                knots: curve.knots,
                knotVector: parameterCurveKnotVector(
                    knots: curve.knots,
                    degree: curve.degree,
                    trimReference: trimReference
                ),
                spans: spans,
                spanCount: spans.count,
                isRational: curve.isRational,
                supportsKnotInsertion: spans.isEmpty == false,
                unsupportedReason: spans.isEmpty
                    ? "B-spline trim p-curve has no non-degenerate span for knot insertion."
                    : nil
            )
        }
    }

    private func parameterCurveKnotVector(
        knots: [Double],
        degree: Int,
        trimReference: SurfaceTrimReference?
    ) -> [SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurve.Knot] {
        let lowerBound = knots.indices.contains(degree) ? knots[degree] : knots.first
        let upperBoundIndex = knots.count - degree - 1
        let upperBound = knots.indices.contains(upperBoundIndex) ? knots[upperBoundIndex] : knots.last
        let multiplicities = Dictionary(grouping: knots, by: { $0 }).mapValues(\.count)
        let firstInteriorKnotIndex = degree + 1
        let lastInteriorKnotIndex = knots.count - degree - 2
        return knots.indices.map { index in
            let value = knots[index]
            let isBoundary = value == lowerBound || value == upperBound
            let multiplicity = multiplicities[value] ?? 1
            let isInterior = firstInteriorKnotIndex <= lastInteriorKnotIndex
                && (firstInteriorKnotIndex ... lastInteriorKnotIndex).contains(index)
                && isBoundary == false
            let isValueEditable = isInterior
                && index > knots.startIndex
                && index < knots.index(before: knots.endIndex)
                && knots[index - 1] < knots[index + 1]
            let isInsertionSupported = isInterior && multiplicity < degree
            return SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurve.Knot(
                id: "parameterCurveKnot:\(index)",
                index: index,
                value: value,
                multiplicity: multiplicity,
                isBoundary: isBoundary,
                isValueEditable: isValueEditable,
                isMultiplicityEditable: isInsertionSupported,
                isInsertionSupported: isInsertionSupported,
                unsupportedReason: parameterCurveKnotUnsupportedReason(
                    isInterior: isInterior,
                    isBoundary: isBoundary,
                    multiplicity: multiplicity,
                    degree: degree
                ),
                selectionReference: trimReference.map {
                    .surface(.trimKnot(SurfaceTrimKnotReference(
                        trim: $0,
                        knotIndex: index
                    )))
                }
            )
        }
    }

    private func parameterCurveKnotUnsupportedReason(
        isInterior: Bool,
        isBoundary: Bool,
        multiplicity: Int,
        degree: Int
    ) -> String? {
        if isInterior && multiplicity < degree {
            return nil
        }
        if isBoundary {
            return "Boundary trim p-curve knots cannot be duplicated."
        }
        if multiplicity >= degree {
            return "B-spline trim p-curve knot multiplicity is already saturated."
        }
        return "Only interior trim p-curve knots can be duplicated."
    }

    private func parameterCurveSpans(
        knots: [Double],
        degree: Int,
        trimReference: SurfaceTrimReference?
    ) -> [SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurve.Span] {
        let lowerIndex = degree
        let upperIndex = knots.count - degree - 1
        guard lowerIndex < upperIndex else {
            return []
        }
        var result: [SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurve.Span] = []
        for index in lowerIndex..<upperIndex {
            let lowerBound = knots[index]
            let upperBound = knots[index + 1]
            guard upperBound > lowerBound else {
                continue
            }
            let spanIndex = result.count
            result.append(SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurve.Span(
                id: "parameterCurveSpan:\(spanIndex)",
                index: spanIndex,
                lowerBound: lowerBound,
                upperBound: upperBound,
                startKnotIndex: index,
                endKnotIndex: index + 1,
                isInsertionSupported: true,
                selectionReference: trimReference.map {
                    .surface(.trimSpan(SurfaceTrimSpanReference(
                        trim: $0,
                        spanIndex: spanIndex
                    )))
                }
            ))
        }
        return result
    }

    private func parameterCurveControlPoints(
        for curve: SurfaceParameterCurve,
        loopIndex: Int,
        edgeIndex: Int,
        surfaceReference: SurfaceReference?
    ) -> [SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurveControlPoint] {
        switch curve {
        case .constantU, .constantV, .affine, .harmonic, .sphericalGreatCircle,
             .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .periodicTranslation, .projectedAnalytic:
            return []
        case .polyline(let points):
            return parameterCurveControlPoints(
                points: points,
                loopIndex: loopIndex,
                edgeIndex: edgeIndex,
                surfaceReference: surfaceReference
            )
        case .bSpline(let curve):
            return parameterCurveControlPoints(
                controlPoints: curve.controlPoints,
                weights: curve.weights,
                loopIndex: loopIndex,
                edgeIndex: edgeIndex,
                surfaceReference: surfaceReference
            )
        }
    }

    private func parameterCurveControlPoints(
        points: [SurfaceParameter],
        loopIndex: Int,
        edgeIndex: Int,
        surfaceReference: SurfaceReference?
    ) -> [SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurveControlPoint] {
        points.enumerated().map { index, point in
            parameterCurveControlPoint(
                index: index,
                count: points.count,
                u: point.u,
                v: point.v,
                weight: nil,
                isWeightEditable: false,
                weightUnsupportedReason: "Polyline trim p-curve control points do not have NURBS weights.",
                loopIndex: loopIndex,
                edgeIndex: edgeIndex,
                surfaceReference: surfaceReference
            )
        }
    }

    private func parameterCurveControlPoints(
        controlPoints: [Point2D],
        weights: [Double],
        loopIndex: Int,
        edgeIndex: Int,
        surfaceReference: SurfaceReference?
    ) -> [SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurveControlPoint] {
        controlPoints.enumerated().map { index, point in
            let weight = weights.indices.contains(index) ? weights[index] : nil
            return parameterCurveControlPoint(
                index: index,
                count: controlPoints.count,
                u: point.x,
                v: point.y,
                weight: weight,
                isWeightEditable: weight != nil,
                weightUnsupportedReason: weight == nil
                    ? "B-spline trim p-curve weight vector does not contain this control point."
                    : nil,
                loopIndex: loopIndex,
                edgeIndex: edgeIndex,
                surfaceReference: surfaceReference
            )
        }
    }

    private func parameterCurveControlPoint(
        index: Int,
        count: Int,
        u: Double,
        v: Double,
        weight: Double?,
        isWeightEditable: Bool,
        weightUnsupportedReason: String?,
        loopIndex: Int,
        edgeIndex: Int,
        surfaceReference: SurfaceReference?
    ) -> SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurveControlPoint {
        let isEndpoint = index == 0 || index == count - 1
        return SurfaceSourceSummaryResult.TrimLoop.Edge.ParameterCurveControlPoint(
            index: index,
            parameter: parameterAddress(
                id: "loop:\(loopIndex):edge:\(edgeIndex):parameterCurveControlPoint:\(index)",
                surfaceReference: surfaceReference,
                u: u,
                v: v
            ),
            weight: weight,
            isEndpoint: isEndpoint,
            isEditable: isEndpoint == false,
            unsupportedReason: isEndpoint
                ? "Use moveSurfaceTrimEndpoint for trim endpoints."
                : nil,
            isWeightEditable: isWeightEditable,
            weightUnsupportedReason: weightUnsupportedReason
        )
    }

    /// Mirrors the kernel sewing traversal that assigns edge ordinals to an
    /// authored surface trim: loops are ordered outer-first and then by their
    /// sewing stable identifier, and edges keep loop order. Loop edges never
    /// coincide within one trim, so ordinals accumulate without merging.
    private func authoredTrimEdgeOrdinal(
        loops: [SummaryTrimLoop],
        loopIndex: Int,
        edgeIndex: Int
    ) -> Int {
        let order = loops.indices.sorted { lhs, rhs in
            let lhsOuter = loops[lhs].role == .outer
            let rhsOuter = loops[rhs].role == .outer
            if lhsOuter != rhsOuter {
                return lhsOuter
            }
            return "surfaceTrim:loop:\(lhs)" < "surfaceTrim:loop:\(rhs)"
        }
        var ordinal = 0
        for index in order {
            if index == loopIndex {
                return ordinal + edgeIndex
            }
            ordinal += loops[index].edges.count
        }
        return ordinal + edgeIndex
    }

    private func trimEdgeSubshape(
        sourceLoop: SummaryTrimLoop,
        loopIndex: Int,
        edgeIndex: Int
    ) -> String {
        if loopIndex == 0,
           let role = sourceLoop.edges[edgeIndex].role,
           sourceLoop.isRectangularBoundaryLoop {
            return "patch:0:edge:\(role)"
        }
        return "patch:0:loop:\(loopIndex):edge:\(edgeIndex)"
    }

    private func trimLoopParameterAddresses(
        sourceLoop: SummaryTrimLoop,
        loopIndex: Int,
        surfaceReference: SurfaceReference?,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSourceSummaryResult.ParameterAddress] {
        if loopIndex == 0, sourceLoop.isRectangularBoundaryLoop {
            return cornerParameterAddresses(
                surfaceReference: surfaceReference,
                uBounds: uBounds,
                vBounds: vBounds
            )
        }
        return try sourceLoop.edges.indices.map { edgeIndex in
            let parameter = try sourceLoop.edges[edgeIndex].startParameter(tolerance: tolerance)
            return parameterAddress(
                id: "loop:\(loopIndex):edge:\(edgeIndex):start",
                surfaceReference: surfaceReference,
                u: parameter.u,
                v: parameter.v
            )
        }
    }

    private func trimEdgeParameters(
        sourceEdge: SummaryTrimEdge,
        loopIndex: Int,
        edgeIndex: Int,
        surfaceReference: SurfaceReference?,
        tolerance: ModelingTolerance
    ) throws -> (start: SurfaceSourceSummaryResult.ParameterAddress, end: SurfaceSourceSummaryResult.ParameterAddress) {
        let start = try sourceEdge.startParameter(tolerance: tolerance)
        let end = try sourceEdge.endParameter(tolerance: tolerance)
        return (
            parameterAddress(
                id: "loop:\(loopIndex):edge:\(edgeIndex):start",
                surfaceReference: surfaceReference,
                u: start.u,
                v: start.v
            ),
            parameterAddress(
                id: "loop:\(loopIndex):edge:\(edgeIndex):end",
                surfaceReference: surfaceReference,
                u: end.u,
                v: end.v
            )
        )
    }

    private func boundarySide(role: String?) -> BSplineSurfaceBoundarySide? {
        guard let role else {
            return nil
        }
        return BSplineSurfaceBoundarySide(rawValue: role)
    }

    private func dominantBoundaryDirection(
        start: SurfaceSourceSummaryResult.ParameterAddress,
        end: SurfaceSourceSummaryResult.ParameterAddress
    ) -> SurfaceParameterDirection {
        abs(end.u - start.u) >= abs(end.v - start.v) ? .u : .v
    }

    private func inferredInwardDirection(
        boundaryDirection: SurfaceParameterDirection
    ) -> SurfaceParameterDirection {
        switch boundaryDirection {
        case .u:
            return .v
        case .v:
            return .u
        }
    }

    private func trimEdgeParameters(
        side: BSplineSurfaceBoundarySide,
        surfaceReference: SurfaceReference?,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double)
    ) -> (start: SurfaceSourceSummaryResult.ParameterAddress, end: SurfaceSourceSummaryResult.ParameterAddress) {
        switch side {
        case .vMin:
            return (
                parameterAddress(id: "uMin:vMin", surfaceReference: surfaceReference, u: uBounds.lower, v: vBounds.lower),
                parameterAddress(id: "uMax:vMin", surfaceReference: surfaceReference, u: uBounds.upper, v: vBounds.lower)
            )
        case .uMax:
            return (
                parameterAddress(id: "uMax:vMin", surfaceReference: surfaceReference, u: uBounds.upper, v: vBounds.lower),
                parameterAddress(id: "uMax:vMax", surfaceReference: surfaceReference, u: uBounds.upper, v: vBounds.upper)
            )
        case .vMax:
            return (
                parameterAddress(id: "uMax:vMax", surfaceReference: surfaceReference, u: uBounds.upper, v: vBounds.upper),
                parameterAddress(id: "uMin:vMax", surfaceReference: surfaceReference, u: uBounds.lower, v: vBounds.upper)
            )
        case .uMin:
            return (
                parameterAddress(id: "uMin:vMax", surfaceReference: surfaceReference, u: uBounds.lower, v: vBounds.upper),
                parameterAddress(id: "uMin:vMin", surfaceReference: surfaceReference, u: uBounds.lower, v: vBounds.lower)
            )
        }
    }

    private func controlPointReferences(
        side: BSplineSurfaceBoundarySide,
        inwardOffset: Int,
        surface: BSplineSurface3D,
        surfaceReference: SurfaceReference?
    ) -> [SelectionReference] {
        guard inwardOffset < boundaryProfileBuilder.inwardControlPointCount(for: side, in: surface) else {
            return []
        }
        guard let surfaceReference else {
            return []
        }
        return boundaryOrdinals(for: side, in: surface).map { ordinal in
            let indices = controlPointIndices(side: side, ordinal: ordinal, inwardOffset: inwardOffset, surface: surface)
            return .surface(.controlPoint(SurfaceControlPointReference(
                surface: surfaceReference,
                uIndex: indices.uIndex,
                vIndex: indices.vIndex
            )))
        }
    }

    private func boundaryOrdinals(
        for side: BSplineSurfaceBoundarySide,
        in surface: BSplineSurface3D
    ) -> [Int] {
        switch side {
        case .vMin:
            return Array(0..<surface.uControlPointCount)
        case .uMax:
            return Array(0..<surface.vControlPointCount)
        case .vMax:
            return Array((0..<surface.uControlPointCount).reversed())
        case .uMin:
            return Array((0..<surface.vControlPointCount).reversed())
        }
    }

    private func controlPointIndices(
        side: BSplineSurfaceBoundarySide,
        ordinal: Int,
        inwardOffset: Int,
        surface: BSplineSurface3D
    ) -> (uIndex: Int, vIndex: Int) {
        switch side {
        case .vMin, .vMax:
            return (uIndex: ordinal, vIndex: side.inwardIndex(offset: inwardOffset, in: surface))
        case .uMin, .uMax:
            return (uIndex: side.inwardIndex(offset: inwardOffset, in: surface), vIndex: ordinal)
        }
    }

    private func supportedBoundaryContinuityLevels(
        side: BSplineSurfaceBoundarySide?,
        surface: BSplineSurface3D,
        usesAuthoredTrimLoops: Bool,
        trimsFullSurfaceDomain: Bool,
        hasSelectionReference: Bool
    ) -> [SurfaceBoundaryContinuityLevel] {
        guard hasSelectionReference else {
            return []
        }
        guard let side else {
            return []
        }
        guard usesAuthoredTrimLoops == false else {
            return []
        }
        guard trimsFullSurfaceDomain else {
            return []
        }
        return boundaryProfileBuilder
            .profile(side: side, surface: surface)
            .supportedContinuityLevels
    }

    private func unsupportedBoundaryContinuityReason(
        side: BSplineSurfaceBoundarySide?,
        surface: BSplineSurface3D,
        usesAuthoredTrimLoops: Bool,
        trimsFullSurfaceDomain: Bool,
        hasSelectionReference: Bool
    ) -> String? {
        if hasSelectionReference == false {
            return "Trim edge is not present in the evaluated topology summary."
        }
        guard let side else {
            return "Authored trim edges do not expose boundary control rows for continuity matching."
        }
        if usesAuthoredTrimLoops {
            return "Authored trim loops do not expose boundary control rows for continuity matching."
        }
        if trimsFullSurfaceDomain == false {
            return "Interior rectangular trim domains do not expose boundary control rows for continuity matching."
        }
        let profile = boundaryProfileBuilder.profile(side: side, surface: surface)
        if profile.boundaryControlPointCount < 2 {
            return "Boundary has fewer than two control points."
        }
        if profile.isClamped == false {
            return "Boundary is not clamped, so the boundary control row does not map exactly to the surface edge."
        }
        return nil
    }

    private func trimDomainDiagnostics(
        trimDomain: SurfaceParameterDomain2D,
        trimsFullSurfaceDomain: Bool,
        usesAuthoredTrimLoops: Bool
    ) -> [SurfaceSourceSummaryResult.Diagnostic] {
        guard usesAuthoredTrimLoops == false,
              trimsFullSurfaceDomain == false else {
            return []
        }
        return [
            SurfaceSourceSummaryResult.Diagnostic(
                severity: "info",
                code: "directBSplineSurfaceTrimDomain",
                message: "Direct B-spline surface uses an authored rectangular outer trim domain u[\(trimDomain.uLowerBound), \(trimDomain.uUpperBound)] v[\(trimDomain.vLowerBound), \(trimDomain.vUpperBound)]."
            ),
        ]
    }

    private func authoredTrimLoopDiagnostics(
        sourceTrimLoops: [SummaryTrimLoop],
        usesAuthoredTrimLoops: Bool
    ) -> [SurfaceSourceSummaryResult.Diagnostic] {
        guard usesAuthoredTrimLoops else {
            return []
        }
        let edgeCount = sourceTrimLoops.reduce(0) { partial, loop in
            partial + loop.edges.count
        }
        return [
            SurfaceSourceSummaryResult.Diagnostic(
                severity: "info",
                code: "directSurfaceTrimLoops",
                message: "Direct B-spline surface uses \(sourceTrimLoops.count) authored UV trim loop(s) with \(edgeCount) source p-curve edge(s)."
            ),
        ]
    }

    private func isSurfaceControlPointDisplayVisible(
        _ selectionReference: SelectionReference,
        in displays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay]
    ) -> Bool {
        let id: SurfaceControlPointDisplayID
        do {
            id = try SurfaceControlPointDisplayID(selectionReference: selectionReference)
        } catch {
            return false
        }
        return displays[id]?.isVisible == true
    }

    private func basis(
        surface: BSplineSurface3D,
        surfaceReference: SurfaceReference?
    ) -> SurfaceSourceSummaryResult.Basis {
        let uSpans = spans(
            direction: .u,
            knots: surface.uKnots,
            degree: surface.uDegree,
            surfaceReference: surfaceReference
        )
        let vSpans = spans(
            direction: .v,
            knots: surface.vKnots,
            degree: surface.vDegree,
            surfaceReference: surfaceReference
        )
        return SurfaceSourceSummaryResult.Basis(
            kind: "bSplineSurface",
            uDegree: surface.uDegree,
            vDegree: surface.vDegree,
            uOrder: surface.uOrder,
            vOrder: surface.vOrder,
            uKnots: surface.uKnots,
            vKnots: surface.vKnots,
            uKnotVector: knotVector(
                direction: .u,
                knots: surface.uKnots,
                degree: surface.uDegree,
                surfaceReference: surfaceReference
            ),
            vKnotVector: knotVector(
                direction: .v,
                knots: surface.vKnots,
                degree: surface.vDegree,
                surfaceReference: surfaceReference
            ),
            uSpans: uSpans,
            vSpans: vSpans,
            uSpanCount: uSpans.count,
            vSpanCount: vSpans.count,
            isRational: surface.isRational
        )
    }

    private func knotVector(
        direction: SurfaceParameterDirection,
        knots: [Double],
        degree: Int,
        surfaceReference: SurfaceReference?
    ) -> [SurfaceSourceSummaryResult.Basis.Knot] {
        let lowerBound = knots.first
        let upperBound = knots.last
        let multiplicities = Dictionary(grouping: knots, by: { $0 }).mapValues(\.count)
        let firstInteriorKnotIndex = degree + 1
        let lastInteriorKnotIndex = knots.count - degree - 2
        return knots.indices.map { index in
            let value = knots[index]
            let isBoundary = value == lowerBound || value == upperBound
            let isEditable = firstInteriorKnotIndex <= lastInteriorKnotIndex
                && (firstInteriorKnotIndex ... lastInteriorKnotIndex).contains(index)
                && isBoundary == false
            return SurfaceSourceSummaryResult.Basis.Knot(
                id: "\(direction.rawValue)Knot:\(index)",
                index: index,
                value: value,
                multiplicity: multiplicities[value] ?? 1,
                isBoundary: isBoundary,
                isEditable: isEditable,
                selectionReference: surfaceReference.map {
                    .surface(.knot(SurfaceKnotReference(
                        surface: $0,
                        direction: direction,
                        knotIndex: index
                    )))
                }
            )
        }
    }

    private func spans(
        direction: SurfaceParameterDirection,
        knots: [Double],
        degree: Int,
        surfaceReference: SurfaceReference?
    ) -> [SurfaceSourceSummaryResult.Basis.Span] {
        let lowerIndex = degree
        let upperIndex = knots.count - degree - 1
        guard lowerIndex < upperIndex else {
            return []
        }
        var result: [SurfaceSourceSummaryResult.Basis.Span] = []
        for index in lowerIndex..<upperIndex {
            let lowerBound = knots[index]
            let upperBound = knots[index + 1]
            guard upperBound > lowerBound else {
                continue
            }
            let spanIndex = result.count
            result.append(SurfaceSourceSummaryResult.Basis.Span(
                id: "\(direction.rawValue)Span:\(spanIndex)",
                index: spanIndex,
                lowerBound: lowerBound,
                upperBound: upperBound,
                startKnotIndex: index,
                endKnotIndex: index + 1,
                isEditable: true,
                selectionReference: surfaceReference.map {
                    .surface(.span(SurfaceSpanReference(
                        surface: $0,
                        direction: direction,
                        spanIndex: spanIndex
                    )))
                }
            ))
        }
        return result
    }

    private func clippedSpans(
        _ spans: [SurfaceSourceSummaryResult.Basis.Span],
        to bounds: (lower: Double, upper: Double)
    ) -> [SurfaceSourceSummaryResult.Basis.Span] {
        spans.compactMap { span in
            let lowerBound = max(span.lowerBound, bounds.lower)
            let upperBound = min(span.upperBound, bounds.upper)
            guard upperBound > lowerBound else {
                return nil
            }
            var clippedSpan = span
            clippedSpan.lowerBound = lowerBound
            clippedSpan.upperBound = upperBound
            return clippedSpan
        }
    }

    private func patchParameterAddresses(
        surfaceReference: SurfaceReference?,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double)
    ) -> [SurfaceSourceSummaryResult.ParameterAddress] {
        let centerU = (uBounds.lower + uBounds.upper) * 0.5
        let centerV = (vBounds.lower + vBounds.upper) * 0.5
        return cornerParameterAddresses(
            surfaceReference: surfaceReference,
            uBounds: uBounds,
            vBounds: vBounds
        ) + [
            SurfaceSourceSummaryResult.ParameterAddress(
                id: "center",
                u: centerU,
                v: centerV,
                selectionReference: surfaceReference.map {
                    .surface(.parameter(SurfaceParameterReference(
                        surface: $0,
                        u: centerU,
                        v: centerV
                    )))
                }
            ),
        ]
    }

    private func cornerParameterAddresses(
        surfaceReference: SurfaceReference?,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double)
    ) -> [SurfaceSourceSummaryResult.ParameterAddress] {
        [
            parameterAddress(id: "uMin:vMin", surfaceReference: surfaceReference, u: uBounds.lower, v: vBounds.lower),
            parameterAddress(id: "uMax:vMin", surfaceReference: surfaceReference, u: uBounds.upper, v: vBounds.lower),
            parameterAddress(id: "uMax:vMax", surfaceReference: surfaceReference, u: uBounds.upper, v: vBounds.upper),
            parameterAddress(id: "uMin:vMax", surfaceReference: surfaceReference, u: uBounds.lower, v: vBounds.upper),
        ]
    }

    private func parameterAddress(
        id: String,
        surfaceReference: SurfaceReference?,
        u: Double,
        v: Double
    ) -> SurfaceSourceSummaryResult.ParameterAddress {
        SurfaceSourceSummaryResult.ParameterAddress(
            id: id,
            u: u,
            v: v,
            selectionReference: surfaceReference.map {
                .surface(.parameter(SurfaceParameterReference(
                    surface: $0,
                    u: u,
                    v: v
                )))
            }
        )
    }

    private func subshapeIdentity(featureID: FeatureID, subshape: String) -> String {
        GeneratedSubshapeIdentity.string(for: SubshapeID(
            featureID: featureID,
            role: "bSplineSurface.\(subshape)",
            ordinal: 0
        ))
    }
}
