import RupaProject

extension ProjectWorkspace {
    public func makeEditable(
        _ request: ProjectMakeEditableRequest,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMakeEditableResult {
        try await DefaultProjectMakeEditable(workspace: self).makeEditable(
            request,
            operationGuard: operationGuard
        )
    }
}
