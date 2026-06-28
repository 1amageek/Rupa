import Foundation
import Testing
import RupaCore

@Test func designProcessPacketRoundTripsThroughJSON() throws {
    let packet = makeDesignProcessPacket()
    let encoded = try JSONEncoder().encode(packet)
    let decoded = try JSONDecoder().decode(DesignProcessPacket.self, from: encoded)

    #expect(decoded == packet)
    #expect(decoded.caseMatrix.cases.map(\.id) == ["sweep-supported", "sweep-missing"])
    #expect(decoded.routeMatrix.missingRequiredPortKinds().isEmpty)
    #expect(decoded.flowGraph.validate().isValid)
    #expect(decoded.confidence.score > 0)
}

@Test func designProcessFlowGraphValidationAcceptsConnectedRequiredPorts() {
    let graph = makeConnectedFlowGraph()

    let result = graph.validate()

    #expect(result.isValid)
    #expect(result.issues.isEmpty)
}

@Test func designProcessFlowGraphValidationReportsStaticConnectionFailures() {
    let graph = DesignProcessFlowGraph(
        nodes: [
            DesignProcessFlowNode(
                id: "ui",
                title: "UI",
                layer: .ui,
                ports: [
                    DesignProcessFlowPort(id: "intent", title: "Intent", direction: .output),
                ]
            ),
            DesignProcessFlowNode(
                id: "core",
                title: "Core",
                layer: .core,
                ports: [
                    DesignProcessFlowPort(id: "command", title: "Command", direction: .input),
                    DesignProcessFlowPort(id: "diagnostic", title: "Diagnostic", direction: .output),
                ]
            ),
            DesignProcessFlowNode(
                id: "measurement",
                title: "Measurement",
                layer: .measurement,
                ports: [
                    DesignProcessFlowPort(id: "readback", title: "Readback", direction: .input),
                ]
            ),
        ],
        edges: [
            DesignProcessFlowEdge(
                id: "ui-core",
                sourceNodeID: "ui",
                sourcePortID: "intent",
                targetNodeID: "core",
                targetPortID: "command"
            ),
            DesignProcessFlowEdge(
                id: "dangling-diagnostic",
                sourceNodeID: "core",
                sourcePortID: "diagnostic",
                targetNodeID: "diagnostics",
                targetPortID: "message"
            ),
        ],
        requiredPorts: [
            DesignProcessFlowPortRequirement(
                nodeID: "core",
                portID: "diagnostic",
                connection: .outgoing,
                reason: "Core diagnostics must reach a diagnostics surface."
            ),
            DesignProcessFlowPortRequirement(
                nodeID: "measurement",
                portID: "readback",
                connection: .incoming,
                reason: "Measurement readback must be reachable."
            ),
        ]
    )

    let result = graph.validate()
    let kinds = Set(result.issues.map(\.kind))

    #expect(!result.isValid)
    #expect(kinds.contains(.danglingEdgeTargetNode))
    #expect(kinds.contains(.floatingRequiredOutput))
    #expect(kinds.contains(.unreachableRequiredInput))
    #expect(kinds.contains(.deadEndNode))
}

@Test func designProcessRouteMatrixReportsMissingRequiredPorts() {
    let routeMatrix = DesignProcessRouteMatrix(
        requiredPorts: [.ui, .core, .agent, .kernel],
        routes: [
            DesignProcessRoute(
                id: "ui-core",
                title: "UI to Core",
                source: DesignProcessRoutePort(kind: .ui, identifier: "toolbar", title: "Toolbar"),
                target: DesignProcessRoutePort(kind: .core, identifier: "command", title: "Command"),
                status: .connected
            ),
        ]
    )

    #expect(routeMatrix.missingRequiredPortKinds() == [.agent, .kernel])
}

