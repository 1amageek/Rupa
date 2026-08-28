import Foundation
import RupaAgentCADBenchmark
import RupaAgentCADBenchmarkJSONAdapter

struct CADBenchmarkCLIService: Sendable {
    func request(rawCaseID: String) async -> CADBenchmarkCLIExecution {
        let caseID: CADBenchmarkCaseID
        do {
            caseID = try CADBenchmarkCaseID(validating: rawCaseID)
        } catch {
            return failure(
                error: CADJSONAdapterError.inactiveCase,
                caseID: nil
            )
        }

        let adapter = await CADJSONAdapter()
        do {
            let data = try await adapter.encodeRequest(for: caseID)
            return CADBenchmarkCLIExecution(
                output: data,
                exitCode: .success
            )
        } catch {
            return failure(error: error, caseID: caseID)
        }
    }

    func evaluate(responsePath: String) async -> CADBenchmarkCLIExecution {
        do {
            let input = try readInput(at: responsePath)
            let adapter = await CADJSONAdapter()
            var caseID: CADBenchmarkCaseID?
            do {
                let response = try await adapter.decodeResponse(from: input)
                caseID = response.caseID
                let evaluation = try await adapter.evaluate(responseData: input)
                let output = try await adapter.encodeEvaluation(evaluation)
                let exitCode: CADBenchmarkCLIExitCode
                if let result = evaluation.result {
                    exitCode = CADBenchmarkCLIExitCode.value(for: result)
                } else if let error = evaluation.error {
                    exitCode = CADBenchmarkCLIExitCode.value(for: error.code)
                } else {
                    return failure(
                        error: CADJSONAdapterError.infrastructureFailure,
                        caseID: caseID
                    )
                }
                return CADBenchmarkCLIExecution(output: output, exitCode: exitCode)
            } catch {
                return failure(error: error, caseID: caseID)
            }
        } catch {
            return failure(error: error, caseID: nil)
        }
    }

    private func readInput(at path: String) throws -> Data {
        if path == "-" {
            return try CADJSONBoundedCodec.readStandardInput()
        }
        return try CADJSONBoundedCodec.readRegularFile(at: path)
    }

    private func failure(
        error: Error,
        caseID: CADBenchmarkCaseID?
    ) -> CADBenchmarkCLIExecution {
        let adapterError = error as? CADJSONAdapterError
        let code = adapterError?.code ?? .infrastructureFailure
        do {
            let envelope = try CADJSONErrorEnvelope(code: code, caseID: caseID)
            let data = try CADJSONBoundedCodec.encode(envelope)
            return CADBenchmarkCLIExecution(
                output: data,
                exitCode: CADBenchmarkCLIExitCode.value(for: code)
            )
        } catch {
            do {
                let envelope = try CADJSONErrorEnvelope(code: .infrastructureFailure)
                let data = try CADJSONBoundedCodec.encode(envelope)
                return CADBenchmarkCLIExecution(
                    output: data,
                    exitCode: .software
                )
            } catch {
                return CADBenchmarkCLIExecution(
                    output: CADJSONBoundedCodec.guaranteedInfrastructureFailureDocument,
                    exitCode: .software
                )
            }
        }
    }
}
