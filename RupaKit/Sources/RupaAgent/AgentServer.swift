import Foundation
import RupaAutomation
import RupaCore

public final class AgentServer: AgentClientProtocol {
    public var name: String
    public var socketPath: String?
    private let registry: WorkspaceRegistry
    private let runner: AutomationRunner
    private let exportService: DocumentExportService
    private let fileService: DocumentFileService

    public init(
        name: String = "Rupa Agent",
        socketPath: String? = nil,
        registry: WorkspaceRegistry = WorkspaceRegistry(),
        runner: AutomationRunner = AutomationRunner(),
        exportService: DocumentExportService = DocumentExportService(),
        fileService: DocumentFileService = DocumentFileService()
    ) {
        self.name = name
        self.socketPath = socketPath
        self.registry = registry
        self.runner = runner
        self.exportService = exportService
        self.fileService = fileService
    }

    public func capabilities() -> [String] {
        [
            "describeDocument",
            "setDisplayUnit",
            "renameDocument",
            "upsertParameter",
            "deleteParameter",
            "setParameterExpression",
            "listParameters",
            "createComponentDefinition",
            "createComponentInstance",
            "setSceneNodeVisibility",
            "setSceneNodeLock",
            "setSceneNodeTransform",
            "setComponentInstanceVisibility",
            "setComponentInstanceLock",
            "setComponentInstanceTransform",
            "createSectionPlane",
            "createLineSketch",
            "createCircleSketch",
            "createRectangleSketch",
            "addSketchConstraint",
            "extrudeProfile",
            "createExtrudedRectangle",
            "createExtrudedRectangleFromCorners",
            "createExtrudedCircle",
            "evaluateDocument",
            "measureDocument",
            "meshSummary",
            "saveDocument",
            "exportDocument",
            "validateDocument",
        ]
    }

    @discardableResult
    public func register(
        session: EditorSession,
        path: URL? = nil,
        id: UUID = UUID()
    ) -> UUID {
        registry.register(session: session, path: path, id: id)
    }

    public func unregister(id: UUID) {
        registry.unregister(id: id)
    }

    public func handle(_ request: AgentRequest) -> AgentResponse {
        do {
            switch request {
            case .status:
                return .status(
                    AgentStatus(
                        running: true,
                        socketPath: socketPath,
                        sessionCount: registry.summaries().count
                    )
                )
            case .sessions:
                return .sessions(registry.summaries())
            case let .execute(sessionID, command, expectedGeneration):
                let session = try registry.session(id: sessionID)
                let result = try runner.executeBatch(
                    AutomationBatch(
                        commands: [command],
                        expectedGeneration: expectedGeneration
                    ),
                    in: session
                )
                guard let commandResult = result.first else {
                    throw EditorError(
                        code: .commandFailed,
                        message: "Agent command produced no result."
                    )
                }
                return .command(commandResult)
            case let .parameters(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .parameters(
                    ParameterListResult(
                        document: session.document,
                        generation: session.generation,
                        dirty: session.isDirty,
                        diagnostics: session.diagnostics
                    )
                )
            case let .setParameterExpression(sessionID, name, expression, kind, defaults, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let parsedExpression = try ParameterExpressionParser().parseForUpsert(
                    expression,
                    parameterName: name,
                    parameters: session.document.cadDocument.parameters,
                    targetKind: kind,
                    defaults: defaults
                )
                let result = try runner.execute(
                    .upsertParameter(
                        name: name,
                        expression: parsedExpression,
                        kind: kind
                    ),
                    in: session
                )
                return .command(result)
            case let .evaluate(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                let result = try runner.executeBatch(
                    AutomationBatch(
                        commands: [.validateDocument],
                        expectedGeneration: expectedGeneration
                    ),
                    in: session
                )
                guard result.first != nil else {
                    throw EditorError(
                        code: .commandFailed,
                        message: "Agent evaluation produced no result."
                    )
                }
                return .evaluation(session.evaluationSnapshot)
            case let .measure(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .measurement(
                    try MeasurementService().measure(
                        document: session.document,
                        selection: session.selection
                    )
                )
            case let .meshSummary(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                return .meshSummary(
                    try MeshSummaryService().summarize(
                        document: session.document,
                        objectRegistry: session.objectRegistry
                    )
                )
            case let .save(sessionID, expectedGeneration):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let url = try registry.documentURL(id: sessionID)
                try fileService.save(session.document, to: url)
                session.store.markClean()
                return .save(
                    SaveResult(
                        message: "Document saved to \(url.path).",
                        path: url.path,
                        generation: session.generation,
                        dirty: session.isDirty,
                        diagnostics: session.diagnostics
                    )
                )
            case let .export(sessionID, outputPath, expectedGeneration, options, dryRun):
                let session = try registry.session(id: sessionID)
                try session.store.requireGeneration(expectedGeneration)
                let result = try exportService.export(
                    document: session.document,
                    generation: session.generation,
                    to: URL(fileURLWithPath: outputPath),
                    options: options,
                    dryRun: dryRun,
                    objectRegistry: session.objectRegistry
                )
                return .export(result)
            }
        } catch let error as EditorError {
            return .failure(error)
        } catch {
            return .failure(
                EditorError(
                    code: .commandFailed,
                    message: error.localizedDescription
                )
            )
        }
    }

    public func send(_ request: AgentRequest) throws -> AgentResponse {
        handle(request)
    }
}
