import Foundation
import RupaAgentCADBenchmark

@MainActor
public struct CADJSONAdapter: Sendable {
    private let executor: any CADActivatedCaseExecuting

    public init() {
        self.executor = DefaultCADActivatedCaseExecutor()
    }

    // Test-only injection keeps production construction sealed to the reviewed executor.
    init(executor: any CADActivatedCaseExecuting) {
        self.executor = executor
    }

    public var activatedCaseIDs: [CADBenchmarkCaseID] {
        executor.activatedCaseIDs
    }

    public func makeRequest(for caseID: CADBenchmarkCaseID) throws -> CADJSONRequestEnvelope {
        guard executor.activatedCaseIDs.contains(caseID) else {
            throw CADJSONAdapterError.inactiveCase
        }
        let context: CADCandidateContext
        do {
            context = try executor.context(for: caseID)
        } catch let error as CADActivatedCaseExecutorError {
            throw map(error)
        } catch {
            throw CADJSONAdapterError.infrastructureFailure
        }
        return try CADJSONRequestEnvelope(caseID: caseID, context: context)
    }

    public func encodeRequest(for caseID: CADBenchmarkCaseID) throws -> Data {
        try CADJSONBoundedCodec.encode(makeRequest(for: caseID))
    }

    public func decodeResponse(from data: Data) throws -> CADJSONCandidateResponseEnvelope {
        try CADJSONBoundedCodec.decode(CADJSONCandidateResponseEnvelope.self, from: data)
    }

    public func encodeEvaluation(_ envelope: CADJSONEvaluationEnvelope) throws -> Data {
        try CADJSONBoundedCodec.encode(envelope)
    }

    func makeCandidate(
        from response: CADJSONCandidateResponseEnvelope,
        for caseID: CADBenchmarkCaseID
    ) throws -> CADJSONCandidate {
        let context = try liveContext(for: caseID)
        let fingerprint = try CADJSONContextFingerprint.value(for: context)
        try response.validate(
            expectedCaseID: caseID,
            expectedContextFingerprint: fingerprint
        )
        return try CADJSONCandidate(response: response)
    }

    func makeCandidate(
        from response: CADJSONCandidateResponseEnvelope
    ) throws -> CADJSONCandidate {
        try makeCandidate(from: response, for: response.caseID)
    }

    public func evaluate(
        responseData: Data
    ) async throws -> CADJSONEvaluationEnvelope {
        let response = try decodeResponse(from: responseData)
        return try await evaluate(response: response, for: response.caseID)
    }

    func evaluate(
        response: CADJSONCandidateResponseEnvelope
    ) async throws -> CADJSONEvaluationEnvelope {
        try await evaluate(response: response, for: response.caseID)
    }

    func evaluate(
        response: CADJSONCandidateResponseEnvelope,
        for caseID: CADBenchmarkCaseID
    ) async throws -> CADJSONEvaluationEnvelope {
        let context = try liveContext(for: caseID)
        let contextFingerprint = try CADJSONContextFingerprint.value(for: context)
        try response.validate(
            expectedCaseID: caseID,
            expectedContextFingerprint: contextFingerprint
        )
        let candidate = try CADJSONCandidate(response: response)

        do {
            let result = try await executor.evaluate(caseID: caseID, candidate: candidate)
            do {
                try result.validate()
            } catch {
                return try failure(
                    caseID: caseID,
                    contextFingerprint: contextFingerprint,
                    error: .infrastructureFailure
                )
            }
            return try CADJSONEvaluationEnvelope(
                caseID: caseID,
                contextFingerprint: contextFingerprint,
                result: result
            )
        } catch let error as CADJSONAdapterError {
            return try failure(
                caseID: caseID,
                contextFingerprint: contextFingerprint,
                error: error
            )
        } catch let error as CADActivatedCaseExecutorError {
            return try failure(
                caseID: caseID,
                contextFingerprint: contextFingerprint,
                error: map(error)
            )
        } catch is CancellationError {
            return try failure(
                caseID: caseID,
                contextFingerprint: contextFingerprint,
                error: .cancellation
            )
        } catch {
            return try failure(
                caseID: caseID,
                contextFingerprint: contextFingerprint,
                error: .infrastructureFailure
            )
        }
    }

    private func liveContext(for caseID: CADBenchmarkCaseID) throws -> CADCandidateContext {
        guard executor.activatedCaseIDs.contains(caseID) else {
            throw CADJSONAdapterError.inactiveCase
        }
        do {
            return try executor.context(for: caseID)
        } catch let error as CADActivatedCaseExecutorError {
            throw map(error)
        } catch {
            throw CADJSONAdapterError.infrastructureFailure
        }
    }

    private func map(_ error: CADActivatedCaseExecutorError) -> CADJSONAdapterError {
        switch error {
        case .inactiveCase:
            .inactiveCase
        case .candidateFailure:
            .candidateFailure
        case .catalogFailure, .invalidResult:
            .infrastructureFailure
        }
    }

    private func failure(
        caseID: CADBenchmarkCaseID,
        contextFingerprint: String,
        error: CADJSONAdapterError
    ) throws -> CADJSONEvaluationEnvelope {
        let envelopeError = try CADJSONErrorEnvelope(code: error.code, caseID: caseID)
        return try CADJSONEvaluationEnvelope(
            caseID: caseID,
            contextFingerprint: contextFingerprint,
            error: envelopeError
        )
    }
}
