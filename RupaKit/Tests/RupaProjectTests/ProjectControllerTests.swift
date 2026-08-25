import Foundation
import Synchronization
import SwiftCAD
import Testing
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaProjectPackage
@testable import RupaProject

@Test(.timeLimit(.minutes(1)))
func projectControllerPublishesCADPackageAndEvaluationAfterValidation() async throws {
    let controller = try makeController(document: .empty(named: "Before"))
    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.rename",
            commands: [.renameDocument(name: "After")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )

    #expect(result.baseTransactionRevision == DocumentTransactionRevision(0))
    #expect(result.transactionRevision == DocumentTransactionRevision(1))
    #expect(result.documentGeneration == DocumentGeneration(1))
    #expect(result.document.cadDocument.metadata.name == "After")
    #expect(result.package.source.name == "After")
    #expect(result.evaluation.projectID == result.package.source.id)
    #expect(result.commandResults.count == 1)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "After")
    #expect(await controller.currentSource().name == "After")
    #expect(await controller.currentPackage().cadSource == result.package.cadSource)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerDoesNotPublishWhenEvaluationFails() async throws {
    let initial = DesignDocument.empty(named: "Before")
    let controller = try makeController(
        document: initial,
        evaluator: FailingProjectEvaluator()
    )
    let initialPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.failure",
                commands: [.renameDocument(name: "Never Published")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .evaluationFailed)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")
    #expect(await controller.currentSource().name == "Before")
    #expect(await controller.currentPackage().cadSource == initialPackage.cadSource)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsStaleRequestBeforeStaging() async throws {
    let controller = try makeController(document: .empty(named: "Before"))
    _ = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.first",
            commands: [.renameDocument(name: "Committed")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.stale",
                commands: [.renameDocument(name: "Rejected")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .revisionConflict)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Committed")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsPublicationWhenConcurrentCallerWins() async throws {
    let gate = BlockingEvaluationGate()
    let controller = try makeController(
        document: .empty(named: "Before"),
        evaluator: BlockingProjectEvaluator(gate: gate)
    )
    let first = Task {
        try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.first",
                commands: [.renameDocument(name: "First")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    }
    while !gate.didStartFirstEvaluation {
        try await Task.sleep(for: .milliseconds(1))
    }

    let second = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.second",
            commands: [.renameDocument(name: "Second")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )
    gate.releaseFirstEvaluation()

    var firstError: ProjectControllerError?
    do {
        _ = try await first.value
    } catch let error as ProjectControllerError {
        firstError = error
    }
    #expect(firstError?.code == .revisionConflict)
    #expect(second.transactionRevision == DocumentTransactionRevision(1))
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Second")
    #expect(await controller.currentSource().name == "Second")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRoutesSaveAndLoadThroughCoherentPackageState() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("project.swcad")
        let controller = try makeController(document: .empty(named: "Saved"))
        let saved = try await controller.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        #expect(saved.document.source.name == "Saved")

        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.change",
                commands: [.renameDocument(name: "Changed")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
        let loaded = try await controller.load(
            from: url,
            expectedTransactionRevision: DocumentTransactionRevision(1)
        )

        #expect(loaded.document.cadDocument.metadata.name == "Saved")
        #expect(loaded.package.source.name == "Saved")
        #expect(loaded.transactionRevision == DocumentTransactionRevision(2))
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Saved")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(2))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerLoadInvalidatesPreLoadTransactionRevisions() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("project.swcad")
        let controller = try makeController(document: .empty(named: "Loaded"))
        _ = try await controller.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let loaded = try await controller.load(
            from: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )

        #expect(loaded.transactionRevision == DocumentTransactionRevision(1))
        var caught: ProjectControllerError?
        do {
            _ = try await controller.commit(
                ProjectSourceTransaction(
                    name: "fixture.stale-after-load",
                    commands: [.renameDocument(name: "Rejected")],
                    expectedTransactionRevision: DocumentTransactionRevision(0)
                )
            )
        } catch let error as ProjectControllerError {
            caught = error
        }
        #expect(caught?.code == .revisionConflict)
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Loaded")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsLateCommitAfterPackageLoadPublishes() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("project.swcad")
        let gate = BlockingEvaluationGate()
        defer { gate.releaseFirstEvaluation() }
        let controller = try makeController(
            document: .empty(named: "Loaded"),
            evaluator: BlockingProjectEvaluator(gate: gate)
        )
        _ = try await controller.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let commit = Task {
            try await controller.commit(
                ProjectSourceTransaction(
                    name: "fixture.late",
                    commands: [.renameDocument(name: "First")],
                    expectedTransactionRevision: DocumentTransactionRevision(0)
                )
            )
        }
        while !gate.didStartFirstEvaluation {
            try await Task.sleep(for: .milliseconds(1))
        }

        let loaded = try await controller.load(
            from: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        gate.releaseFirstEvaluation()

        var commitError: ProjectControllerError?
        do {
            _ = try await commit.value
        } catch let error as ProjectControllerError {
            commitError = error
        }
        #expect(commitError?.code == .revisionConflict)
        #expect(loaded.transactionRevision == DocumentTransactionRevision(1))
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Loaded")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerFailedSaveRetainsCurrentAggregate() async throws {
    try await withTemporaryDirectory { directory in
        let controller = try makeController(
            document: .empty(named: "Retained"),
            packageWriter: FailingPackageWriter()
        )
        let before = await controller.currentPackage()
        var caught: ProjectControllerError?

        do {
            _ = try await controller.save(
                to: directory.appendingPathComponent("failed.swcad"),
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        } catch let error as ProjectControllerError {
            caught = error
        }

        #expect(caught?.code == .packageFailed)
        #expect(await controller.currentPackage().source == before.source)
        #expect(await controller.currentPackage().cadSource == before.cadSource)
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    }
}

private func makeController(
    document: DesignDocument,
    evaluator: any ProjectEvaluating = ProjectEvaluationEngine(),
    packageWriter: any ProjectPackageWriting = ProjectPackageStore()
) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluator: evaluator,
        projector: FixtureProjector(),
        cadSourceCodec: FixtureCADSourceCodec(),
        packageWriter: packageWriter
    )
}

private struct FixtureProjector: ProjectSourceProjecting {
    func project(_ document: DesignDocument) throws -> ProjectSourceModel {
        try ProjectSourceModel(
            id: ProjectID(rawValue: "cad.\(document.id.description)"),
            name: document.cadDocument.metadata.name ?? "Untitled"
        )
    }
}

private struct FixtureCADSourceCodec: ProjectCADSourceCoding {
    func encode(_ document: DesignDocument) throws -> ProjectPackageCADSource {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try ProjectPackageCADSource(
            data: encoder.encode(document.cadDocument)
        )
    }

    func decode(_ source: ProjectPackageCADSource) throws -> DesignDocument {
        DesignDocument(cadDocument: try JSONDecoder().decode(CADDocument.self, from: source.data))
    }
}

private struct FailingProjectEvaluator: ProjectEvaluating {
    func evaluate(
        project _: ProjectSourceModel,
        purpose _: GeometryRepresentationPurpose,
        revision _: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        throw EvaluationError(
            code: .sourceUnavailable,
            message: "Fixture evaluation failed."
        )
    }
}

private final class BlockingEvaluationGate: Sendable {
    private struct State {
        var didStartFirstEvaluation = false
        var canFinishFirstEvaluation = false
    }

    private let state = Mutex(State())

    var didStartFirstEvaluation: Bool {
        state.withLock { $0.didStartFirstEvaluation }
    }

    func waitIfNeeded(for sourceName: String) {
        guard sourceName == "First" else {
            return
        }
        state.withLock { $0.didStartFirstEvaluation = true }
        while !state.withLock({ $0.canFinishFirstEvaluation }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func releaseFirstEvaluation() {
        state.withLock { $0.canFinishFirstEvaluation = true }
    }
}

private struct BlockingProjectEvaluator: ProjectEvaluating {
    let gate: BlockingEvaluationGate

    func evaluate(
        project source: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        gate.waitIfNeeded(for: source.name)
        return try ProjectEvaluationEngine().evaluate(
            project: source,
            purpose: purpose,
            revision: revision
        )
    }
}

private struct FailingPackageWriter: ProjectPackageWriting {
    func save(
        _: ProjectPackageDocument,
        to _: URL
    ) throws -> ProjectPackageSaveResult {
        throw ProjectPackageError(
            code: .atomicSaveFailure,
            message: "Fixture save failure."
        )
    }
}

private func withTemporaryDirectory<Result: Sendable>(
    _ body: (URL) async throws -> Result
) async throws -> Result {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "rupa-project-controller-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    do {
        let result = try await body(directory)
        try FileManager.default.removeItem(at: directory)
        return result
    } catch {
        let primaryError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let cleanupError {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Test failed and temporary cleanup also failed: "
                    + "\(primaryError); \(cleanupError)."
            )
        }
        throw primaryError
    }
}
