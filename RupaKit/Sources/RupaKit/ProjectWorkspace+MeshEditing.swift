import RupaProject

extension ProjectWorkspace {
    /// Stages one Mesh edit and returns the existing candidate render payload.
    /// The Mesh adapter validates the request and exact authority coordinates;
    /// this overload does not publish a project view or re-evaluate the edit.
    public func previewRenderPayload(
        _ request: ProjectMeshEditRequest,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectPreviewRenderPayload {
        try await DefaultProjectMeshEditor(workspace: self).previewRenderPayload(
            request,
            operationGuard: operationGuard
        )
    }

    public func preview(
        _ request: ProjectMeshEditRequest,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshEditPreviewResult {
        try await DefaultProjectMeshEditor(workspace: self).preview(
            request,
            operationGuard: operationGuard
        )
    }

    public func commit(
        _ request: ProjectMeshEditRequest,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshEditCommitResult {
        try await DefaultProjectMeshEditor(workspace: self).commit(
            request,
            operationGuard: operationGuard
        )
    }
}
