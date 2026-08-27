import Foundation
import RupaCore
import RupaProject

/// Default bounded Mesh reader over one existing project authority.
public struct DefaultProjectMeshReader: ProjectMeshReading, Sendable {
    private let project: any ProjectOperating

    public init(project: any ProjectOperating) {
        self.project = project
    }

    public func catalog(
        from snapshot: ProjectViewSnapshot,
        limits: ProjectMeshReadLimits = .standard,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshCatalog {
        let state = try await ProjectMeshReadSupport.state(
            for: snapshot,
            project: project,
            operationGuard: operationGuard
        )
        let coordinate = ProjectAuthorityCoordinate(
            projectID: snapshot.projectID,
            transactionRevision: snapshot.transactionRevision,
            publicationSequence: snapshot.publicationSequence
        )
        let task = Task.detached(priority: nil) {
            try Task.checkCancellation()
            try limits.validate()
            var budget = ProjectMeshReadBudget(limits: limits)
            let sourceCount = state.document.authoredMeshAssets.count
            guard sourceCount <= limits.maxSources else {
                throw ProjectMeshReadError(
                    code: .limitExceeded,
                    message: "The Mesh catalog exceeds the source-count limit."
                )
            }
            try budget.consumeScanned(sourceCount, label: "source")
            let sourceIDs = state.document.authoredMeshAssets.keys.sorted {
                $0.rawValue < $1.rawValue
            }
            let referencesBySource = try ProjectMeshReadSupport.catalogReferences(
                in: state.document,
                budget: &budget
            )
            var sources: [ProjectMeshCatalogSource] = []
            sources.reserveCapacity(sourceIDs.count)
            for sourceID in sourceIDs {
                try Task.checkCancellation()
                guard let asset = state.document.authoredMeshAssets[sourceID] else {
                    throw ProjectMeshReadError(
                        code: .invalidSource,
                        message: "The Mesh source dictionary changed while building the catalog."
                    )
                }
                let handle = ProjectMeshSourceHandle(
                    projectAuthorityCoordinate: coordinate,
                    sourceID: sourceID,
                    contentIdentity: asset.contentIdentity
                )
                let source = try ProjectMeshSourceReadWorker(
                    handle: handle,
                    source: asset.source,
                    document: state.document,
                    limits: limits
                ).catalog(
                    references: referencesBySource[sourceID] ?? [],
                    budget: &budget
                )
                sources.append(source)
            }
            try Task.checkCancellation()
            return ProjectMeshCatalog(
                projectAuthorityCoordinate: coordinate,
                sources: sources
            )
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            _ = try await ProjectMeshReadSupport.state(
                for: snapshot,
                project: project,
                operationGuard: operationGuard
            )
            try Task.checkCancellation()
            return result
        } catch let error as ProjectMeshReadError {
            throw error
        } catch is CancellationError {
            throw ProjectMeshReadError(
                code: .cancelled,
                message: "The project Mesh catalog read was cancelled."
            )
        } catch {
            throw ProjectMeshReadError(
                code: .resultMismatch,
                message: "The project Mesh catalog read failed: \(error)."
            )
        }
    }

    public func page(
        _ request: ProjectMeshElementPageRequest,
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshElementPage {
        let state = try await ProjectMeshReadSupport.state(
            for: snapshot,
            project: project,
            operationGuard: operationGuard
        )
        try ProjectMeshReadSupport.validate(
            snapshot: snapshot,
            handle: request.handle,
            document: state.document
        )
        guard request.handle.projectAuthorityCoordinate
                == ProjectAuthorityCoordinate(
                    projectID: snapshot.projectID,
                    transactionRevision: snapshot.transactionRevision,
                    publicationSequence: snapshot.publicationSequence
                ) else {
            throw ProjectMeshReadError(
                code: .resultMismatch,
                message: "The Mesh page handle coordinate does not match the supplied view."
            )
        }
        let asset = try ProjectMeshReadSupport.requireAsset(
            for: request.handle,
            in: state.document
        )
        let task = Task.detached(priority: nil) {
            try Task.checkCancellation()
            var budget = ProjectMeshReadBudget(limits: request.limits)
            return try ProjectMeshSourceReadWorker(
                handle: request.handle,
                source: asset.source,
                document: state.document,
                limits: request.limits
            ).page(
                domain: request.domain,
                cursor: request.cursor,
                budget: &budget
            )
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            _ = try await ProjectMeshReadSupport.state(
                for: snapshot,
                project: project,
                operationGuard: operationGuard
            )
            try Task.checkCancellation()
            return result
        } catch let error as ProjectMeshReadError {
            throw error
        } catch is CancellationError {
            throw ProjectMeshReadError(
                code: .cancelled,
                message: "The project Mesh page read was cancelled."
            )
        } catch {
            throw ProjectMeshReadError(
                code: .resultMismatch,
                message: "The project Mesh page read failed: \(error)."
            )
        }
    }

    public func neighborhood(
        _ request: ProjectMeshNeighborhoodRequest,
        from snapshot: ProjectViewSnapshot,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectMeshNeighborhood {
        let state = try await ProjectMeshReadSupport.state(
            for: snapshot,
            project: project,
            operationGuard: operationGuard
        )
        try ProjectMeshReadSupport.validate(
            snapshot: snapshot,
            handle: request.handle,
            document: state.document
        )
        let asset = try ProjectMeshReadSupport.requireAsset(
            for: request.handle,
            in: state.document
        )
        let task = Task.detached(priority: nil) {
            try Task.checkCancellation()
            var budget = ProjectMeshReadBudget(limits: request.limits)
            return try ProjectMeshSourceReadWorker(
                handle: request.handle,
                source: asset.source,
                document: state.document,
                limits: request.limits
            ).neighborhood(
                origin: request.origin,
                depth: request.depth,
                budget: &budget
            )
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            _ = try await ProjectMeshReadSupport.state(
                for: snapshot,
                project: project,
                operationGuard: operationGuard
            )
            try Task.checkCancellation()
            return result
        } catch let error as ProjectMeshReadError {
            throw error
        } catch is CancellationError {
            throw ProjectMeshReadError(
                code: .cancelled,
                message: "The project Mesh neighborhood read was cancelled."
            )
        } catch {
            throw ProjectMeshReadError(
                code: .resultMismatch,
                message: "The project Mesh neighborhood read failed: \(error)."
            )
        }
    }
}