private func makeDesignProcessPacket() -> DesignProcessPacket {
    let testReference = DesignProcessTestReference(
        target: "RupaCoreTests",
        name: "designProcessPacketRoundTripsThroughJSON",
        command: "xcodebuild test -scheme RupaKit -only-testing:RupaCoreTests/DesignProcessPacketTests",
        file: "RupaKit/Tests/RupaCoreTests/DesignProcessPacketTests.swift"
    )

    return DesignProcessPacket(
        id: "sweep-guide-design-packet",
        intent: DesignProcessIntent(
            capabilityID: "sweep-guide",
            title: "Sweep with guide constraints",
            outcome: "Create a validated CAD sweep route that can be operated from UI and Agent surfaces.",
            area: .sweep,
            sourceOfTruth: .core,
            referenceSources: ["Rupa/DESIGN_PROCESS.md"]
        ),
        evaluation: DesignProcessEvaluationSpec(
            successCriteria: ["Preflight reports unsupported guide sets before mutation."],
            diagnosticRequirements: ["Guide constraint failures must be structured."],
            performanceBudget: "Preflight must avoid mutating the document.",
            requiredEvidence: ["Focused core tests"]
        ),
        domain: DesignProcessDomainModel(
            sourceEntities: ["section profile", "path curve", "guide curve"],
            targetEntities: ["solid body"],
            generatedTopology: ["generated faces", "generated edges"],
            units: "document units",
            tolerances: ["kernel tolerance"],
            ownershipBoundaries: ["RupaCore owns command route", "SwiftCAD owns kernel evaluation"]
        ),
        caseMatrix: DesignProcessCaseMatrix(
            supported: DesignProcessCaseGroup(
                kind: .supported,
                cases: [
                    DesignProcessCase(
                        id: "sweep-supported",
                        title: "Supported guide sweep",
                        status: .verified,
                        testReferences: [testReference],
                        evidence: ["Sweep command route exists."]
                    ),
                ]
            ),
            missing: DesignProcessCaseGroup(
                kind: .missing,
                cases: [
                    DesignProcessCase(
                        id: "sweep-missing",
                        title: "Variable section law",
                        status: .missing,
                        diagnostic: DesignProcessDiagnostic(
                            id: "missing-variable-law",
                            severity: .warning,
                            message: "Variable section law is not modeled yet.",
                            affectedLayer: .kernel
                        )
                    ),
                ]
            )
        ),
        routeMatrix: DesignProcessRouteMatrix(
            requiredPorts: [.ui, .core, .agent, .kernel, .diagnostics],
            routes: [
                DesignProcessRoute(
                    id: "ui-core",
                    title: "UI command route",
                    source: DesignProcessRoutePort(kind: .ui, identifier: "sweep-tool", title: "Sweep Tool"),
                    target: DesignProcessRoutePort(kind: .core, identifier: "sweep-command", title: "Sweep Command"),
                    status: .connected,
                    evidence: DesignProcessRouteEvidence(tests: [testReference])
                ),
                DesignProcessRoute(
                    id: "agent-core",
                    title: "Agent command route",
                    source: DesignProcessRoutePort(kind: .agent, identifier: "sweep-request", title: "Sweep Request"),
                    target: DesignProcessRoutePort(kind: .core, identifier: "sweep-command", title: "Sweep Command"),
                    status: .connected
                ),
                DesignProcessRoute(
                    id: "core-kernel",
                    title: "Kernel evaluation route",
                    source: DesignProcessRoutePort(kind: .core, identifier: "preflight", title: "Preflight"),
                    target: DesignProcessRoutePort(kind: .kernel, identifier: "sweep-evaluator", title: "Sweep Evaluator"),
                    status: .connected
                ),
                DesignProcessRoute(
                    id: "core-diagnostics",
                    title: "Diagnostic route",
                    source: DesignProcessRoutePort(kind: .core, identifier: "diagnostic", title: "Diagnostic"),
                    target: DesignProcessRoutePort(kind: .diagnostics, identifier: "readback", title: "Readback"),
                    status: .connected
                ),
            ]
        ),
        constraintBinding: DesignProcessConstraintBinding(
            validationRules: ["Preflight must run before document mutation."],
            invariants: [
                DesignProcessInvariant(
                    id: "no-mutation-on-failure",
                    title: "No mutation on failed preflight",
                    requiredLayer: .core,
                    verification: "Focused command tests"
                ),
            ]
        ),
        resolution: DesignProcessResolution(
            selectedRouteIDs: ["ui-core", "agent-core", "core-kernel", "core-diagnostics"],
            decisions: [
                DesignProcessDecisionRecord(
                    id: "preflight-first",
                    conflictArea: "Mutation safety",
                    selectedRouteID: "core-kernel",
                    rationale: "Kernel constraint solving must fail before Core mutates the document.",
                    followUpOwner: .core
                ),
            ]
        ),
        validatedArtifact: DesignProcessValidatedArtifact(
            sourceFiles: ["RupaKit/Sources/RupaCore/DesignProcessPacket.swift"],
            tests: [testReference],
            buildCommands: ["xcodebuild test -scheme RupaKit -only-testing:RupaCoreTests/DesignProcessPacketTests"],
            supportedClaims: ["Packet can represent D1 DBN artifacts."]
        ),
        observations: [
            DesignProcessObservation(
                id: "missing-assessment-connection",
                channel: .humanReview,
                severity: .warning,
                affectedLayer: .evaluation,
                summary: "Assessment entries do not emit packets yet.",
                requiredNextAction: "Connect CADInteractionQualityAssessmentService to typed packets."
            ),
        ],
        flowGraph: makeConnectedFlowGraph(),
        confidence: DesignProcessConfidence(
            evidenceFreshness: 1,
            testCoverage: 0.75,
            performanceCoverage: 0.25,
            missingChannelPenalty: 0.2,
            calibrationState: .humanAnchored,
            notes: ["D1 model is typed; assessment integration is pending."]
        )
    )
}

