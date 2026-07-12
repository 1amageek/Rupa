import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel

public actor ProjectController {
    private var source: ProjectSourceModel
    private var sourceRevision: DocumentTransactionRevision
    private var evaluation: EvaluatedProjectSnapshot?
    private let evaluator: ProjectEvaluationEngine

    public init(
        source: ProjectSourceModel,
        evaluator: ProjectEvaluationEngine = ProjectEvaluationEngine()
    ) throws {
        do {
            try source.validate()
        } catch let error as ProjectModelError {
            throw ProjectControllerError(code: .sourceInvalid, message: error.message)
        }
        self.source = source
        self.sourceRevision = DocumentTransactionRevision()
        self.evaluation = nil
        self.evaluator = evaluator
    }

    public func currentSource() -> ProjectSourceModel {
        source
    }

    public func currentSourceRevision() -> DocumentTransactionRevision {
        sourceRevision
    }

    public func currentEvaluation() throws -> EvaluatedProjectSnapshot {
        guard let evaluation else {
            throw ProjectControllerError(
                code: .snapshotUnavailable,
                message: "The project has not been evaluated yet."
            )
        }
        return evaluation
    }

    public func evaluateCurrent() async throws -> EvaluatedProjectSnapshot {
        try await evaluate(source: source, revision: sourceRevision)
    }

    public func commit(
        _ mutation: @Sendable (ProjectSourceModel) throws -> ProjectSourceModel
    ) async throws -> ProjectCommitResult {
        let baseRevision = sourceRevision
        let stagedSource: ProjectSourceModel
        do {
            stagedSource = try mutation(source)
            try stagedSource.validate()
        } catch let error as ProjectControllerError {
            throw error
        } catch let error as ProjectModelError {
            throw ProjectControllerError(code: .sourceInvalid, message: error.message)
        } catch {
            throw ProjectControllerError(
                code: .mutationFailed,
                message: "Project source mutation failed: \(error)"
            )
        }

        let nextRevision: DocumentTransactionRevision
        do {
            nextRevision = try baseRevision.advanced()
        } catch {
            throw ProjectControllerError(
                code: .revisionOverflow,
                message: "Project source revision cannot be advanced."
            )
        }
        let stagedEvaluation = try await evaluate(
            source: stagedSource,
            revision: nextRevision
        )
        guard sourceRevision == baseRevision else {
            throw ProjectControllerError(
                code: .revisionConflict,
                message: "Project source changed while the staged evaluation was running."
            )
        }
        source = stagedSource
        sourceRevision = nextRevision
        evaluation = stagedEvaluation
        return ProjectCommitResult(
            sourceRevision: nextRevision,
            source: stagedSource,
            evaluation: stagedEvaluation
        )
    }

    private func evaluate(
        source: ProjectSourceModel,
        revision: DocumentTransactionRevision
    ) async throws -> EvaluatedProjectSnapshot {
        let evaluator = self.evaluator
        do {
            return try await Task.detached(priority: nil) {
                try Task.checkCancellation()
                let result = try evaluator.evaluate(source, sourceRevision: revision)
                try Task.checkCancellation()
                return result
            }.value
        } catch let error as EvaluationError {
            throw ProjectControllerError(
                code: .evaluationFailed,
                message: error.message
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .evaluationFailed,
                message: "Project evaluation failed: \(error)"
            )
        }
    }
}
