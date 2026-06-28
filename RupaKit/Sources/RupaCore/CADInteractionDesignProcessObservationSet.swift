struct CADInteractionDesignProcessObservationSet: Sendable {
    var observations: [DesignProcessObservation]

    init(observations: [DesignProcessObservation]) {
        self.observations = observations
    }

    static func make(
        area: CADInteractionQualityArea,
        gateAssessments: [CADInteractionQualityGateAssessment],
        evidence: [CADInteractionQualityEvidence],
        openWork: [String],
        routeMatrix: DesignProcessRouteMatrix,
        flowGraphValidation: DesignProcessFlowGraphValidationResult
    ) -> CADInteractionDesignProcessObservationSet {
        var builder = ObservationBuilder(area: area)
        builder.addOpenWork(openWork)
        builder.addEvidence(evidence)
        builder.addGateAssessments(gateAssessments)
        builder.addRouteMatrix(routeMatrix)
        builder.addFlowGraphValidation(flowGraphValidation)
        return CADInteractionDesignProcessObservationSet(observations: builder.observations)
    }

    func confidence(
        rating: CADInteractionQualityRating,
        gates: [CADInteractionQualityGate: CADInteractionQualityRating],
        evidence: [CADInteractionQualityEvidence]
    ) -> DesignProcessConfidence {
        let performanceRating = gates[.performanceBudget] ?? .missing
        let verificationRating = gates[.verification] ?? .missing
        let agentRating = gates[.agentParity] ?? .missing
        let state = calibrationState(
            verification: verificationRating,
            performance: performanceRating,
            agent: agentRating,
            evidence: evidence
        )
        let anchors = calibrationAnchors(
            state: state,
            gates: gates,
            evidence: evidence
        )
        let measurements = performanceMeasurements(
            performanceRating: performanceRating,
            evidence: evidence
        )

        return DesignProcessConfidence(
            evidenceFreshness: evidenceFreshness(from: evidence),
            testCoverage: testCoverage(from: evidence),
            performanceCoverage: performanceCoverage(from: performanceRating),
            missingChannelPenalty: missingChannelPenalty,
            calibrationState: state,
            calibrationAnchors: anchors,
            performanceMeasurements: measurements,
            notes: confidenceNotes(
                rating: rating,
                calibrationAnchors: anchors,
                performanceMeasurements: measurements
            )
        )
    }

    private var missingChannelPenalty: Double {
        let penalty = observations.reduce(0.0) { result, observation in
            switch observation.severity {
            case .info:
                result
            case .warning:
                result + 0.04
            case .error:
                result + 0.1
            case .blocking:
                result + 0.16
            }
        }
        return min(0.8, penalty)
    }

    private func evidenceFreshness(
        from evidence: [CADInteractionQualityEvidence]
    ) -> Double {
        guard !evidence.isEmpty else {
            return 0.0
        }
        let completeEvidenceCount = evidence.filter { item in
            !item.sourceFiles.isEmpty || !item.tests.isEmpty || !item.notes.isEmpty
        }.count
        return Double(completeEvidenceCount) / Double(evidence.count)
    }

    private func testCoverage(
        from evidence: [CADInteractionQualityEvidence]
    ) -> Double {
        let testCount = Self.unique(evidence.flatMap(\.tests)).count
        return min(1.0, Double(testCount) / 3.0)
    }

    private func performanceCoverage(
        from performanceRating: CADInteractionQualityRating
    ) -> Double {
        Double(performanceRating.score) / Double(CADInteractionQualityRating.verified.score)
    }

    private func calibrationState(
        verification: CADInteractionQualityRating,
        performance: CADInteractionQualityRating,
        agent: CADInteractionQualityRating,
        evidence: [CADInteractionQualityEvidence]
    ) -> DesignProcessCalibrationState {
        if observations.contains(where: { $0.severity == .blocking || $0.severity == .error }) {
            return evidence.isEmpty ? .uncalibrated : .humanAnchored
        }
        if verification == .verified, performance == .verified {
            return .measurementCalibrated
        }
        if verification.score >= CADInteractionQualityRating.implemented.score,
           agent.score >= CADInteractionQualityRating.implemented.score {
            return .agentReadable
        }
        if !evidence.isEmpty {
            return .humanAnchored
        }
        return .uncalibrated
    }

    private func confidenceNotes(
        rating: CADInteractionQualityRating,
        calibrationAnchors: [DesignProcessCalibrationAnchor],
        performanceMeasurements: [DesignProcessPerformanceMeasurement]
    ) -> [String] {
        let warningCount = observations.filter { $0.severity == .warning }.count
        let errorCount = observations.filter { $0.severity == .error }.count
        let blockingCount = observations.filter { $0.severity == .blocking }.count
        let channels = Self.unique(observations.map { $0.channel.rawValue })
        let measuredPerformanceCount = performanceMeasurements.filter { measurement in
            measurement.status == .withinBudget || measurement.status == .exceedsBudget
        }.count

        return [
            "Confidence is derived from the ObservationSet, calibration anchors, test evidence, performance measurements, and calibration state.",
            "ObservationSet contains \(observations.count) observations across \(channels.count) channels.",
            "Calibration uses \(calibrationAnchors.count) anchors and \(measuredPerformanceCount)/\(performanceMeasurements.count) measured performance records.",
            "Current CAD quality rating is \(rating.rawValue); warning/error/blocking observations are \(warningCount)/\(errorCount)/\(blockingCount).",
        ]
    }

    private func calibrationAnchors(
        state: DesignProcessCalibrationState,
        gates: [CADInteractionQualityGate: CADInteractionQualityRating],
        evidence: [CADInteractionQualityEvidence]
    ) -> [DesignProcessCalibrationAnchor] {
        var anchors: [DesignProcessCalibrationAnchor] = []
        let tests = Self.unique(evidence.flatMap(\.tests))
        if !tests.isEmpty {
            anchors.append(
                DesignProcessCalibrationAnchor(
                    id: "automated-test-evidence",
                    title: "Automated test evidence",
                    channel: .automatedTest,
                    affectedLayer: .evaluation,
                    state: (gates[.verification] ?? .missing).score >= CADInteractionQualityRating.implemented.score
                        ? .agentReadable
                        : .humanAnchored,
                    summary: "\(tests.count) focused test references are attached to this packet.",
                    evidence: tests
                )
            )
        }

        let humanReviewObservations = observations.filter { $0.channel == .humanReview }
        if !humanReviewObservations.isEmpty {
            anchors.append(
                DesignProcessCalibrationAnchor(
                    id: "human-review-observations",
                    title: "Human review observations",
                    channel: .humanReview,
                    affectedLayer: .evaluation,
                    state: .humanAnchored,
                    summary: "\(humanReviewObservations.count) open review observations constrain the confidence score.",
                    evidence: humanReviewObservations.map(\.summary)
                )
            )
        }

        let agentRating = gates[.agentParity] ?? .missing
        if agentRating.score >= CADInteractionQualityRating.implemented.score {
            anchors.append(
                DesignProcessCalibrationAnchor(
                    id: "agent-readback-route",
                    title: "Agent readback route",
                    channel: .agentReadback,
                    affectedLayer: .agent,
                    state: .agentReadable,
                    summary: "Agent parity is \(agentRating.rawValue), so Agent-readable confidence can cite this route.",
                    evidence: observations
                        .filter { $0.channel == .agentReadback }
                        .map(\.summary)
                )
            )
        }

        let performanceRating = gates[.performanceBudget] ?? .missing
        if performanceRating.score > CADInteractionQualityRating.missing.score {
            anchors.append(
                DesignProcessCalibrationAnchor(
                    id: "performance-budget-gate",
                    title: "Performance budget gate",
                    channel: .performanceMeasurement,
                    affectedLayer: .measurement,
                    state: state == .measurementCalibrated ? .measurementCalibrated : .humanAnchored,
                    summary: "Performance budget gate is \(performanceRating.rawValue).",
                    evidence: observations
                        .filter { $0.channel == .performanceMeasurement }
                        .map(\.summary)
                )
            )
        }

        return anchors
    }

    private func performanceMeasurements(
        performanceRating: CADInteractionQualityRating,
        evidence: [CADInteractionQualityEvidence]
    ) -> [DesignProcessPerformanceMeasurement] {
        [
            DesignProcessPerformanceMeasurement(
                id: "performance-budget-gate",
                title: "Performance budget gate",
                metric: "performanceBudgetGate",
                unit: "ratingScore",
                measuredValue: Double(performanceRating.score),
                budgetValue: Double(CADInteractionQualityRating.verified.score),
                status: performanceMeasurementStatus(for: performanceRating),
                source: "CADInteractionQualityGate.performanceBudget",
                notes: [
                    "This record is a gate-derived calibration fixture, not an elapsed-time benchmark.",
                    "Attach measured dense-scene timings before treating the performance budget as fully calibrated.",
                ] + Self.unique(evidence.flatMap(\.notes)).filter { note in
                    let lowered = note.lowercased()
                    return lowered.contains("performance")
                        || lowered.contains("budget")
                        || lowered.contains("metric")
                        || lowered.contains("timing")
                        || lowered.contains("readback")
                }
            ),
        ]
    }

    private struct ObservationBuilder {
        var observations: [DesignProcessObservation] = []
        private let area: CADInteractionQualityArea

        init(area: CADInteractionQualityArea) {
            self.area = area
        }

        mutating func addOpenWork(_ openWork: [String]) {
            for (index, item) in openWork.enumerated() {
                append(
                    id: "open-work-\(index + 1)",
                    channel: .humanReview,
                    severity: index == 0 ? .blocking : .warning,
                    affectedLayer: affectedLayer(for: item),
                    summary: item,
                    requiredNextAction: "Update the design packet and implementation route before claiming verified support."
                )
            }
        }

        mutating func addEvidence(_ evidence: [CADInteractionQualityEvidence]) {
            let tests = unique(evidence.flatMap(\.tests))
            if tests.isEmpty {
                append(
                    id: "test-evidence-missing",
                    channel: .automatedTest,
                    severity: .error,
                    affectedLayer: .evaluation,
                    summary: "No focused regression test evidence is attached to this capability packet.",
                    requiredNextAction: "Attach focused tests or keep the capability below implemented status."
                )
            } else {
                append(
                    id: "test-evidence-present",
                    channel: .automatedTest,
                    severity: .info,
                    affectedLayer: .evaluation,
                    summary: "\(tests.count) focused regression test references are attached.",
                    requiredNextAction: "Keep tests aligned with the supported, rejected, degenerate, and performance cases."
                )
            }

            if evidence.isEmpty {
                append(
                    id: "implementation-evidence-missing",
                    channel: .humanReview,
                    severity: .error,
                    affectedLayer: .evaluation,
                    summary: "No implementation evidence is attached to this capability packet.",
                    requiredNextAction: "Attach source files, tests, or diagnostics before increasing the rating."
                )
            }
        }

        mutating func addGateAssessments(
            _ gateAssessments: [CADInteractionQualityGateAssessment]
        ) {
            for assessment in gateAssessments where assessment.rating != .verified {
                append(
                    id: "gate-\(assessment.gate.rawValue)-\(assessment.rating.rawValue)",
                    channel: observationChannel(for: assessment.gate),
                    severity: observationSeverity(for: assessment.rating),
                    affectedLayer: affectedLayer(for: assessment.gate),
                    summary: "\(assessment.gate.rawValue) is \(assessment.rating.rawValue).",
                    requiredNextAction: requiredAction(for: assessment.gate, rating: assessment.rating)
                )
            }
        }

        mutating func addRouteMatrix(_ routeMatrix: DesignProcessRouteMatrix) {
            let missingPorts = routeMatrix.missingRequiredPortKinds()
            for port in missingPorts {
                append(
                    id: "missing-route-port-\(port.rawValue)",
                    channel: .runtimeDiagnostic,
                    severity: .blocking,
                    affectedLayer: affectedLayer(for: port),
                    summary: "\(port.rawValue) route port is required but not covered.",
                    requiredNextAction: "Connect the required route port before broadening this capability."
                )
            }

            for route in routeMatrix.routes where route.status != .verified && route.status != .connected {
                append(
                    id: "route-\(route.id)-\(route.status.rawValue)",
                    channel: observationChannel(for: route),
                    severity: observationSeverity(for: route.status),
                    affectedLayer: affectedLayer(for: route.target.kind),
                    summary: "\(route.title) is \(route.status.rawValue).",
                    requiredNextAction: "Close or explicitly reject this route before claiming full parity."
                )
            }
        }

        mutating func addFlowGraphValidation(
            _ validation: DesignProcessFlowGraphValidationResult
        ) {
            if validation.isValid {
                append(
                    id: "flow-graph-connected",
                    channel: .runtimeDiagnostic,
                    severity: .info,
                    affectedLayer: .evaluation,
                    summary: "FlowGraph static connection check passed.",
                    requiredNextAction: "Keep route matrix and FlowGraph requirements in sync with capability expansion."
                )
                return
            }

            for (index, issue) in validation.issues.enumerated() {
                append(
                    id: "flow-graph-issue-\(index + 1)",
                    channel: .runtimeDiagnostic,
                    severity: .blocking,
                    affectedLayer: .evaluation,
                    summary: issue.message,
                    requiredNextAction: "Repair the disconnected FlowGraph port or route before implementation continues."
                )
            }
        }

        private mutating func append(
            id: String,
            channel: DesignProcessObservationChannel,
            severity: DesignProcessObservationSeverity,
            affectedLayer: DesignProcessLayer,
            summary: String,
            requiredNextAction: String
        ) {
            observations.append(
                DesignProcessObservation(
                    id: "\(area.rawValue)-\(id)",
                    channel: channel,
                    severity: severity,
                    affectedLayer: affectedLayer,
                    summary: summary,
                    requiredNextAction: requiredNextAction
                )
            )
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}

private func observationSeverity(
    for rating: CADInteractionQualityRating
) -> DesignProcessObservationSeverity {
    switch rating {
    case .missing:
        .error
    case .planned, .partial:
        .warning
    case .implemented, .verified:
        .info
    }
}

private func performanceMeasurementStatus(
    for rating: CADInteractionQualityRating
) -> DesignProcessPerformanceMeasurementStatus {
    switch rating {
    case .verified:
        .withinBudget
    case .implemented, .partial:
        .missingBudget
    case .planned, .missing:
        .unmeasured
    }
}

private func observationSeverity(
    for status: DesignProcessRouteStatus
) -> DesignProcessObservationSeverity {
    switch status {
    case .missing, .unsupported:
        .error
    case .planned, .partial:
        .warning
    case .connected, .verified:
        .info
    }
}

private func observationChannel(
    for gate: CADInteractionQualityGate
) -> DesignProcessObservationChannel {
    switch gate {
    case .agentParity:
        .agentReadback
    case .verification:
        .automatedTest
    case .performanceBudget:
        .performanceMeasurement
    case .measurementDiagnostics:
        .runtimeDiagnostic
    case .referenceContract,
         .sourceOwnership,
         .commandContract,
         .selectionTopology,
         .viewportAffordance,
         .inspectorAffordance:
        .runtimeDiagnostic
    }
}

private func observationChannel(
    for route: DesignProcessRoute
) -> DesignProcessObservationChannel {
    if route.source.kind == .agent || route.target.kind == .agent {
        return .agentReadback
    }
    if route.source.kind == .measurement || route.target.kind == .measurement {
        return .performanceMeasurement
    }
    return .runtimeDiagnostic
}

private func affectedLayer(
    for gate: CADInteractionQualityGate
) -> DesignProcessLayer {
    switch gate {
    case .referenceContract:
        .product
    case .sourceOwnership, .commandContract, .selectionTopology:
        .core
    case .viewportAffordance, .inspectorAffordance:
        .ui
    case .agentParity:
        .agent
    case .measurementDiagnostics:
        .diagnostics
    case .verification:
        .evaluation
    case .performanceBudget:
        .measurement
    }
}

private func affectedLayer(
    for port: DesignProcessRoutePortKind
) -> DesignProcessLayer {
    switch port {
    case .product:
        .product
    case .ui:
        .ui
    case .core:
        .core
    case .automation:
        .automation
    case .agent:
        .agent
    case .cli:
        .cli
    case .kernel:
        .kernel
    case .evaluation:
        .evaluation
    case .measurement:
        .measurement
    case .diagnostics:
        .diagnostics
    case .documentation, .export:
        .documentation
    }
}

private func affectedLayer(
    for openWork: String
) -> DesignProcessLayer {
    let lowered = openWork.lowercased()
    if lowered.contains("agent") {
        return .agent
    }
    if lowered.contains("cli") {
        return .cli
    }
    if lowered.contains("ui") || lowered.contains("viewport") || lowered.contains("inspector") {
        return .ui
    }
    if lowered.contains("kernel") || lowered.contains("swiftcad") || lowered.contains("brep") {
        return .kernel
    }
    if lowered.contains("performance")
        || lowered.contains("budget")
        || lowered.contains("dense")
        || lowered.contains("zero-copy")
        || lowered.contains("measurement") {
        return .measurement
    }
    if lowered.contains("diagnostic") {
        return .diagnostics
    }
    if lowered.contains("reference") || lowered.contains("product") || lowered.contains("plasticity") {
        return .product
    }
    if lowered.contains("topology")
        || lowered.contains("selection")
        || lowered.contains("source")
        || lowered.contains("command") {
        return .core
    }
    return .evaluation
}

private func requiredAction(
    for gate: CADInteractionQualityGate,
    rating: CADInteractionQualityRating
) -> String {
    if rating.score >= CADInteractionQualityRating.implemented.score {
        return "Promote \(gate.rawValue) from implemented to verified with direct evidence."
    }
    return "Implement or reject the missing \(gate.rawValue) channel before broadening this capability."
}