private func makeConnectedFlowGraph() -> DesignProcessFlowGraph {
    DesignProcessFlowGraph(
        nodes: [
            DesignProcessFlowNode(
                id: "ui",
                title: "UI",
                layer: .ui,
                ports: [
                    DesignProcessFlowPort(id: "intent", title: "Intent", direction: .output),
                ]
            ),
            DesignProcessFlowNode(
                id: "core",
                title: "Core",
                layer: .core,
                ports: [
                    DesignProcessFlowPort(id: "command", title: "Command", direction: .input),
                    DesignProcessFlowPort(id: "kernel-request", title: "Kernel Request", direction: .output),
                    DesignProcessFlowPort(id: "kernel-result", title: "Kernel Result", direction: .input),
                    DesignProcessFlowPort(id: "diagnostic", title: "Diagnostic", direction: .output),
                ]
            ),
            DesignProcessFlowNode(
                id: "kernel",
                title: "Kernel",
                layer: .kernel,
                ports: [
                    DesignProcessFlowPort(id: "evaluate", title: "Evaluate", direction: .input),
                    DesignProcessFlowPort(id: "result", title: "Result", direction: .output),
                ]
            ),
            DesignProcessFlowNode(
                id: "diagnostics",
                title: "Diagnostics",
                layer: .diagnostics,
                ports: [
                    DesignProcessFlowPort(id: "message", title: "Message", direction: .input),
                ]
            ),
        ],
        edges: [
            DesignProcessFlowEdge(
                id: "ui-core",
                sourceNodeID: "ui",
                sourcePortID: "intent",
                targetNodeID: "core",
                targetPortID: "command"
            ),
            DesignProcessFlowEdge(
                id: "core-kernel",
                sourceNodeID: "core",
                sourcePortID: "kernel-request",
                targetNodeID: "kernel",
                targetPortID: "evaluate"
            ),
            DesignProcessFlowEdge(
                id: "kernel-core",
                sourceNodeID: "kernel",
                sourcePortID: "result",
                targetNodeID: "core",
                targetPortID: "kernel-result"
            ),
            DesignProcessFlowEdge(
                id: "core-diagnostics",
                sourceNodeID: "core",
                sourcePortID: "diagnostic",
                targetNodeID: "diagnostics",
                targetPortID: "message"
            ),
        ],
        requiredPorts: [
            DesignProcessFlowPortRequirement(
                nodeID: "ui",
                portID: "intent",
                connection: .outgoing,
                reason: "The user-facing affordance must reach Core."
            ),
            DesignProcessFlowPortRequirement(
                nodeID: "core",
                portID: "command",
                connection: .incoming,
                reason: "Core must receive the command."
            ),
            DesignProcessFlowPortRequirement(
                nodeID: "core",
                portID: "kernel-request",
                connection: .outgoing,
                reason: "Core must request kernel evaluation."
            ),
            DesignProcessFlowPortRequirement(
                nodeID: "kernel",
                portID: "evaluate",
                connection: .incoming,
                reason: "Kernel evaluation must be reachable."
            ),
            DesignProcessFlowPortRequirement(
                nodeID: "kernel",
                portID: "result",
                connection: .outgoing,
                reason: "Kernel result must return to Core."
            ),
            DesignProcessFlowPortRequirement(
                nodeID: "core",
                portID: "kernel-result",
                connection: .incoming,
                reason: "Core must receive kernel result."
            ),
            DesignProcessFlowPortRequirement(
                nodeID: "core",
                portID: "diagnostic",
                connection: .outgoing,
                reason: "Core diagnostics must reach readback."
            ),
            DesignProcessFlowPortRequirement(
                nodeID: "diagnostics",
                portID: "message",
                connection: .incoming,
                reason: "Diagnostics surface must receive failures."
            ),
        ]
    )
}
