import Foundation
import Observation
import RupaCoreTypes
import RupaProject

/// Main-actor observation adapter for one project-operation owner.
@MainActor
@Observable
public final class ProjectWorkspace {
    public private(set) var view: ProjectViewSnapshot?

    @ObservationIgnored
    private let project: any ProjectOperating
    @ObservationIgnored
    private let viewBuilder: ProjectViewSnapshotBuilder

    public init(
        project: any ProjectOperating,
        viewBuilder: ProjectViewSnapshotBuilder = ProjectViewSnapshotBuilder()
    ) {
        self.project = project
        self.viewBuilder = viewBuilder
    }

    @discardableResult
    public func refresh() async throws -> ProjectViewSnapshot {
        try await publish(try await project.currentState())
    }

    @discardableResult
    public func evaluate() async throws -> ProjectViewSnapshot {
        _ = try await project.evaluateCurrent()
        return try await publish(try await project.currentState())
    }

    @discardableResult
    public func commit(
        _ transaction: ProjectSourceTransaction
    ) async throws -> ProjectViewSnapshot {
        _ = try await project.commit(transaction)
        return try await publish(try await project.currentState())
    }

    @discardableResult
    public func undo() async throws -> ProjectViewSnapshot {
        let revision = try currentTransactionRevision()
        return try await publish(
            try await project.undo(expectedTransactionRevision: revision)
        )
    }

    @discardableResult
    public func redo() async throws -> ProjectViewSnapshot {
        let revision = try currentTransactionRevision()
        return try await publish(
            try await project.redo(expectedTransactionRevision: revision)
        )
    }

    @discardableResult
    public func load(from url: URL) async throws -> ProjectViewSnapshot {
        let revision: DocumentTransactionRevision
        if let view {
            revision = view.transactionRevision
        } else {
            revision = await project.currentTransactionRevision()
        }
        return try await publish(
            try await project.load(
                from: url,
                expectedTransactionRevision: revision
            )
        )
    }

    @discardableResult
    public func save(to url: URL) async throws -> ProjectViewSnapshot {
        let revision = try currentTransactionRevision()
        _ = try await project.save(
            to: url,
            expectedTransactionRevision: revision
        )
        return try await publish(try await project.currentState())
    }

    @discardableResult
    func publish(_ state: ProjectStateSnapshot) async throws -> ProjectViewSnapshot {
        if let view,
           state.publicationSequence <= view.publicationSequence {
            return view
        }
        let builder = viewBuilder
        let candidate = try await Task.detached(priority: nil) {
            try builder.build(from: state)
        }.value
        if let view,
           candidate.publicationSequence <= view.publicationSequence {
            return view
        }
        view = candidate
        return candidate
    }

    private func currentTransactionRevision() throws -> DocumentTransactionRevision {
        guard let view else {
            throw ProjectViewSnapshotError(
                code: .snapshotUnavailable,
                message: "The project workspace has no published view snapshot."
            )
        }
        return view.transactionRevision
    }
}
