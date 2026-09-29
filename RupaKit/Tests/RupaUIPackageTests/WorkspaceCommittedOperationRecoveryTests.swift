import Foundation
import RupaCore
import RupaEvaluation
import RupaKit
import RupaProject
import Synchronization
import Testing
@testable import RupaUI

/// An edit that commits while its view fails is never replayed: the committed view is rebuilt
/// before anything else plans against it, or editing stops and says why.
@MainActor
@Suite struct WorkspaceCommittedOperationRecoveryTests {
    private enum ViewFailure: Error {
        case projectionFailed
    }

    /// Fails the view builds whose ordinal `fails` accepts (the first build is the initial view).
    private final class FailingViewBuilder: ProjectViewSnapshotBuilding, Sendable {
        private let count = Mutex(0)
        private let fails: @Sendable (Int) -> Bool

        init(fails: @escaping @Sendable (Int) -> Bool) {
            self.fails = fails
        }

        func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot {
            let ordinal = count.withLock { count in
                count += 1
                return count
            }
            if fails(ordinal) {
                throw ViewFailure.projectionFailed
            }
            return try ProjectViewSnapshotBuilder().build(from: state)
        }
    }

    private func workspace(failing fails: @escaping @Sendable (Int) -> Bool) async throws -> (ProjectWorkspace, ProjectViewSnapshot) {
        let controller = try ProjectController(
            document: .empty(named: "Before"),
            evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
            projector: DesignDocumentProjectBridge()
        )
        let workspace = ProjectWorkspace(project: controller, viewBuilder: FailingViewBuilder(fails: fails))
        return (workspace, try await workspace.evaluate())
    }

    private func rename(_ workspace: ProjectWorkspace, from snapshot: ProjectViewSnapshot, to name: String) async throws {
        let action = try DefaultProjectWorkspaceActionPlanner().source(
            name: "rename", commands: [.renameDocument(name: name)], from: snapshot
        )
        _ = try await workspace.perform(action)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCommittedEditWhoseViewFailedShowsTheEditAndIsNotReplayed() async throws {
        // Build 2 is the rename's view; build 3, the recovery, succeeds.
        let (workspace, before) = try await workspace { $0 == 2 }
        let recovery = WorkspaceCommittedOperationRecovery(workspace: workspace)
        var runs = 0
        await #expect(throws: WorkspaceCommittedOperationError.self) {
            try await recovery.run {
                runs += 1
                try await rename(workspace, from: before, to: "After")
            }
        }
        #expect(runs == 1)
        let view = try #require(workspace.view)
        #expect(view.document.document.cadDocument.metadata.name == "After")
        #expect(view.publicationSequence > before.publicationSequence)
        #expect(recovery.unavailableReason == nil)
        // The next edit plans against the recovered view and commits.
        try await recovery.run {
            try await rename(workspace, from: view, to: "Again")
        }
        #expect(workspace.view?.document.document.cadDocument.metadata.name == "Again")
    }

    @Test(.timeLimit(.minutes(1)))
    func aViewThatCannotBeRebuiltStopsEditing() async throws {
        let (workspace, before) = try await workspace { $0 >= 2 }
        let recovery = WorkspaceCommittedOperationRecovery(workspace: workspace)
        var caught: WorkspaceCommittedOperationError?
        do {
            try await recovery.run {
                try await rename(workspace, from: before, to: "After")
            }
        } catch let error as WorkspaceCommittedOperationError {
            caught = error
        }
        guard case .unrecovered = try #require(caught) else {
            Issue.record("A view that cannot be rebuilt must be reported as unrecovered, not \(String(describing: caught)).")
            return
        }
        #expect(recovery.unavailableReason != nil)
        #expect(throws: WorkspaceCommittedOperationError.self) {
            try recovery.checkAvailable()
        }
        var ranAfterwards = false
        await #expect(throws: WorkspaceCommittedOperationError.self) {
            try await recovery.run { ranAfterwards = true }
        }
        #expect(!ranAfterwards)
    }

    @Test(.timeLimit(.minutes(1)))
    func anOrdinaryFailurePassesThroughAndEditingContinues() async throws {
        let recovery = WorkspaceCommittedOperationRecovery { _ in
            Issue.record("An ordinary failure has no committed view to recover.")
        }
        await #expect(throws: ViewFailure.self) {
            try await recovery.run { throw ViewFailure.projectionFailed }
        }
        #expect(recovery.unavailableReason == nil)
        try recovery.checkAvailable()
    }
}
