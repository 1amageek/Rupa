import Foundation
import RupaCore
import RupaGeometry
import RupaViewportScene
import SwiftCAD

extension ViewportSpatialOverlayProducer {
    /// Preview the actual source edges, not a bounding-box substitute. The one
    /// output position buffer is required by the native overlay boundary.
    static func appendPresentationTransformPreviews(
        input: SurfaceTransformAffordanceSource.RawInput,
        checkpoint: (Int, Int, Int) throws -> Void,
        meshes: inout [SurfaceTransformAffordanceSource.Mesh]
    ) throws {
        guard let scene = input.presentationScene, !input.bodyPreviewTransforms.isEmpty else { return }
        for item in scene.items {
            guard let mutation = input.bodyPreviewTransforms[item.occurrenceID.rawValue] else { continue }
            let source = item.mesh
            let indexCount = source.edgeEndpoints.count.multipliedReportingOverflow(by: 2)
            guard !indexCount.overflow else { throw RealityViewportSpatialBatch.exhausted() }
            try checkpoint(1, source.vertexPositions.count, indexCount.partialValue)
            guard source.vertexPositions.count <= Int(UInt32.max) else { throw RealityViewportSpatialBatch.exhausted() }
            let index = try source.makeTriangulationIndex()
            var positions: [Point3D] = []
            positions.reserveCapacity(source.vertexPositions.count)
            for point in source.vertexPositions {
                try Task.checkCancellation()
                let world = try item.worldTransform.applying(to: point)
                positions.append(try ViewportWorldTransformAlgebra.transformedPoint(
                    Point3D(x: world.x, y: world.y, z: world.z), by: mutation))
            }
            var indices: [UInt32] = []
            indices.reserveCapacity(indexCount.partialValue)
            for edge in source.edgeEndpoints {
                try Task.checkCancellation()
                guard let a = index.positionIndex(for: edge.start), let b = index.positionIndex(for: edge.end) else {
                    throw RealityViewportSpatialBatch.invalid("Mesh preview edge has no source vertex.")
                }
                indices.append(UInt32(a)); indices.append(UInt32(b))
            }
            guard !indices.isEmpty else { continue }
            meshes.append(.init(route: .bodyTransform, positions: positions, indices: indices,
                                topology: .lines, color: editColor, family: .transform,
                                identity: nil, state: .preview, occurrenceID: item.occurrenceID.rawValue))
        }
    }

    /// Admit the whole selected set or none, using the presentation's actual
    /// occurrence addresses. Geometry is borrowed; only placement values survive.
    static func presentationTransformMembers(
        input: SurfaceTransformAffordanceSource.RawInput
    ) throws -> [ViewportObjectTransformMember]? {
        guard let scene = input.presentationScene, !input.selection.selectedTargets.isEmpty,
              input.selection.selectedTargets.allSatisfy({ $0.component == .object }) else { return nil }
        let selected = Set(input.selection.selectedTargets.map(\.sceneNodeID))
        let frames = try ViewportSceneNodeParentFrames(document: input.document)
        var members: [ViewportObjectTransformMember] = []
        var admitted: Set<SceneNodeID> = []
        for item in scene.items {
            try Task.checkCancellation()
            guard let nodeID = input.presentationNodeIDs[item.occurrenceID], selected.contains(nodeID) else { continue }
            guard admitted.insert(nodeID).inserted,
                  let node = input.document.productMetadata.sceneNodes[nodeID], !node.isLocked,
                  node.object?.componentInstanceID == nil, let reference = node.reference,
                  reference.kind == .body || reference.kind == .authoredMesh,
                  let object = node.object, let selection = object.geometryRepresentations.selection,
                  selection.presentation == item.representationID,
                  object.geometryRepresentations.representations[item.representationID]?.source == item.reference,
                  let parent = try frames.parentWorldTransform(of: nodeID) else { return nil }
            switch item.reference {
            case .authoredMesh(let source):
                guard input.document.authoredMeshAssets[source] != nil else { return nil }
            case .cad(let source, let output):
                guard source == input.document.id.description,
                      let id = UUID(uuidString: output),
                      input.document.cadDocument.designGraph.nodes[FeatureID(id)] != nil else { return nil }
            default: return nil
            }
            let world = item.worldBounds
            var bounds = ViewportObjectEditState(
                xMin: CGFloat(world.minimum.x), xMax: CGFloat(world.maximum.x),
                yMin: CGFloat(world.minimum.y), yMax: CGFloat(world.maximum.y),
                zMin: CGFloat(world.minimum.z), zMax: CGFloat(world.maximum.z))
            if let mutation = input.bodyPreviewTransforms[item.occurrenceID.rawValue] {
                let points = try bounds.worldBoxCorners.map { try ViewportWorldTransformAlgebra.transformedPoint($0, by: mutation) }
                bounds = .init(xMin: CGFloat(points.map(\.x).min()!), xMax: CGFloat(points.map(\.x).max()!),
                               yMin: CGFloat(points.map(\.y).min()!), yMax: CGFloat(points.map(\.y).max()!),
                               zMin: CGFloat(points.map(\.z).min()!), zMax: CGFloat(points.map(\.z).max()!))
            }
            members.append(.init(occurrenceID: item.occurrenceID.rawValue, reference: reference,
                                 sceneNodeID: nodeID, baseLocalTransform: node.localTransform,
                                 parentWorldTransform: parent, bounds: bounds))
        }
        return admitted == selected ? members : nil
    }
}
