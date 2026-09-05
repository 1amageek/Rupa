import RupaCore
import RupaGeometry
import RupaKit

struct MeshOperationDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case translate = "Move Elements"
        case position = "Set Vertex Position"
        case extrude = "Extrude Faces"
        case delete = "Delete Faces"
        case addFace = "Add Face"
        var id: String { rawValue }
    }

    let sourceID: GeometrySourceID
    let contentIdentity: ContentIdentity
    let occurrenceID: SceneOccurrenceID
    var elements: [MeshSelectionElement] = []
    var kind = Kind.translate
    var coordinates = ["0", "0", "0"]
    var unit: LengthDisplayUnit

    mutating func select(_ element: MeshSelectionElement, toggle: Bool) throws {
        if !toggle { elements = [element]; return }
        if let index = elements.firstIndex(of: element) { elements.remove(at: index) }
        else {
            guard elements.count < MeshEditLimits.standard.maxSelectedIDs else {
                throw EditorError(code: .commandInvalid, message: "Mesh selection exceeds the edit limit.")
            }
            elements.append(element)
        }
    }

    func request(from snapshot: ProjectViewSnapshot) throws -> ProjectMeshEditRequest {
        guard elements.count <= MeshEditLimits.standard.maxSelectedIDs else {
            throw EditorError(code: .commandInvalid, message: "Mesh selection exceeds the edit limit.")
        }
        guard let nodeID = snapshot.sceneNodeIDByOccurrenceID[occurrenceID],
              let node = snapshot.document.document.productMetadata.sceneNodes[nodeID], !node.isLocked,
              snapshot.viewport.items.contains(where: { $0.id == occurrenceID && $0.reference == .authoredMesh(sourceID) }) else {
            throw EditorError(code: .commandInvalid, message: "The selected Mesh occurrence is missing, locked, or no longer presents this source.")
        }
        guard let asset = snapshot.document.document.authoredMeshAssets[sourceID],
              asset.contentIdentity == contentIdentity else {
            throw EditorError(code: .commandInvalid, message: "The Mesh source changed. Select its elements again.")
        }
        // Workspace validates source membership off MainActor while staging.
        let selection = try MeshSelectionSet(elements: elements)
        guard !selection.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "Select Mesh elements in the canvas.")
        }
        let operation: MeshEditOperation
        switch kind {
        case .translate, .extrude, .position:
            guard coordinates.count == 3 else {
                throw EditorError(code: .commandInvalid, message: "Mesh coordinates require X, Y and Z.")
            }
            let values = try coordinates.map { text -> Double in
                guard let value = workspaceLengthMeters(fromFieldText: text, defaultUnit: unit), value.isFinite else {
                    throw EditorError(code: .commandInvalid, message: "Enter finite source-coordinate lengths with valid units.")
                }
                return value
            }
            if kind == .position {
                guard elements.count == 1, case .vertex(let id) = elements[0] else {
                    throw EditorError(code: .commandInvalid, message: "Select exactly one Mesh vertex to set its position.")
                }
                operation = .primitive(.setVertexPositions([try MeshVertexPositionEdit(vertexID: id, position: GeometryPoint3D(x: values[0], y: values[1], z: values[2]))]))
            } else {
                guard values.contains(where: { $0 != 0 }) else {
                    throw EditorError(code: .commandInvalid, message: "The movement vector must be non-zero.")
                }
                let offset = GeometryVector3D(x: values[0], y: values[1], z: values[2])
                operation = kind == .translate ? .translateElements(.explicit(selection), offset: offset) : .extrudeFaces(.explicit(selection), offset: offset)
            }
        case .delete:
            operation = .primitive(.deleteFaces(.explicit(selection)))
        case .addFace:
            let vertices = elements.compactMap { element -> MeshVertexID? in
                if case .vertex(let id) = element { return id }; return nil
            }
            guard vertices.count == elements.count, vertices.count >= 3 else {
                throw EditorError(code: .commandInvalid, message: "Select at least three vertices in boundary order to add a face.")
            }
            operation = .primitive(.addFace(vertexIDs: vertices))
        }
        return ProjectMeshEditRequest(
            handle: ProjectMeshSourceHandle(projectAuthorityCoordinate: snapshot.authorityCoordinate, sourceID: sourceID, contentIdentity: contentIdentity),
            plan: try MeshEditPlan(steps: [MeshEditStep(id: MeshEditStepID("ui.edit"), operation: operation)]),
            snapshot: snapshot, name: kind.rawValue
        )
    }

    static func title(_ element: MeshSelectionElement) -> String {
        switch element {
        case .vertex(let id): "Vertex \(id.rawValue)"
        case .edge(let id): "Edge \(id.rawValue)"
        case .face(let id): "Face \(id.rawValue)"
        case .corner(let id): "Corner \(id.rawValue)"
        }
    }
}
