import Foundation
import RupaAutomation
import RupaCore

public struct AgentResponseEnvelope: Codable, Equatable, Sendable {
    public static let protocolVersion = "2.0"

    public var jsonrpc: String
    public var id: String?
    public var method: String?
    public var result: AgentResponse?
    public var error: AgentErrorEnvelope?

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case method
        case result
        case error
    }

    public init(
        id: String?,
        response: AgentResponse,
        method: String? = nil,
        jsonrpc: String = Self.protocolVersion
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method ?? Self.defaultMethodName(for: response)
        switch response {
        case .failure(let editorError):
            self.result = nil
            self.error = AgentErrorEnvelope(error: editorError)
        default:
            self.result = response
            self.error = nil
        }
    }

    public init(
        id: String?,
        method: String? = nil,
        result: AgentResponse?,
        error: AgentErrorEnvelope?,
        jsonrpc: String = Self.protocolVersion
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method ?? result.flatMap(Self.defaultMethodName(for:))
        self.result = result
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.method = try container.decodeIfPresent(String.self, forKey: .method)
        let hasResult = container.contains(.result)
        let hasError = container.contains(.error)
        guard hasResult != hasError else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent response envelope must contain exactly one result or error."
            )
        }
        if hasResult {
            guard let method else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Agent response result requires a method."
                )
            }
            self.result = try Self.decodeResult(method: method, from: container)
            self.error = nil
        } else if hasError {
            self.result = nil
            self.error = try container.decode(AgentErrorEnvelope.self, forKey: .error)
        } else {
            self.result = nil
            self.error = nil
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(method, forKey: .method)
        if let result {
            try encode(result: result, to: &container)
        }
        if let error {
            try container.encode(error, forKey: .error)
        }
    }

    public func decodedResponse() throws -> AgentResponse {
        try validate()
        if let result {
            return result
        }
        if let error {
            return .failure(error.editorError)
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Agent response envelope has no result or error."
        )
    }

    public func validate() throws {
        guard jsonrpc == Self.protocolVersion else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unsupported agent protocol version: \(jsonrpc)."
            )
        }
        let hasResult = result != nil
        let hasError = error != nil
        guard hasResult != hasError else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent response envelope must contain exactly one result or error."
            )
        }
        if let result, case .failure = result {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent failure responses must be encoded as response errors."
            )
        }
        if let result {
            guard let method else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Agent response result requires a method."
                )
            }
            guard Self.isCompatible(result: result, with: method) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Agent response result does not match method \(method)."
                )
            }
        }
    }

    private func encode(
        result: AgentResponse,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch result {
        case .capabilities(let value):
            try container.encode(value, forKey: .result)
        case .status(let value):
            try container.encode(value, forKey: .result)
        case .sessions(let value):
            try container.encode(value, forKey: .result)
        case .cadInteractionQualityAssessment(let value):
            try container.encode(value, forKey: .result)
        case .command(let value):
            try container.encode(value, forKey: .result)
        case .batch(let value):
            try container.encode(value, forKey: .result)
        case .parameters(let value):
            try container.encode(value, forKey: .result)
        case .evaluation(let value):
            try container.encode(value, forKey: .result)
        case .measurement(let value):
            try container.encode(value, forKey: .result)
        case .selectionMeasurement(let value):
            try container.encode(value, forKey: .result)
        case .snapResolution(let value):
            try container.encode(value, forKey: .result)
        case .constructionPlaneSummary(let value):
            try container.encode(value, forKey: .result)
        case .designDisplaySnapshot(let value):
            try container.encode(value, forKey: .result)
        case .patternArraySummary(let value):
            try container.encode(value, forKey: .result)
        case .meshSummary(let value):
            try container.encode(value, forKey: .result)
        case .polySplineMeshAnalysis(let value):
            try container.encode(value, forKey: .result)
        case .sketchEntitySummary(let value):
            try container.encode(value, forKey: .result)
        case .sketchDimensionSummary(let value):
            try container.encode(value, forKey: .result)
        case .selectionDimensionEvaluation(let value):
            try container.encode(value, forKey: .result)
        case .curveAnalysis(let value):
            try container.encode(value, forKey: .result)
        case .topologySummary(let value):
            try container.encode(value, forKey: .result)
        case .sweepEvaluationPlan(let value):
            try container.encode(value, forKey: .result)
        case .booleanEvaluationPlan(let value):
            try container.encode(value, forKey: .result)
        case .objectDimensionSummary(let value):
            try container.encode(value, forKey: .result)
        case .surfaceSourceSummary(let value):
            try container.encode(value, forKey: .result)
        case .surfaceAnalysis(let value):
            try container.encode(value, forKey: .result)
        case .surfaceFrames(let value):
            try container.encode(value, forKey: .result)
        case .surfaceContinuitySummary(let value):
            try container.encode(value, forKey: .result)
        case .surfaceBoundaryContinuityCompatibility(let value):
            try container.encode(value, forKey: .result)
        case .selection(let value):
            try container.encode(value, forKey: .result)
        case .save(let value):
            try container.encode(value, forKey: .result)
        case .export(let value):
            try container.encode(value, forKey: .result)
        case .failure:
            throw EditorError(
                code: .commandInvalid,
                message: "Agent failure responses must be encoded as response errors."
            )
        }
    }

    private static func decodeResult(
        method: String,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> AgentResponse {
        switch method {
        case "agent.capabilities":
            return .capabilities(
                try container.decode([AgentCapabilityDescriptor].self, forKey: .result)
            )
        case "agent.status":
            return .status(try container.decode(AgentStatus.self, forKey: .result))
        case "sessions.list":
            return .sessions(
                try container.decode([WorkspaceSessionSummary].self, forKey: .result)
            )
        case "agent.cadInteractionQualityAssessment":
            return .cadInteractionQualityAssessment(
                try container.decode(CADInteractionQualityAssessmentResult.self, forKey: .result)
            )
        case "command.apply",
             "parameter.setExpression",
             "document.setSurfaceFrameDisplay",
             "document.movePolySplineSurfaceVertex":
            return .command(try container.decode(AutomationResult.self, forKey: .result))
        case "command.applyBatch":
            return .batch(try container.decode(AgentBatchResult.self, forKey: .result))
        case "document.parameters":
            return .parameters(try container.decode(ParameterListResult.self, forKey: .result))
        case "document.evaluate":
            return .evaluation(try container.decode(EvaluationSnapshot.self, forKey: .result))
        case "document.measure":
            return .measurement(try container.decode(MeasurementResult.self, forKey: .result))
        case "selection.measure":
            return .selectionMeasurement(
                try container.decode(SelectionMeasurementResult.self, forKey: .result)
            )
        case "snap.resolve":
            return .snapResolution(try container.decode(SnapResolutionResult.self, forKey: .result))
        case "document.constructionPlaneSummary":
            return .constructionPlaneSummary(
                try container.decode(ConstructionPlaneSummaryResult.self, forKey: .result)
            )
        case "document.designDisplaySnapshot":
            return .designDisplaySnapshot(
                try container.decode(DesignDisplaySnapshotResult.self, forKey: .result)
            )
        case "document.patternArraySummary":
            return .patternArraySummary(
                try container.decode(PatternArraySummaryResult.self, forKey: .result)
            )
        case "document.meshSummary":
            return .meshSummary(try container.decode(MeshSummaryResult.self, forKey: .result))
        case "document.polySplineMeshAnalysis":
            return .polySplineMeshAnalysis(
                try container.decode(PolySplineMeshAnalysisResult.self, forKey: .result)
            )
        case "document.sketchEntitySummary":
            return .sketchEntitySummary(
                try container.decode(SketchEntitySummaryResult.self, forKey: .result)
            )
        case "document.sketchDimensionSummary":
            return .sketchDimensionSummary(
                try container.decode(SketchDimensionSummaryResult.self, forKey: .result)
            )
        case "selection.dimensionEvaluation":
            return .selectionDimensionEvaluation(
                try container.decode(SelectionDimensionEvaluationResult.self, forKey: .result)
            )
        case "document.curveAnalysis":
            return .curveAnalysis(try container.decode(CurveAnalysisResult.self, forKey: .result))
        case "document.topologySummary":
            return .topologySummary(try container.decode(TopologySummaryResult.self, forKey: .result))
        case "document.sweepEvaluationPlan":
            return .sweepEvaluationPlan(
                try container.decode(SweepEvaluationPlanResult.self, forKey: .result)
            )
        case "document.booleanEvaluationPlan":
            return .booleanEvaluationPlan(
                try container.decode(BooleanEvaluationPlanResult.self, forKey: .result)
            )
        case "document.objectDimensionSummary":
            return .objectDimensionSummary(
                try container.decode(ObjectDimensionSummaryResult.self, forKey: .result)
            )
        case "document.surfaceSourceSummary":
            return .surfaceSourceSummary(
                try container.decode(SurfaceSourceSummaryResult.self, forKey: .result)
            )
        case "document.surfaceAnalysis":
            return .surfaceAnalysis(try container.decode(SurfaceAnalysisResult.self, forKey: .result))
        case "document.surfaceFrames":
            return .surfaceFrames(try container.decode(SurfaceFrameResult.self, forKey: .result))
        case "document.surfaceContinuitySummary":
            return .surfaceContinuitySummary(
                try container.decode(RupaCore.SurfaceContinuityResult.self, forKey: .result)
            )
        case "document.surfaceBoundaryContinuityCompatibility":
            return .surfaceBoundaryContinuityCompatibility(
                try container.decode(SurfaceBoundaryContinuityCompatibilityResult.self, forKey: .result)
            )
        case "selection.selectTargets",
             "selection.selectReferences":
            return .selection(try container.decode(SelectionStateResult.self, forKey: .result))
        case "document.save":
            return .save(try container.decode(SaveResult.self, forKey: .result))
        case "document.export":
            return .export(try container.decode(ExportResult.self, forKey: .result))
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "Unsupported agent response method: \(method)."
            )
        }
    }

    private static func defaultMethodName(for response: AgentResponse) -> String? {
        switch response {
        case .capabilities:
            "agent.capabilities"
        case .status:
            "agent.status"
        case .sessions:
            "sessions.list"
        case .cadInteractionQualityAssessment:
            "agent.cadInteractionQualityAssessment"
        case .command:
            "command.apply"
        case .batch:
            "command.applyBatch"
        case .parameters:
            "document.parameters"
        case .evaluation:
            "document.evaluate"
        case .measurement:
            "document.measure"
        case .selectionMeasurement:
            "selection.measure"
        case .snapResolution:
            "snap.resolve"
        case .constructionPlaneSummary:
            "document.constructionPlaneSummary"
        case .designDisplaySnapshot:
            "document.designDisplaySnapshot"
        case .patternArraySummary:
            "document.patternArraySummary"
        case .meshSummary:
            "document.meshSummary"
        case .polySplineMeshAnalysis:
            "document.polySplineMeshAnalysis"
        case .sketchEntitySummary:
            "document.sketchEntitySummary"
        case .sketchDimensionSummary:
            "document.sketchDimensionSummary"
        case .selectionDimensionEvaluation:
            "selection.dimensionEvaluation"
        case .curveAnalysis:
            "document.curveAnalysis"
        case .topologySummary:
            "document.topologySummary"
        case .sweepEvaluationPlan:
            "document.sweepEvaluationPlan"
        case .booleanEvaluationPlan:
            "document.booleanEvaluationPlan"
        case .objectDimensionSummary:
            "document.objectDimensionSummary"
        case .surfaceSourceSummary:
            "document.surfaceSourceSummary"
        case .surfaceAnalysis:
            "document.surfaceAnalysis"
        case .surfaceFrames:
            "document.surfaceFrames"
        case .surfaceContinuitySummary:
            "document.surfaceContinuitySummary"
        case .surfaceBoundaryContinuityCompatibility:
            "document.surfaceBoundaryContinuityCompatibility"
        case .selection:
            "selection.selectTargets"
        case .save:
            "document.save"
        case .export:
            "document.export"
        case .failure:
            nil
        }
    }

    private static func isCompatible(result: AgentResponse, with method: String) -> Bool {
        switch (method, result) {
        case ("agent.capabilities", .capabilities),
             ("agent.status", .status),
             ("sessions.list", .sessions),
             ("agent.cadInteractionQualityAssessment", .cadInteractionQualityAssessment),
             ("command.apply", .command),
             ("command.applyBatch", .batch),
             ("parameter.setExpression", .command),
             ("document.setSurfaceFrameDisplay", .command),
             ("document.movePolySplineSurfaceVertex", .command),
             ("document.parameters", .parameters),
             ("document.evaluate", .evaluation),
             ("document.measure", .measurement),
             ("selection.measure", .selectionMeasurement),
             ("snap.resolve", .snapResolution),
             ("document.constructionPlaneSummary", .constructionPlaneSummary),
             ("document.designDisplaySnapshot", .designDisplaySnapshot),
             ("document.patternArraySummary", .patternArraySummary),
             ("document.meshSummary", .meshSummary),
             ("document.polySplineMeshAnalysis", .polySplineMeshAnalysis),
             ("document.sketchEntitySummary", .sketchEntitySummary),
             ("document.sketchDimensionSummary", .sketchDimensionSummary),
             ("selection.dimensionEvaluation", .selectionDimensionEvaluation),
             ("document.curveAnalysis", .curveAnalysis),
             ("document.topologySummary", .topologySummary),
             ("document.sweepEvaluationPlan", .sweepEvaluationPlan),
             ("document.booleanEvaluationPlan", .booleanEvaluationPlan),
             ("document.objectDimensionSummary", .objectDimensionSummary),
             ("document.surfaceSourceSummary", .surfaceSourceSummary),
             ("document.surfaceAnalysis", .surfaceAnalysis),
             ("document.surfaceFrames", .surfaceFrames),
             ("document.surfaceContinuitySummary", .surfaceContinuitySummary),
             ("document.surfaceBoundaryContinuityCompatibility", .surfaceBoundaryContinuityCompatibility),
             ("selection.selectTargets", .selection),
             ("selection.selectReferences", .selection),
             ("document.save", .save),
             ("document.export", .export):
            true
        default:
            false
        }
    }
}
