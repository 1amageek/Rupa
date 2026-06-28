public struct DesignProcessPacket: Codable, Equatable, Sendable {
    public var id: String
    public var intent: DesignProcessIntent
    public var evaluation: DesignProcessEvaluationSpec
    public var domain: DesignProcessDomainModel
    public var caseMatrix: DesignProcessCaseMatrix
    public var routeMatrix: DesignProcessRouteMatrix
    public var constraintBinding: DesignProcessConstraintBinding
    public var resolution: DesignProcessResolution
    public var validatedArtifact: DesignProcessValidatedArtifact
    public var observations: [DesignProcessObservation]
    public var flowGraph: DesignProcessFlowGraph
    public var confidence: DesignProcessConfidence

    public init(
        id: String,
        intent: DesignProcessIntent,
        evaluation: DesignProcessEvaluationSpec,
        domain: DesignProcessDomainModel,
        caseMatrix: DesignProcessCaseMatrix,
        routeMatrix: DesignProcessRouteMatrix,
        constraintBinding: DesignProcessConstraintBinding,
        resolution: DesignProcessResolution,
        validatedArtifact: DesignProcessValidatedArtifact,
        observations: [DesignProcessObservation] = [],
        flowGraph: DesignProcessFlowGraph,
        confidence: DesignProcessConfidence
    ) {
        self.id = id
        self.intent = intent
        self.evaluation = evaluation
        self.domain = domain
        self.caseMatrix = caseMatrix
        self.routeMatrix = routeMatrix
        self.constraintBinding = constraintBinding
        self.resolution = resolution
        self.validatedArtifact = validatedArtifact
        self.observations = observations
        self.flowGraph = flowGraph
        self.confidence = confidence
    }

    public func validateFlowGraph() -> DesignProcessFlowGraphValidationResult {
        flowGraph.validate()
    }
}
