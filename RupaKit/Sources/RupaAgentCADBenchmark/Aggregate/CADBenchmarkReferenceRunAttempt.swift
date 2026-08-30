struct CADBenchmarkReferenceRunAttempt: Equatable, Sendable {
    let manifest: CADBenchmarkManifest
    let executions: [CADActivatedCaseExecution]

    init(
        manifest: CADBenchmarkManifest,
        executions: [CADActivatedCaseExecution]
    ) throws {
        try manifest.validate()
        guard executions.count == manifest.orderedCaseIDs.count else {
            throw CADBenchmarkReferenceRunError.incompleteRun(
                expected: manifest.orderedCaseIDs.count,
                actual: executions.count
            )
        }
        var identities = Set<CADBenchmarkCaseID>()
        for execution in executions {
            try execution.validate()
            guard identities.insert(execution.publicResult.id).inserted else {
                throw CADBenchmarkReferenceRunError.duplicateCase(execution.publicResult.id)
            }
        }
        guard executions.map(\.publicResult.id) == manifest.orderedCaseIDs else {
            throw CADBenchmarkReferenceRunError.activationMismatch
        }
        self.manifest = manifest
        self.executions = executions
        try validate()
    }

    var publicResults: [CADCaseResult] {
        executions.map(\.publicResult)
    }

    var regressionRecords: [CADCaseRegressionRecord] {
        executions.map(\.regressionRecord)
    }

    var measurements: [CADCaseMeasurement] {
        executions.map(\.measurement)
    }

    func validate() throws {
        try manifest.validate()
        guard executions.count == 100,
              executions.map(\.publicResult.id) == manifest.orderedCaseIDs else {
            throw CADBenchmarkReferenceRunError.incompleteRun(
                expected: 100,
                actual: executions.count
            )
        }
        for execution in executions {
            try execution.validate()
            let expectedOutcome: CADCaseOutcome = execution.publicResult.category == .sphere
                ? .expectedUnsupported
                : .realized
            guard execution.publicResult.outcome == expectedOutcome,
                  execution.regressionRecord.capabilityDecisionCorrect else {
                throw CADBenchmarkReferenceRunError.invalidOutcome(execution.publicResult.id)
            }
        }
    }
}
