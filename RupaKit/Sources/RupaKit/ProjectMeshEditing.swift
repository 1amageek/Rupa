import RupaProject

public protocol ProjectMeshEditing: Sendable {
    func preview(
        _ request: ProjectMeshEditRequest,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectMeshEditPreviewResult

    func commit(
        _ request: ProjectMeshEditRequest,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectMeshEditCommitResult
}

public extension ProjectMeshEditing {
    func preview(
        _ request: ProjectMeshEditRequest,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshEditPreviewResult {
        try await preview(request, operationGuard: operationGuard)
    }

    func commit(
        _ request: ProjectMeshEditRequest,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshEditCommitResult {
        try await commit(request, operationGuard: operationGuard)
    }
}
