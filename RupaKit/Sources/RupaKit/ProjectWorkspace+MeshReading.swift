import RupaProject

extension ProjectWorkspace {
    public func catalog(
        from snapshot: ProjectViewSnapshot,
        limits: ProjectMeshReadLimits = .standard,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshCatalog {
        try await DefaultProjectMeshReader(project: projectAuthorityOwner).catalog(
            from: snapshot,
            limits: limits,
            operationGuard: operationGuard
        )
    }

    public func page(
        _ request: ProjectMeshElementPageRequest,
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshElementPage {
        try await DefaultProjectMeshReader(project: projectAuthorityOwner).page(
            request,
            from: snapshot,
            operationGuard: operationGuard
        )
    }

    public func neighborhood(
        _ request: ProjectMeshNeighborhoodRequest,
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshNeighborhood {
        try await DefaultProjectMeshReader(project: projectAuthorityOwner).neighborhood(
            request,
            from: snapshot,
            operationGuard: operationGuard
        )
    }
}
