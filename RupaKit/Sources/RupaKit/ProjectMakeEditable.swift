import RupaProject

/// Transport-neutral CAD Make Editable use case.
public protocol ProjectMakeEditable: Sendable {
    func makeEditable(
        _ request: ProjectMakeEditableRequest,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectMakeEditableResult
}

public extension ProjectMakeEditable {
    func makeEditable(
        _ request: ProjectMakeEditableRequest,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMakeEditableResult {
        try await makeEditable(request, operationGuard: operationGuard)
    }
}
