import Foundation
import RupaAutomation
import RupaCore

public struct AgentRequestEnvelope: Codable, Equatable, Sendable {
    public static let protocolVersion = "2.0"

    public var jsonrpc: String
    public var id: String
    public var method: String
    public var params: AgentRequest

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case method
        case params
    }

    public init(
        id: String,
        method: String? = nil,
        params: AgentRequest,
        jsonrpc: String = Self.protocolVersion
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method ?? params.methodName
        self.params = params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        self.id = try container.decode(String.self, forKey: .id)
        self.method = try container.decode(String.self, forKey: .method)
        self.params = try Self.decodeRequest(method: method, from: container)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try encodeParams(to: &container)
    }

    public func validate() throws {
        guard jsonrpc == Self.protocolVersion else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unsupported agent protocol version: \(jsonrpc)."
            )
        }
        guard method == params.methodName else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent request method \(method) does not match payload method \(params.methodName)."
            )
        }
    }

    private func encodeParams(to container: inout KeyedEncodingContainer<CodingKeys>) throws {
        switch params {
        case .capabilities,
             .status,
             .sessions,
             .cadInteractionQualityAssessment:
            try container.encode(EmptyParams(), forKey: .params)
        case let .execute(sessionID, command, expectedGeneration):
            try container.encode(
                ExecuteParams(
                    sessionID: sessionID,
                    command: command,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .parameters(sessionID, expectedGeneration):
            try container.encode(
                SessionGenerationParams(
                    sessionID: sessionID,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .setParameterExpression(sessionID, name, expression, kind, defaults, expectedGeneration):
            try container.encode(
                SetParameterExpressionParams(
                    sessionID: sessionID,
                    name: name,
                    expression: expression,
                    kind: kind,
                    defaults: defaults,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .evaluate(sessionID, expectedGeneration),
             let .measure(sessionID, expectedGeneration),
             let .constructionPlaneSummary(sessionID, expectedGeneration),
             let .designDisplaySnapshot(sessionID, expectedGeneration),
             let .patternArraySummary(sessionID, expectedGeneration),
             let .meshSummary(sessionID, expectedGeneration),
             let .sketchEntitySummary(sessionID, expectedGeneration),
             let .curveAnalysis(sessionID, expectedGeneration),
             let .topologySummary(sessionID, expectedGeneration),
             let .surfaceSourceSummary(sessionID, expectedGeneration),
             let .surfaceContinuitySummary(sessionID, expectedGeneration),
             let .save(sessionID, expectedGeneration):
            try container.encode(
                SessionGenerationParams(
                    sessionID: sessionID,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .selectionMeasurement(sessionID, query, expectedGeneration):
            try container.encode(
                SelectionMeasurementParams(
                    sessionID: sessionID,
                    query: query,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .resolveSnap(sessionID, point, options, expectedGeneration):
            try container.encode(
                ResolveSnapParams(
                    sessionID: sessionID,
                    point: point,
                    options: options,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .polySplineMeshAnalysis(sessionID, sourceMesh, options, expectedGeneration):
            try container.encode(
                PolySplineMeshAnalysisParams(
                    sessionID: sessionID,
                    sourceMesh: sourceMesh,
                    options: options,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .sweepEvaluationPlan(sessionID, sections, path, guides, targets, options, expectedGeneration):
            try container.encode(
                SweepEvaluationPlanParams(
                    sessionID: sessionID,
                    sections: sections,
                    path: path,
                    guides: guides,
                    targets: targets,
                    options: options,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .sketchDimensionSummary(sessionID, targets, expectedGeneration),
             let .objectDimensionSummary(sessionID, targets, expectedGeneration),
             let .selectTargets(sessionID, targets, expectedGeneration):
            try container.encode(
                SelectionTargetsParams(
                    sessionID: sessionID,
                    targets: targets,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .selectReferences(sessionID, references, expectedGeneration):
            try container.encode(
                SelectionReferencesParams(
                    sessionID: sessionID,
                    references: references,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .selectionDimensionEvaluation(sessionID, dimensionID, expectedGeneration):
            try container.encode(
                SelectionDimensionEvaluationParams(
                    sessionID: sessionID,
                    dimensionID: dimensionID,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .surfaceAnalysis(sessionID, options, expectedGeneration):
            try container.encode(
                SurfaceAnalysisParams(
                    sessionID: sessionID,
                    options: options,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .surfaceFrames(sessionID, queries, expectedGeneration):
            try container.encode(
                SurfaceFramesParams(
                    sessionID: sessionID,
                    queries: queries,
                    expectedGeneration: expectedGeneration
                ),
                forKey: .params
            )
        case let .export(sessionID, outputPath, expectedGeneration, options, dryRun):
            try container.encode(
                ExportParams(
                    sessionID: sessionID,
                    outputPath: outputPath,
                    expectedGeneration: expectedGeneration,
                    options: options,
                    dryRun: dryRun
                ),
                forKey: .params
            )
        }
    }

    private static func decodeRequest(
        method: String,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> AgentRequest {
        switch method {
        case "agent.capabilities":
            try decodeEmptyParams(from: container, method: method)
            return .capabilities
        case "agent.status":
            try decodeEmptyParams(from: container, method: method)
            return .status
        case "sessions.list":
            try decodeEmptyParams(from: container, method: method)
            return .sessions
        case "agent.cadInteractionQualityAssessment":
            try decodeEmptyParams(from: container, method: method)
            return .cadInteractionQualityAssessment
        case "command.apply":
            let payload = try decodeParams(ExecuteParams.self, from: container, method: method)
            return .execute(
                sessionID: payload.sessionID,
                command: payload.command,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.parameters":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .parameters(
                sessionID: payload.sessionID,
                expectedGeneration: payload.expectedGeneration
            )
        case "parameter.setExpression":
            let payload = try decodeParams(SetParameterExpressionParams.self, from: container, method: method)
            return .setParameterExpression(
                sessionID: payload.sessionID,
                name: payload.name,
                expression: payload.expression,
                kind: payload.kind,
                defaults: payload.defaults,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.evaluate":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .evaluate(sessionID: payload.sessionID, expectedGeneration: payload.expectedGeneration)
        case "document.measure":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .measure(sessionID: payload.sessionID, expectedGeneration: payload.expectedGeneration)
        case "selection.measure":
            let payload = try decodeParams(SelectionMeasurementParams.self, from: container, method: method)
            return .selectionMeasurement(
                sessionID: payload.sessionID,
                query: payload.query,
                expectedGeneration: payload.expectedGeneration
            )
        case "snap.resolve":
            let payload = try decodeParams(ResolveSnapParams.self, from: container, method: method)
            return .resolveSnap(
                sessionID: payload.sessionID,
                point: payload.point,
                options: payload.options,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.constructionPlaneSummary":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .constructionPlaneSummary(
                sessionID: payload.sessionID,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.designDisplaySnapshot":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .designDisplaySnapshot(
                sessionID: payload.sessionID,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.patternArraySummary":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .patternArraySummary(
                sessionID: payload.sessionID,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.meshSummary":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .meshSummary(sessionID: payload.sessionID, expectedGeneration: payload.expectedGeneration)
        case "document.polySplineMeshAnalysis":
            let payload = try decodeParams(PolySplineMeshAnalysisParams.self, from: container, method: method)
            return .polySplineMeshAnalysis(
                sessionID: payload.sessionID,
                sourceMesh: payload.sourceMesh,
                options: payload.options,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.sketchEntitySummary":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .sketchEntitySummary(
                sessionID: payload.sessionID,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.sketchDimensionSummary":
            let payload = try decodeParams(SelectionTargetsParams.self, from: container, method: method)
            return .sketchDimensionSummary(
                sessionID: payload.sessionID,
                targets: payload.targets,
                expectedGeneration: payload.expectedGeneration
            )
        case "selection.dimensionEvaluation":
            let payload = try decodeParams(SelectionDimensionEvaluationParams.self, from: container, method: method)
            return .selectionDimensionEvaluation(
                sessionID: payload.sessionID,
                dimensionID: payload.dimensionID,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.curveAnalysis":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .curveAnalysis(sessionID: payload.sessionID, expectedGeneration: payload.expectedGeneration)
        case "document.topologySummary":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .topologySummary(sessionID: payload.sessionID, expectedGeneration: payload.expectedGeneration)
        case "document.sweepEvaluationPlan":
            let payload = try decodeParams(SweepEvaluationPlanParams.self, from: container, method: method)
            return .sweepEvaluationPlan(
                sessionID: payload.sessionID,
                sections: payload.sections,
                path: payload.path,
                guides: payload.guides,
                targets: payload.targets,
                options: payload.options,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.objectDimensionSummary":
            let payload = try decodeParams(SelectionTargetsParams.self, from: container, method: method)
            return .objectDimensionSummary(
                sessionID: payload.sessionID,
                targets: payload.targets,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.surfaceSourceSummary":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .surfaceSourceSummary(
                sessionID: payload.sessionID,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.surfaceAnalysis":
            let payload = try decodeParams(SurfaceAnalysisParams.self, from: container, method: method)
            return .surfaceAnalysis(
                sessionID: payload.sessionID,
                options: payload.options,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.surfaceFrames":
            let payload = try decodeParams(SurfaceFramesParams.self, from: container, method: method)
            return .surfaceFrames(
                sessionID: payload.sessionID,
                queries: payload.queries,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.surfaceContinuitySummary":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .surfaceContinuitySummary(
                sessionID: payload.sessionID,
                expectedGeneration: payload.expectedGeneration
            )
        case "selection.selectTargets":
            let payload = try decodeParams(SelectionTargetsParams.self, from: container, method: method)
            return .selectTargets(
                sessionID: payload.sessionID,
                targets: payload.targets,
                expectedGeneration: payload.expectedGeneration
            )
        case "selection.selectReferences":
            let payload = try decodeParams(SelectionReferencesParams.self, from: container, method: method)
            return .selectReferences(
                sessionID: payload.sessionID,
                references: payload.references,
                expectedGeneration: payload.expectedGeneration
            )
        case "document.save":
            let payload = try decodeParams(SessionGenerationParams.self, from: container, method: method)
            return .save(sessionID: payload.sessionID, expectedGeneration: payload.expectedGeneration)
        case "document.export":
            let payload = try decodeParams(ExportParams.self, from: container, method: method)
            return .export(
                sessionID: payload.sessionID,
                outputPath: payload.outputPath,
                expectedGeneration: payload.expectedGeneration,
                options: payload.options,
                dryRun: payload.dryRun
            )
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "Unsupported agent request method: \(method)."
            )
        }
    }

    private static func decodeEmptyParams(
        from container: KeyedDecodingContainer<CodingKeys>,
        method: String
    ) throws {
        guard container.contains(.params) else {
            return
        }
        let decoder = try container.superDecoder(forKey: .params)
        try validateParamsKeys(from: decoder, allowedKeys: EmptyParams.allowedKeys, method: method)
    }

    private static func decodeParams<Payload: AgentRequestParameterPayload>(
        _ type: Payload.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        method: String
    ) throws -> Payload {
        guard container.contains(.params) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent request method \(method) requires params."
            )
        }
        let decoder = try container.superDecoder(forKey: .params)
        try validateParamsKeys(from: decoder, allowedKeys: Payload.allowedKeys, method: method)
        return try Payload(from: decoder)
    }

    private static func validateParamsKeys(
        from decoder: Decoder,
        allowedKeys: Set<String>,
        method: String
    ) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let unknownKeys = Set(container.allKeys.map(\.stringValue)).subtracting(allowedKeys)
        guard unknownKeys.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unsupported params for \(method): \(unknownKeys.sorted().joined(separator: ", "))."
            )
        }
    }
}

private protocol AgentRequestParameterPayload: Codable, Sendable {
    static var allowedKeys: Set<String> { get }
}

private struct EmptyParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = []
}

private struct SessionGenerationParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = ["sessionID", "expectedGeneration"]

    var sessionID: UUID
    var expectedGeneration: DocumentGeneration?
}

private struct ExecuteParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = ["sessionID", "command", "expectedGeneration"]

    var sessionID: UUID
    var command: AutomationCommand
    var expectedGeneration: DocumentGeneration?
}

private struct SetParameterExpressionParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = [
        "sessionID",
        "name",
        "expression",
        "kind",
        "defaults",
        "expectedGeneration",
    ]

    var sessionID: UUID
    var name: String
    var expression: String
    var kind: QuantityKind
    var defaults: ParameterExpressionDefaults
    var expectedGeneration: DocumentGeneration?
}

private struct SelectionMeasurementParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = ["sessionID", "query", "expectedGeneration"]

    var sessionID: UUID
    var query: CADAgentMeasurementQuery
    var expectedGeneration: DocumentGeneration?
}

private struct ResolveSnapParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = ["sessionID", "point", "options", "expectedGeneration"]

    var sessionID: UUID
    var point: Point2D
    var options: SnapResolutionOptions
    var expectedGeneration: DocumentGeneration?
}

private struct PolySplineMeshAnalysisParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = ["sessionID", "sourceMesh", "options", "expectedGeneration"]

    var sessionID: UUID
    var sourceMesh: Mesh
    var options: PolySplineOptions
    var expectedGeneration: DocumentGeneration?
}

private struct SelectionTargetsParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = ["sessionID", "targets", "expectedGeneration"]

    var sessionID: UUID
    var targets: [SelectionTarget]
    var expectedGeneration: DocumentGeneration?
}

private struct SelectionReferencesParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = ["sessionID", "references", "expectedGeneration"]

    var sessionID: UUID
    var references: [SelectionReference]
    var expectedGeneration: DocumentGeneration?
}

private struct SelectionDimensionEvaluationParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = ["sessionID", "dimensionID", "expectedGeneration"]

    var sessionID: UUID
    var dimensionID: SelectionDimensionID?
    var expectedGeneration: DocumentGeneration?
}

private struct SurfaceAnalysisParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = ["sessionID", "options", "expectedGeneration"]

    var sessionID: UUID
    var options: SurfaceAnalysisOptions
    var expectedGeneration: DocumentGeneration?
}

private struct SurfaceFramesParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = ["sessionID", "queries", "expectedGeneration"]

    var sessionID: UUID
    var queries: [SurfaceFrameQuery]
    var expectedGeneration: DocumentGeneration?
}

private struct SweepEvaluationPlanParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = [
        "sessionID",
        "sections",
        "path",
        "guides",
        "targets",
        "options",
        "expectedGeneration",
    ]

    var sessionID: UUID
    var sections: [SweepSectionReference]
    var path: SweepPathReference
    var guides: [SweepGuideReference]
    var targets: [SweepTargetReference]
    var options: SweepOptions
    var expectedGeneration: DocumentGeneration?
}

private struct ExportParams: AgentRequestParameterPayload, Equatable {
    static let allowedKeys: Set<String> = [
        "sessionID",
        "outputPath",
        "expectedGeneration",
        "options",
        "dryRun",
    ]

    var sessionID: UUID
    var outputPath: String
    var expectedGeneration: DocumentGeneration?
    var options: ExportOptions
    var dryRun: Bool
}

private struct AnyCodingKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
