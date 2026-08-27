import RupaCoreTypes

/// Identity-only intent for promoting one CAD modeling representation to an
/// Authored Mesh source. The caller must bind the request to a complete view.
public struct ProjectMakeEditableRequest: Sendable {
    public let snapshot: ProjectViewSnapshot
    public let sceneNodeID: SceneNodeID
    public let authoredMeshSourceID: GeometrySourceID
    public let authoredMeshRepresentationID: GeometryRepresentationID
    public let switchesPresentationSelection: Bool
    public let name: String

    public init(
        snapshot: ProjectViewSnapshot,
        sceneNodeID: SceneNodeID,
        authoredMeshSourceID: GeometrySourceID,
        authoredMeshRepresentationID: GeometryRepresentationID,
        switchesPresentationSelection: Bool = true,
        name: String = "cad.make-editable"
    ) {
        self.snapshot = snapshot
        self.sceneNodeID = sceneNodeID
        self.authoredMeshSourceID = authoredMeshSourceID
        self.authoredMeshRepresentationID = authoredMeshRepresentationID
        self.switchesPresentationSelection = switchesPresentationSelection
        self.name = name
    }
}
