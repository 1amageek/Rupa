import SwiftCAD

struct BSplineSurfaceSourceSummaryBuilder: Sendable {
    private struct SurfaceEdgeRole {
        var subshape: String
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
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) -> SurfaceSourceSummaryResult.Source? {
        let surface = surfaceFeature.surface
        guard case let .closed(uLower, uUpper) = surface.uDomain,
              case let .closed(vLower, vUpper) = surface.vDomain else {
            return nil
        }
        let patch = bSplinePatch(
            featureID: featureID,
            surface: surface,
            uBounds: (uLower, uUpper),
            vBounds: (vLower, vUpper),
            surfaceControlPointDisplays: surfaceControlPointDisplays,
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
            patches: [patch],
            adjacencies: [],
            diagnostics: [
                SurfaceSourceSummaryResult.Diagnostic(
                    severity: "info",
                    code: "directBSplineSurface",
                    message: "Direct B-spline surface source is represented by its stored degree, knot vectors, weights, control net, and rectangular trim loop."
                ),
            ]
        )
    }

    private func bSplinePatch(
        featureID: FeatureID,
        surface: BSplineSurface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay],
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) -> SurfaceSourceSummaryResult.Patch {
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
        return SurfaceSourceSummaryResult.Patch(
            patchID: 0,
            facePersistentName: topologyEntriesByPersistentName[facePersistentName]?.persistentName,
            faceSelectionComponentID: topologyEntriesByPersistentName[facePersistentName]?.selectionComponentID,
            faceSelectionReference: faceSelectionReference,
            uDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: uBounds.lower, upperBound: uBounds.upper),
            vDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: vBounds.lower, upperBound: vBounds.upper),
            basis: basis(surface: surface, surfaceReference: surfaceReference),
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
                    selectionReferences: trimSelectionReferences
                ),
            ],
            parameterAddresses: patchParameterAddresses(
                surfaceReference: surfaceReference,
                uBounds: uBounds,
                vBounds: vBounds
            )
        )
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
