import RupaProject

public protocol ProjectMeshReading: Sendable {
    func catalog(
        from snapshot: ProjectViewSnapshot,
        limits: ProjectMeshReadLimits,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectMeshCatalog

    func page(
        _ request: ProjectMeshElementPageRequest,
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectMeshElementPage

    func neighborhood(
        _ request: ProjectMeshNeighborhoodRequest,
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectMeshNeighborhood
}

public extension ProjectMeshReading {
    func catalog(
        from snapshot: ProjectViewSnapshot,
        limits: ProjectMeshReadLimits = .standard,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshCatalog {
        try await catalog(
            from: snapshot,
            limits: limits,
            operationGuard: operationGuard
        )
    }

    func page(
        _ request: ProjectMeshElementPageRequest,
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshElementPage {
        try await page(
            request,
            from: snapshot,
            operationGuard: operationGuard
        )
    }

    func neighborhood(
        _ request: ProjectMeshNeighborhoodRequest,
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshNeighborhood {
        try await neighborhood(
            request,
            from: snapshot,
            operationGuard: operationGuard
        )
    }
}
