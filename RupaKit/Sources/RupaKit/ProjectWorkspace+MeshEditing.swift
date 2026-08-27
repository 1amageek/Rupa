import RupaProject

extension ProjectWorkspace {
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
