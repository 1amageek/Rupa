import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// The B-spline surface feature a sheet is presented straight from, when `targets` lie on such
    /// a sheet with no later feature: its edges and corners then move on the surface's control
    /// net rather than through a kernel direct edit.
    func directSurfaceSource(for targets: [SelectionTarget]) -> FeatureID? {
        guard let first = targets.first,
              let featureID = productMetadata.sceneNodes[first.sceneNodeID]?.reference?.featureID,
              case .bSplineSurface = cadDocument.designGraph.nodes[featureID]?.operation else { return nil }
        return featureID
    }

    /// Moves the control points under the targeted edges, corners or face of the untrimmed
    /// B-spline sheet `featureID` by `motion`, in the sheet's own coordinates.
    ///
    /// A clamped surface interpolates its corner control points and its boundary curves are its
    /// boundary rows, so moving a corner point moves that corner and moving a boundary row moves
    /// that edge, both exactly; an affine motion of control points is the same motion of the
    /// curve they define. The surface is replaced together with its checks or not at all.
    mutating func editSurfaceBoundary(
        _ kind: BodyTopologyMoveKind,
        targets: [SelectionTarget],
        featureID: FeatureID,
        motion: Transform3D,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) throws {
        let owner = kind.title
        guard targets.allSatisfy({ $0.sceneNodeID == targets.first?.sceneNodeID }) else {
            throw EditorError(code: .commandInvalid, message: "\(owner) moves the parts of one body at a time.")
        }
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case .bSplineSurface(var surfaceFeature) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) needs the sheet's B-spline surface source.")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): a trimmed sheet's edges are not boundary rows of its
        // control net, so moving them is refused here. Production path: G, R and S on edges,
        // corners and faces of a B-spline sheet shown straight from its source. Complete when a
        // trimmed boundary moves through the kernel with its own tests.
        guard surfaceFeature.parameterDomain == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) moves the edges of an untrimmed B-spline sheet; move a trimmed sheet's control points instead."
            )
        }
        let evaluated = try DocumentEvaluationContextResolver().exactEvaluatedDocument(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration,
            failurePrefix: owner
        )
        let net = surfaceFeature.surface.controlPoints
        let rowCount = net.count
        guard rowCount >= 2, let columnCount = net.first?.count, columnCount >= 2 else {
            throw EditorError(code: .commandInvalid, message: "\(owner) needs a surface net of at least 2 × 2 points.")
        }
        let tolerance = modelingSettings.tolerance.distance
        let corners = [(0, 0), (0, columnCount - 1), (rowCount - 1, 0), (rowCount - 1, columnCount - 1)]
        func corner(at point: Point3D) throws -> (v: Int, u: Int) {
            guard let match = corners.first(where: { (net[$0.0][$0.1] - point).length <= tolerance }) else {
                throw EditorError(code: .commandInvalid, message: "\(owner) found a target away from the surface's corners.")
            }
            return (match.0, match.1)
        }

        var moved: Set<[Int]> = []
        for target in targets {
            let componentID: SelectionComponentID
            switch (kind, target.component) {
            case (.edges, .edge(let id)), (.faces, .face(let id)), (.vertices, .vertex(let id)): componentID = id
            default:
                throw EditorError(code: .commandInvalid, message: "\(owner) applies to \(kind.noun.lowercased()) only.")
            }
            guard let subshapeID = componentID.generatedTopologySubshapeID, subshapeID.featureID == featureID,
                  let reference = evaluated.subshapes.entries[subshapeID] else {
                throw EditorError(code: .referenceUnresolved, message: "The selected subshape is absent from the sheet. Select it again.")
            }
            switch reference {
            case .vertex(let id):
                guard let point = evaluated.brep.vertices[id]?.point else {
                    throw EditorError(code: .referenceUnresolved, message: "\(owner) found no point for the selected corner.")
                }
                let index = try corner(at: point)
                moved.insert([index.v, index.u])
            case .edge(let id):
                guard let edge = evaluated.brep.edges[id],
                      let start = evaluated.brep.vertices[edge.startVertexID]?.point,
                      let end = evaluated.brep.vertices[edge.endVertexID]?.point else {
                    throw EditorError(code: .referenceUnresolved, message: "\(owner) found no ends for the selected edge.")
                }
                let a = try corner(at: start), b = try corner(at: end)
                if a.v == b.v, a.u != b.u {
                    for u in 0..<columnCount { moved.insert([a.v, u]) }
                } else if a.u == b.u, a.v != b.v {
                    for v in 0..<rowCount { moved.insert([v, a.u]) }
                } else {
                    throw EditorError(code: .commandInvalid, message: "\(owner) found an edge that is not a boundary row of the surface.")
                }
            case .face:
                for v in 0..<rowCount { for u in 0..<columnCount { moved.insert([v, u]) } }
            default:
                throw EditorError(code: .commandInvalid, message: "\(owner) applies to edges, corners and faces.")
            }
        }
        for index in moved {
            surfaceFeature.surface.controlPoints[index[0]][index[1]] = try motion.applied(to: net[index[0]][index[1]])
        }
        try surfaceFeature.validate(tolerance: modelingSettings.tolerance)
        feature.operation = .bSplineSurface(surfaceFeature)
        let previousCADDocument = cadDocument
        do {
            try cadDocument.replaceFeature(feature, tolerance: modelingSettings.tolerance)
            try validate(objectRegistry: objectRegistry)
            _ = try DocumentEvaluationContextResolver().exactEvaluatedDocument(
                document: self, objectRegistry: objectRegistry,
                currentEvaluation: nil, currentGeneration: nil, failurePrefix: owner
            )
        } catch {
            cadDocument = previousCADDocument
            throw EditorError(code: .commandInvalid, message: "\(owner) produced invalid sheet geometry: \(error.localizedDescription)")
        }
    }
}
