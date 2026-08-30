struct CADActivatedCaseExecution: Equatable, Sendable {
    let context: CADCandidateContext
    let publicResult: CADCaseResult
    let evidence: CADActivatedCaseEvidence
    let regressionRecord: CADCaseRegressionRecord
    let measurement: CADCaseMeasurement

    init(context: CADCandidateContext, evidence: CADActivatedCaseEvidence) throws {
        try context.validate()
        try evidence.validate()
        guard context.challenge.id == evidence.caseID,
              context.challenge.category == evidence.caseID.category else {
            throw CADBenchmarkReferenceRunError.contextMismatch(evidence.caseID)
        }

        let measurement = try CADCaseMeasurement(
            caseID: evidence.caseID,
            totalWallNanoseconds: evidence.totalWallNanoseconds
        )
        let record = try Self.makeRecord(context: context, evidence: evidence)
        let publicResult = CADCaseResult(
            id: evidence.caseID,
            category: context.challenge.category,
            outcome: evidence.outcome,
            capabilityDecisionCorrect: nil,
            durationMilliseconds: Double(evidence.totalWallNanoseconds) / 1_000_000.0
        )
        try publicResult.validate()

        self.context = context
        self.publicResult = publicResult
        self.evidence = evidence
        self.regressionRecord = record
        self.measurement = measurement
    }

    func validate() throws {
        try context.validate()
        try publicResult.validate()
        try evidence.validate()
        try regressionRecord.validate()
        guard context.challenge.id == evidence.caseID,
              publicResult.id == evidence.caseID,
              publicResult.outcome == evidence.outcome,
              regressionRecord.caseID == evidence.caseID,
              regressionRecord.outcome == evidence.outcome,
              measurement.caseID == evidence.caseID,
              measurement.totalWallNanoseconds == evidence.totalWallNanoseconds else {
            throw CADBenchmarkReferenceRunError.invalidEvidence(evidence.caseID)
        }
    }

    private static func makeRecord(
        context: CADCandidateContext,
        evidence: CADActivatedCaseEvidence
    ) throws -> CADCaseRegressionRecord {
        guard let status = context.capabilities.status(
            for: context.challenge.requiredCapability
        ) else {
            throw CADBenchmarkReferenceRunError.invalidEvidence(evidence.caseID)
        }
        let capabilityDecisionCorrect = switch evidence.outcome {
        case .realized:
            status.available
        case .expectedUnsupported:
            status.available == false && evidence.caseID.category == .sphere
        case .unexpectedUnsupported, .invalidSubmission, .executionFailure, .oracleFailure,
             .timeout, .cancellation, .infrastructureFailure:
            false
        }
        let oracleDisposition: CADCaseRegressionRecord.OracleDisposition
        switch evidence.outcome {
        case .realized:
            oracleDisposition = .accepted
        case .expectedUnsupported:
            oracleDisposition = .expectedUnsupported
        case .unexpectedUnsupported, .invalidSubmission, .executionFailure, .oracleFailure,
             .timeout, .cancellation, .infrastructureFailure:
            oracleDisposition = .rejected
        }
        let entries = try CADInternalCatalogStore.entries()
        guard let entry = entries.first(where: { $0.challenge.id == evidence.caseID }) else {
            throw CADBenchmarkReferenceRunError.missingCase(evidence.caseID)
        }

        return try CADCaseRegressionRecord(
            caseID: evidence.caseID,
            outcome: evidence.outcome,
            capabilityDecisionCorrect: capabilityDecisionCorrect,
            route: try route(for: evidence),
            counts: counts(for: evidence),
            caseContractDigest: entry.expectationDigest,
            oracleDisposition: oracleDisposition
        )
    }

    private static func route(
        for evidence: CADActivatedCaseEvidence
    ) throws -> CADCaseRegressionRecord.Route {
        switch evidence {
        case .line(let result):
            let route = result.routeEvidence
            return try makeRoute(
                caseID: result.caseID,
                didPublish: route.didPublish,
                initialDocumentGeneration: route.initialDocumentGeneration.value,
                finalDocumentGeneration: route.finalDocumentGeneration.value,
                initialTransactionRevision: route.initialTransactionRevision.value,
                finalTransactionRevision: route.finalTransactionRevision.value,
                initialPublicationSequence: route.initialPublicationSequence,
                finalPublicationSequence: route.finalPublicationSequence,
                initialWorkspaceRevision: route.initialWorkspaceRevision.value,
                finalWorkspaceRevision: route.finalWorkspaceRevision.value,
                cleanupCompleted: route.cleanupCompleted,
                remainingRegistrationCount: route.remainingRegistrationCount
            )
        case .rectangle(let result):
            let route = result.routeEvidence
            return try makeRoute(
                caseID: result.caseID,
                didPublish: route.didPublish,
                initialDocumentGeneration: route.initialDocumentGeneration.value,
                finalDocumentGeneration: route.finalDocumentGeneration.value,
                initialTransactionRevision: route.initialTransactionRevision.value,
                finalTransactionRevision: route.finalTransactionRevision.value,
                initialPublicationSequence: route.initialPublicationSequence,
                finalPublicationSequence: route.finalPublicationSequence,
                initialWorkspaceRevision: route.initialWorkspaceRevision.value,
                finalWorkspaceRevision: route.finalWorkspaceRevision.value,
                cleanupCompleted: route.cleanupCompleted,
                remainingRegistrationCount: route.remainingRegistrationCount
            )
        case .circle(let result):
            let route = result.routeEvidence
            return try makeRoute(
                caseID: result.caseID,
                didPublish: route.didPublish,
                initialDocumentGeneration: route.initialDocumentGeneration.value,
                finalDocumentGeneration: route.finalDocumentGeneration.value,
                initialTransactionRevision: route.initialTransactionRevision.value,
                finalTransactionRevision: route.finalTransactionRevision.value,
                initialPublicationSequence: route.initialPublicationSequence,
                finalPublicationSequence: route.finalPublicationSequence,
                initialWorkspaceRevision: route.initialWorkspaceRevision.value,
                finalWorkspaceRevision: route.finalWorkspaceRevision.value,
                cleanupCompleted: route.cleanupCompleted,
                remainingRegistrationCount: route.remainingRegistrationCount
            )
        case .angle(let result):
            let route = result.routeEvidence
            return try makeRoute(
                caseID: result.caseID,
                didPublish: route.didPublish,
                initialDocumentGeneration: route.initialDocumentGeneration.value,
                finalDocumentGeneration: route.finalDocumentGeneration.value,
                initialTransactionRevision: route.initialTransactionRevision.value,
                finalTransactionRevision: route.finalTransactionRevision.value,
                initialPublicationSequence: route.initialPublicationSequence,
                finalPublicationSequence: route.finalPublicationSequence,
                initialWorkspaceRevision: route.initialWorkspaceRevision.value,
                finalWorkspaceRevision: route.finalWorkspaceRevision.value,
                cleanupCompleted: route.cleanupCompleted,
                remainingRegistrationCount: route.remainingRegistrationCount
            )
        case .box(let result):
            let route = result.routeEvidence
            return try makeRoute(
                caseID: result.caseID,
                didPublish: route.didPublish,
                initialDocumentGeneration: route.initialDocumentGeneration.value,
                finalDocumentGeneration: route.finalDocumentGeneration.value,
                initialTransactionRevision: route.initialTransactionRevision.value,
                finalTransactionRevision: route.finalTransactionRevision.value,
                initialPublicationSequence: route.initialPublicationSequence,
                finalPublicationSequence: route.finalPublicationSequence,
                initialWorkspaceRevision: route.initialWorkspaceRevision.value,
                finalWorkspaceRevision: route.finalWorkspaceRevision.value,
                cleanupCompleted: route.cleanupCompleted,
                remainingRegistrationCount: route.remainingRegistrationCount
            )
        case .cylinder(let result):
            let route = result.routeEvidence
            return try makeRoute(
                caseID: result.caseID,
                didPublish: route.didPublish,
                initialDocumentGeneration: route.initialDocumentGeneration.value,
                finalDocumentGeneration: route.finalDocumentGeneration.value,
                initialTransactionRevision: route.initialTransactionRevision.value,
                finalTransactionRevision: route.finalTransactionRevision.value,
                initialPublicationSequence: route.initialPublicationSequence,
                finalPublicationSequence: route.finalPublicationSequence,
                initialWorkspaceRevision: route.initialWorkspaceRevision.value,
                finalWorkspaceRevision: route.finalWorkspaceRevision.value,
                cleanupCompleted: route.cleanupCompleted,
                remainingRegistrationCount: route.remainingRegistrationCount
            )
        case .constraint(let result):
            let route = result.routeEvidence
            return try makeRoute(
                caseID: result.caseID,
                didPublish: route.didPublish,
                initialDocumentGeneration: route.initialDocumentGeneration.value,
                finalDocumentGeneration: route.finalDocumentGeneration.value,
                initialTransactionRevision: route.initialTransactionRevision.value,
                finalTransactionRevision: route.finalTransactionRevision.value,
                initialPublicationSequence: route.initialPublicationSequence,
                finalPublicationSequence: route.finalPublicationSequence,
                initialWorkspaceRevision: route.initialWorkspaceRevision.value,
                finalWorkspaceRevision: route.finalWorkspaceRevision.value,
                cleanupCompleted: route.cleanupCompleted,
                remainingRegistrationCount: route.remainingRegistrationCount
            )
        case .transform(let result):
            let route = result.routeEvidence
            return try makeRoute(
                caseID: result.caseID,
                didPublish: route.didPublish,
                initialDocumentGeneration: route.initialDocumentGeneration.value,
                finalDocumentGeneration: route.finalDocumentGeneration.value,
                initialTransactionRevision: route.initialTransactionRevision.value,
                finalTransactionRevision: route.finalTransactionRevision.value,
                initialPublicationSequence: route.initialPublicationSequence,
                finalPublicationSequence: route.finalPublicationSequence,
                initialWorkspaceRevision: route.initialWorkspaceRevision.value,
                finalWorkspaceRevision: route.finalWorkspaceRevision.value,
                cleanupCompleted: route.cleanupCompleted,
                remainingRegistrationCount: route.remainingRegistrationCount
            )
        case .compound(let result):
            let route = result.routeEvidence
            return try makeRoute(
                caseID: result.caseID,
                didPublish: route.didPublish,
                initialDocumentGeneration: route.initialDocumentGeneration.value,
                finalDocumentGeneration: route.finalDocumentGeneration.value,
                initialTransactionRevision: route.initialTransactionRevision.value,
                finalTransactionRevision: route.finalTransactionRevision.value,
                initialPublicationSequence: route.initialPublicationSequence,
                finalPublicationSequence: route.finalPublicationSequence,
                initialWorkspaceRevision: route.initialWorkspaceRevision.value,
                finalWorkspaceRevision: route.finalWorkspaceRevision.value,
                cleanupCompleted: route.cleanupCompleted,
                remainingRegistrationCount: route.remainingRegistrationCount
            )
        case .sphere(let result):
            let route = result.routeEvidence
            return try makeRoute(
                caseID: result.caseID,
                didPublish: route.didPublish,
                initialDocumentGeneration: route.initialDocumentGeneration.value,
                finalDocumentGeneration: route.finalDocumentGeneration.value,
                initialTransactionRevision: route.initialTransactionRevision.value,
                finalTransactionRevision: route.finalTransactionRevision.value,
                initialPublicationSequence: route.initialPublicationSequence,
                finalPublicationSequence: route.finalPublicationSequence,
                initialWorkspaceRevision: route.initialWorkspaceRevision.value,
                finalWorkspaceRevision: route.finalWorkspaceRevision.value,
                cleanupCompleted: route.cleanupCompleted,
                remainingRegistrationCount: route.remainingRegistrationCount
            )
        }
    }

    private static func counts(
        for evidence: CADActivatedCaseEvidence
    ) -> CADCaseRegressionRecord.Counts {
        switch evidence {
        case .line(let result):
            let telemetry = result.telemetry
            return commonCounts(
                action: telemetry.actionCount, command: telemetry.commandCount,
                read: telemetry.readCount, entity: telemetry.entityCount,
                feature: telemetry.featureCount, body: telemetry.bodyCount
            )
        case .rectangle(let result):
            let telemetry = result.telemetry
            return commonCounts(
                action: telemetry.actionCount, command: telemetry.commandCount,
                read: telemetry.readCount, entity: telemetry.entityCount,
                feature: telemetry.featureCount, body: telemetry.bodyCount
            )
        case .circle(let result):
            let telemetry = result.telemetry
            return commonCounts(
                action: telemetry.actionCount, command: telemetry.commandCount,
                read: telemetry.readCount, entity: telemetry.entityCount,
                feature: telemetry.featureCount, body: telemetry.bodyCount
            )
        case .angle(let result):
            let telemetry = result.telemetry
            return commonCounts(
                action: telemetry.actionCount, command: telemetry.commandCount,
                read: telemetry.readCount, entity: telemetry.entityCount,
                feature: telemetry.featureCount, body: telemetry.bodyCount
            )
        case .box(let result):
            let telemetry = result.telemetry
            return solidCounts(
                action: telemetry.actionCount,
                command: telemetry.commandCount,
                read: telemetry.readCount,
                entity: telemetry.entityCount,
                feature: telemetry.featureCount,
                body: telemetry.bodyCount,
                face: telemetry.faceCount,
                edge: telemetry.edgeCount,
                vertex: telemetry.vertexCount
            )
        case .cylinder(let result):
            let telemetry = result.telemetry
            return solidCounts(
                action: telemetry.actionCount,
                command: telemetry.commandCount,
                read: telemetry.readCount,
                entity: telemetry.entityCount,
                feature: telemetry.featureCount,
                body: telemetry.bodyCount,
                face: telemetry.faceCount,
                edge: telemetry.edgeCount,
                vertex: telemetry.vertexCount
            )
        case .constraint(let result):
            let telemetry = result.telemetry
            return commonCounts(
                action: telemetry.actionCount, command: telemetry.commandCount,
                read: telemetry.readCount, entity: telemetry.entityCount,
                feature: telemetry.featureCount, body: telemetry.bodyCount
            )
        case .transform(let result):
            let telemetry = result.telemetry
            return CADCaseRegressionRecord.Counts(
                action: telemetry.actionCount,
                command: telemetry.commandCount,
                read: telemetry.readCount,
                entity: nil,
                feature: telemetry.featureCount,
                sceneNode: telemetry.sceneNodeCount,
                body: telemetry.bodyCount,
                face: nil,
                edge: nil,
                vertex: nil,
                evaluationPass: nil,
                historyEntry: nil,
                capabilityRequest: nil,
                sourceMutation: nil
            )
        case .compound(let result):
            let telemetry = result.telemetry
            return CADCaseRegressionRecord.Counts(
                action: telemetry.actionCount,
                command: telemetry.commandCount,
                read: telemetry.readCount,
                entity: telemetry.entityCount,
                feature: telemetry.featureCount,
                sceneNode: nil,
                body: telemetry.bodyCount,
                face: telemetry.faceCount,
                edge: telemetry.edgeCount,
                vertex: telemetry.vertexCount,
                evaluationPass: result.routeEvidence.evaluationPassCount,
                historyEntry: result.routeEvidence.historyEntryCount,
                capabilityRequest: nil,
                sourceMutation: nil
            )
        case .sphere(let result):
            let telemetry = result.telemetry
            return CADCaseRegressionRecord.Counts(
                action: telemetry.actionCount,
                command: telemetry.commandCount,
                read: telemetry.readCount,
                entity: telemetry.entityCount,
                feature: telemetry.featureCount,
                sceneNode: nil,
                body: telemetry.bodyCount,
                face: nil,
                edge: nil,
                vertex: nil,
                evaluationPass: nil,
                historyEntry: nil,
                capabilityRequest: telemetry.capabilityRequestCount,
                sourceMutation: telemetry.sourceMutationCount
            )
        }
    }

    private static func commonCounts(
        action: Int,
        command: Int,
        read: Int,
        entity: Int,
        feature: Int,
        body: Int
    ) -> CADCaseRegressionRecord.Counts {
        CADCaseRegressionRecord.Counts(
            action: action,
            command: command,
            read: read,
            entity: entity,
            feature: feature,
            sceneNode: nil,
            body: body,
            face: nil,
            edge: nil,
            vertex: nil,
            evaluationPass: nil,
            historyEntry: nil,
            capabilityRequest: nil,
            sourceMutation: nil
        )
    }

    private static func solidCounts(
        action: Int,
        command: Int,
        read: Int,
        entity: Int,
        feature: Int,
        body: Int,
        face: Int,
        edge: Int,
        vertex: Int
    ) -> CADCaseRegressionRecord.Counts {
        CADCaseRegressionRecord.Counts(
            action: action,
            command: command,
            read: read,
            entity: entity,
            feature: feature,
            sceneNode: nil,
            body: body,
            face: face,
            edge: edge,
            vertex: vertex,
            evaluationPass: nil,
            historyEntry: nil,
            capabilityRequest: nil,
            sourceMutation: nil
        )
    }

    private static func makeRoute(
        caseID: CADBenchmarkCaseID,
        didPublish: Bool,
        initialDocumentGeneration: UInt64,
        finalDocumentGeneration: UInt64,
        initialTransactionRevision: UInt64,
        finalTransactionRevision: UInt64,
        initialPublicationSequence: UInt64,
        finalPublicationSequence: UInt64,
        initialWorkspaceRevision: UInt64,
        finalWorkspaceRevision: UInt64,
        cleanupCompleted: Bool,
        remainingRegistrationCount: Int
    ) throws -> CADCaseRegressionRecord.Route {
        CADCaseRegressionRecord.Route(
            didPublish: didPublish,
            documentGenerationDelta: try delta(
                final: finalDocumentGeneration,
                initial: initialDocumentGeneration,
                caseID: caseID
            ),
            transactionRevisionDelta: try delta(
                final: finalTransactionRevision,
                initial: initialTransactionRevision,
                caseID: caseID
            ),
            publicationSequenceDelta: try delta(
                final: finalPublicationSequence,
                initial: initialPublicationSequence,
                caseID: caseID
            ),
            workspaceRevisionChanged: finalWorkspaceRevision != initialWorkspaceRevision,
            cleanupCompleted: cleanupCompleted,
            remainingRegistrationCount: remainingRegistrationCount
        )
    }

    private static func delta(
        final: UInt64,
        initial: UInt64,
        caseID: CADBenchmarkCaseID
    ) throws -> Int64 {
        guard final >= initial,
              let value = Int64(exactly: final - initial) else {
            throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
        }
        return value
    }
}
