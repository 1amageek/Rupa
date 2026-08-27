import RupaGeometry

public struct ProjectMeshEditRequest: Sendable {
    public let handle: ProjectMeshSourceHandle
    public let plan: MeshEditPlan
    public let snapshot: ProjectViewSnapshot
    public let name: String

    public init(
        handle: ProjectMeshSourceHandle,
        plan: MeshEditPlan,
        snapshot: ProjectViewSnapshot,
        name: String = "mesh.edit"
    ) {
        self.handle = handle
        self.plan = plan
        self.snapshot = snapshot
        self.name = name
    }

    public init(
        handle: ProjectMeshSourceHandle,
        plan: MeshEditPlan,
        view: ProjectViewSnapshot,
        name: String = "mesh.edit"
    ) {
        self.init(handle: handle, plan: plan, snapshot: view, name: name)
    }
}
