import SwiftCAD

struct BSplineSurfaceSourceSummaryBuilder: Sendable {
    private let boundaryProfileBuilder = BSplineSurfaceBoundaryProfileBuilder()

    private struct SurfaceEdgeRole {
        var subshape: String
    }

    private struct PatchBuildResult {
        var patch: SurfaceSourceSummaryResult.Patch
        var diagnostics: [SurfaceSourceSummaryResult.Diagnostic]
    }

    private let edgeRoles: [SurfaceEdgeRole] = [
        SurfaceEdgeRole(subshape: "edge:vMin"),
        SurfaceEdgeRole(subshape: "edge:uMax"),
        SurfaceEdgeRole(subshape: "edge:vMax"),
        SurfaceEdgeRole(subshape: "edge:uMin"),
    ]

    func source(
        featureID: FeatureID,
        feature: FeatureNode,
        surfaceFeature: BSplineSurfaceFeature,
        sceneNodeID: SceneNodeID?,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay],
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay],
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) throws -> SurfaceSourceSummaryResult.Source? {
        let surface = surfaceFeature.surface
        let trimDomain = try surfaceFeature.resolvedOuterTrimDomain()
        let trimsFullSurfaceDomain = try trimDomain.isFullSurfaceDomain(of: surface)
        let patchBuildResult = bSplinePatch(
            featureID: featureID,
            surface: surface,
            uBounds: (trimDomain.uLowerBound, trimDomain.uUpperBound),
            vBounds: (trimDomain.vLowerBound, trimDomain.vUpperBound),
            trimsFullSurfaceDomain: trimsFullSurfaceDomain,
            surfaceControlPointDisplays: surfaceControlPointDisplays,
            surfaceFrameDisplays: surfaceFrameDisplays,
            topologyEntriesByPersistentName: topologyEntriesByPersistentName
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
                boundaryEdgeCount: 4,
                internalEdgeCount: 0
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
                    message: "Direct B-spline surface source is represented by its stored degree, knot vectors, weights, control net, and source-owned rectangular outer trim domain."
                ),
            ] + trimDomainDiagnostics(
                trimDomain: trimDomain,
                trimsFullSurfaceDomain: trimsFullSurfaceDomain
            ) + patchBuildResult.diagnostics
        )
    }

    private func bSplinePatch(
        featureID: FeatureID,
        surface: BSplineSurface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        trimsFullSurfaceDomain: Bool,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay],
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay],
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) -> PatchBuildResult {
        let faceName = persistentName(featureID: featureID, subshape: "patch:0:face")
        let facePersistentName = persistentNameString(faceName)
        let surfaceReference = SurfaceReference(faceName: faceName)
        let faceSelectionReference: SelectionReference? = topologyEntriesByPersistentName[facePersistentName] == nil
            ? nil
            : .surface(.whole(surfaceReference))
        let edgePersistentNames = edgeRoles.map {
            persistentNameString(persistentName(featureID: featureID, subshape: "patch:0:\($0.subshape)"))
        }
        .filter { topologyEntriesByPersistentName[$0] != nil }
        let trimSelectionReferences = edgeRoles.enumerated().compactMap { index, role -> SelectionReference? in
            let edgeName = persistentNameString(
                persistentName(featureID: featureID, subshape: "patch:0:\(role.subshape)")
            )
            guard topologyEntriesByPersistentName[edgeName] != nil else {
                return nil
            }
            return .surface(.trim(SurfaceTrimReference(
                surface: surfaceReference,
                loopIndex: 0,
                    edgeIndex: index
                )))
        }
        let trimEdges = trimEdges(
            featureID: featureID,
            surface: surface,
            surfaceReference: surfaceReference,
            uBounds: uBounds,
            vBounds: vBounds,
            trimsFullSurfaceDomain: trimsFullSurfaceDomain,
            topologyEntriesByPersistentName: topologyEntriesByPersistentName
        )
        let basis = basis(surface: surface, surfaceReference: surfaceReference)
        let frameSampleResult = SurfaceSourceFrameSampleBuilder().buildSamples(
            featureID: featureID,
            patchID: 0,
            surface: surface,
            surfaceReference: surfaceReference,
            uSpans: clippedSpans(basis.uSpans, to: uBounds),
            vSpans: clippedSpans(basis.vSpans, to: vBounds),
            surfaceFrameDisplays: surfaceFrameDisplays
        )

        return PatchBuildResult(patch: SurfaceSourceSummaryResult.Patch(
            patchID: 0,
            facePersistentName: topologyEntriesByPersistentName[facePersistentName]?.persistentName,
            faceSelectionComponentID: topologyEntriesByPersistentName[facePersistentName]?.selectionComponentID,
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
            trimLoops: [
                SurfaceSourceSummaryResult.TrimLoop(
                    role: "outer",
                    parameterAddresses: cornerParameterAddresses(
                        surfaceReference: surfaceReference,
                        uBounds: uBounds,
                        vBounds: vBounds
                    ),
                    sourceVertexIndices: [],
                    edgePersistentNames: edgePersistentNames,
                    selectionReferences: trimSelectionReferences,
                    edges: trimEdges
                ),
            ],
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
        surfaceReference: SurfaceReference,
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
                let selectionReference = SelectionReference.surface(.controlPoint(SurfaceControlPointReference(
                    surface: surfaceReference,
                    uIndex: uIndex,
                    vIndex: vIndex
                )))
                result.append(SurfaceSourceSummaryResult.ControlPoint(
                    id: "feature:\(featureID.description)/patch:0/surfaceControlPoint:u\(uIndex):v\(vIndex)",
                    uIndex: uIndex,
                    vIndex: vIndex,
                    point: SurfaceSourceSummaryResult.Point(x: point.x, y: point.y, z: point.z),
                    weight: weight,
                    isBoundary: isBoundary,
                    isEditable: true,
                    selectionReference: selectionReference,
                    isPointDisplayVisible: isSurfaceControlPointDisplayVisible(
                        selectionReference,
                        in: surfaceControlPointDisplays
                    )
                ))
            }
        }
        return result
    }

    private func trimEdges(
        featureID: FeatureID,
        surface: BSplineSurface3D,
        surfaceReference: SurfaceReference,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        trimsFullSurfaceDomain: Bool,
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) -> [SurfaceSourceSummaryResult.TrimLoop.Edge] {
        BSplineSurfaceBoundarySide.allCases.enumerated().map { index, side in
            let edgePersistentName = persistentNameString(
                persistentName(featureID: featureID, subshape: "patch:0:edge:\(side.rawValue)")
            )
            let selectionReference: SelectionReference? = topologyEntriesByPersistentName[edgePersistentName] == nil
                ? nil
                : .surface(.trim(SurfaceTrimReference(
                    surface: surfaceReference,
                    loopIndex: 0,
                    edgeIndex: index
                )))
            let parameters = trimEdgeParameters(
                side: side,
                surfaceReference: surfaceReference,
                uBounds: uBounds,
                vBounds: vBounds
            )
            let levels = supportedBoundaryContinuityLevels(
                side: side,
                surface: surface,
                trimsFullSurfaceDomain: trimsFullSurfaceDomain,
                hasSelectionReference: selectionReference != nil
            )
            return SurfaceSourceSummaryResult.TrimLoop.Edge(
                index: index,
                role: side.rawValue,
                persistentName: edgePersistentName,
                selectionReference: selectionReference,
                startParameter: parameters.start,
                endParameter: parameters.end,
                boundaryDirection: side.boundaryDirection,
                inwardDirection: side.inwardDirection,
                boundaryControlPointReferences: trimsFullSurfaceDomain ? controlPointReferences(
                    side: side,
                    inwardOffset: 0,
                    surface: surface,
                    surfaceReference: surfaceReference
                ) : [],
                firstInwardControlPointReferences: trimsFullSurfaceDomain ? controlPointReferences(
                    side: side,
                    inwardOffset: 1,
                    surface: surface,
                    surfaceReference: surfaceReference
                ) : [],
                secondInwardControlPointReferences: trimsFullSurfaceDomain ? controlPointReferences(
                    side: side,
                    inwardOffset: 2,
                    surface: surface,
                    surfaceReference: surfaceReference
                ) : [],
                supportedBoundaryContinuityLevels: levels,
                supportsBoundaryContinuityMatching: levels.isEmpty == false,
                unsupportedReason: levels.isEmpty
                    ? unsupportedBoundaryContinuityReason(
                        side: side,
                        surface: surface,
                        trimsFullSurfaceDomain: trimsFullSurfaceDomain,
                        hasSelectionReference: selectionReference != nil
                    )
                    : nil
            )
        }
    }

    private func trimEdgeParameters(
        side: BSplineSurfaceBoundarySide,
        surfaceReference: SurfaceReference,
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
        surfaceReference: SurfaceReference
    ) -> [SelectionReference] {
        guard inwardOffset < boundaryProfileBuilder.inwardControlPointCount(for: side, in: surface) else {
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
        side: BSplineSurfaceBoundarySide,
        surface: BSplineSurface3D,
        trimsFullSurfaceDomain: Bool,
        hasSelectionReference: Bool
    ) -> [SurfaceBoundaryContinuityLevel] {
        guard hasSelectionReference else {
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
        side: BSplineSurfaceBoundarySide,
        surface: BSplineSurface3D,
        trimsFullSurfaceDomain: Bool,
        hasSelectionReference: Bool
    ) -> String? {
        if hasSelectionReference == false {
            return "Trim edge is not present in the evaluated topology summary."
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
        trimDomain: BSplineSurfaceTrimDomain,
        trimsFullSurfaceDomain: Bool
    ) -> [SurfaceSourceSummaryResult.Diagnostic] {
        guard trimsFullSurfaceDomain == false else {
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
        surfaceReference: SurfaceReference
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
        surfaceReference: SurfaceReference
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
                selectionReference: .surface(.knot(SurfaceKnotReference(
                    surface: surfaceReference,
                    direction: direction,
                    knotIndex: index
                )))
            )
        }
    }

    private func spans(
        direction: SurfaceParameterDirection,
        knots: [Double],
        degree: Int,
        surfaceReference: SurfaceReference
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
                selectionReference: .surface(.span(SurfaceSpanReference(
                    surface: surfaceReference,
                    direction: direction,
                    spanIndex: spanIndex
                )))
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
        surfaceReference: SurfaceReference,
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
                selectionReference: .surface(.parameter(SurfaceParameterReference(
                    surface: surfaceReference,
                    u: centerU,
                    v: centerV
                )))
            ),
        ]
    }

    private func cornerParameterAddresses(
        surfaceReference: SurfaceReference,
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
        surfaceReference: SurfaceReference,
        u: Double,
        v: Double
    ) -> SurfaceSourceSummaryResult.ParameterAddress {
        SurfaceSourceSummaryResult.ParameterAddress(
            id: id,
            u: u,
            v: v,
            selectionReference: .surface(.parameter(SurfaceParameterReference(
                surface: surfaceReference,
                u: u,
                v: v
            )))
        )
    }

    private func persistentName(featureID: FeatureID, subshape: String) -> PersistentName {
        PersistentName(components: [
            .feature(featureID),
            .generated("bSplineSurface"),
            .subshape(subshape),
        ])
    }

    private func persistentNameString(_ name: PersistentName) -> String {
        name.components.map { component in
            switch component {
            case .feature(let featureID):
                return "feature:\(featureID.description)"
            case .generated(let value):
                return "generated:\(value)"
            case .subshape(let value):
                return "subshape:\(value)"
            case .index(let index):
                return "index:\(index)"
            }
        }
        .joined(separator: "/")
    }
}
