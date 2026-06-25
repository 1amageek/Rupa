import Foundation
import RupaAgent
import RupaAutomation
import RupaCore

public enum CLIEditMode: String, Codable, Equatable, Sendable, CaseIterable {
    case auto
    case file
    case live
}

public struct CLIDocumentTarget: Equatable, Sendable {
    public var fileURL: URL?
    public var sessionID: UUID?

    public init(fileURL: URL? = nil, sessionID: UUID? = nil) {
        self.fileURL = fileURL
        self.sessionID = sessionID
    }
}

public struct CLIService {
    private let fileService: DocumentFileService
    private let exportService: DocumentExportService

    public init(
        fileService: DocumentFileService = DocumentFileService(),
        exportService: DocumentExportService = DocumentExportService()
    ) {
        self.fileService = fileService
        self.exportService = exportService
    }

    public func capabilities() -> [String] {
        AgentCommandController().capabilities()
    }

    public func agentStatus(
        client: AgentClientProtocol
    ) throws -> CLIAgentStatusResponse {
        switch try client.send(.status) {
        case .status(let status):
            return CLIAgentStatusResponse(status: status)
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Agent status request returned an unexpected response.")
        }
    }

    public func sessions(
        client: AgentClientProtocol
    ) throws -> CLISessionsResponse {
        switch try client.send(.sessions) {
        case .sessions(let sessions):
            return CLISessionsResponse(sessions: sessions)
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Sessions request returned an unexpected response.")
        }
    }

    public func attach(
        target: CLIDocumentTarget,
        client: AgentClientProtocol
    ) throws -> CLIAttachResponse {
        guard target.fileURL != nil || target.sessionID != nil else {
            throw invalidCommand("Attach requires a document file path or session ID.")
        }
        guard !(target.fileURL != nil && target.sessionID != nil) else {
            throw invalidCommand("Attach target must be selected by file path or session ID, not both.")
        }

        let openSessions = try sessions(client: client).sessions
        if let sessionID = target.sessionID {
            guard let session = openSessions.first(where: { $0.id == sessionID }) else {
                throw EditorError(
                    code: .sessionNotFound,
                    message: "No open Rupa session exists for \(sessionID.uuidString)."
                )
            }
            return CLIAttachResponse(session: session)
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Attach requires a document file path or session ID.")
        }
        let requestedPath = canonicalPath(url)
        let matches = openSessions.filter { session in
            guard let path = session.path else {
                return false
            }
            return canonicalPath(URL(fileURLWithPath: path)) == requestedPath
        }
        guard matches.count <= 1 else {
            throw invalidCommand("Multiple open Rupa sessions match \(url.path).")
        }
        guard let session = matches.first else {
            throw EditorError(
                code: .sessionNotFound,
                message: "No open Rupa session matches \(url.path)."
            )
        }
        return CLIAttachResponse(session: session)
    }

    public func renameFile(
        at url: URL,
        name: String,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        conflictClient: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        try rejectOpenDocumentConflict(
            fileURL: url,
            forceFileEdit: forceFileEdit,
            client: conflictClient
        )

        let session = EditorSession(document: try fileService.load(from: url))
        let result = try AutomationRunner().execute(.renameDocument(name: name), in: session)

        if !dryRun {
            try fileService.save(session.document, to: url)
            session.store.markClean()
        }

        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: session.isDirty,
            saved: !dryRun,
            diagnostics: result.diagnostics
        )
    }

    public func renameDocument(
        target: CLIDocumentTarget,
        name: String,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        switch mode {
        case .auto:
            return try renameDocumentAutomatically(
                target: target,
                name: name,
                expectedGeneration: expectedGeneration,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try renameFile(
                at: url,
                name: name,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                conflictClient: client
            )
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try renameLiveSession(
                sessionID: sessionID,
                name: name,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func setParameterFile(
        at url: URL,
        name: String,
        expression: CADExpression,
        kind: QuantityKind,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        conflictClient: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        try rejectOpenDocumentConflict(
            fileURL: url,
            forceFileEdit: forceFileEdit,
            client: conflictClient
        )

        let session = EditorSession(document: try fileService.load(from: url))
        let result = try AutomationRunner().execute(
            .upsertParameter(
                name: name,
                expression: expression,
                kind: kind
            ),
            in: session
        )

        if !dryRun {
            try fileService.save(session.document, to: url)
            session.store.markClean()
        }

        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: session.isDirty,
            saved: !dryRun,
            diagnostics: result.diagnostics
        )
    }

    public func setParameterExpressionFile(
        at url: URL,
        name: String,
        expression: String,
        kind: QuantityKind,
        defaults: ParameterExpressionDefaults = ParameterExpressionDefaults(),
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        conflictClient: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        try rejectOpenDocumentConflict(
            fileURL: url,
            forceFileEdit: forceFileEdit,
            client: conflictClient
        )

        let session = EditorSession(document: try fileService.load(from: url))
        let parsedExpression = try ParameterExpressionParser().parseForUpsert(
            expression,
            parameterName: name,
            parameters: session.document.cadDocument.parameters,
            targetKind: kind,
            defaults: defaults
        )
        let result = try AutomationRunner().execute(
            .upsertParameter(
                name: name,
                expression: parsedExpression,
                kind: kind
            ),
            in: session
        )

        if !dryRun {
            try fileService.save(session.document, to: url)
            session.store.markClean()
        }

        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: session.isDirty,
            saved: !dryRun,
            diagnostics: result.diagnostics
        )
    }

    public func deleteParameterFile(
        at url: URL,
        name: String,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        conflictClient: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        try rejectOpenDocumentConflict(
            fileURL: url,
            forceFileEdit: forceFileEdit,
            client: conflictClient
        )

        let session = EditorSession(document: try fileService.load(from: url))
        let result = try AutomationRunner().execute(
            .deleteParameter(name: name),
            in: session
        )

        if !dryRun {
            try fileService.save(session.document, to: url)
            session.store.markClean()
        }

        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: session.isDirty,
            saved: !dryRun,
            diagnostics: result.diagnostics
        )
    }

    public func setParameter(
        target: CLIDocumentTarget,
        name: String,
        expression: CADExpression,
        kind: QuantityKind,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        switch mode {
        case .auto:
            return try setParameterAutomatically(
                target: target,
                name: name,
                expression: expression,
                kind: kind,
                expectedGeneration: expectedGeneration,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try setParameterFile(
                at: url,
                name: name,
                expression: expression,
                kind: kind,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                conflictClient: client
            )
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try setParameterLiveSession(
                sessionID: sessionID,
                name: name,
                expression: expression,
                kind: kind,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func setParameterExpression(
        target: CLIDocumentTarget,
        name: String,
        expression: String,
        kind: QuantityKind,
        defaults: ParameterExpressionDefaults = ParameterExpressionDefaults(),
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        switch mode {
        case .auto:
            return try setParameterExpressionAutomatically(
                target: target,
                name: name,
                expression: expression,
                kind: kind,
                defaults: defaults,
                expectedGeneration: expectedGeneration,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try setParameterExpressionFile(
                at: url,
                name: name,
                expression: expression,
                kind: kind,
                defaults: defaults,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                conflictClient: client
            )
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try setParameterExpressionLiveSession(
                sessionID: sessionID,
                name: name,
                expression: expression,
                kind: kind,
                defaults: defaults,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func deleteParameter(
        target: CLIDocumentTarget,
        name: String,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        switch mode {
        case .auto:
            return try deleteParameterAutomatically(
                target: target,
                name: name,
                expectedGeneration: expectedGeneration,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try deleteParameterFile(
                at: url,
                name: name,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                conflictClient: client
            )
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try deleteParameterLiveSession(
                sessionID: sessionID,
                name: name,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func listParametersFile(
        at url: URL
    ) throws -> CLIParameterListResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        return CLIParameterListResponse(
            result: ParameterListResult(
                document: session.document,
                generation: session.generation,
                dirty: session.isDirty,
                diagnostics: session.diagnostics
            )
        )
    }

    public func listParameters(
        target: CLIDocumentTarget,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLIParameterListResponse {
        switch mode {
        case .auto:
            return try listParametersAutomatically(
                target: target,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try listParametersFile(at: url)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try listParametersLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func createExtrudedRectangleFile(
        at url: URL,
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        conflictClient: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        try rejectOpenDocumentConflict(
            fileURL: url,
            forceFileEdit: forceFileEdit,
            client: conflictClient
        )

        let session = EditorSession(document: try fileService.load(from: url))
        let result = try AutomationRunner().execute(
            .createExtrudedRectangle(
                name: name,
                plane: plane,
                width: width,
                height: height,
                depth: depth,
                direction: direction
            ),
            in: session
        )

        if !dryRun {
            try fileService.save(session.document, to: url)
            session.store.markClean()
        }

        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: session.isDirty,
            saved: !dryRun,
            diagnostics: result.diagnostics
        )
    }

    public func createExtrudedRectangle(
        target: CLIDocumentTarget,
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        switch mode {
        case .auto:
            return try createExtrudedRectangleAutomatically(
                target: target,
                name: name,
                plane: plane,
                width: width,
                height: height,
                depth: depth,
                direction: direction,
                expectedGeneration: expectedGeneration,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try createExtrudedRectangleFile(
                at: url,
                name: name,
                plane: plane,
                width: width,
                height: height,
                depth: depth,
                direction: direction,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                conflictClient: client
            )
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try createExtrudedRectangleLiveSession(
                sessionID: sessionID,
                name: name,
                plane: plane,
                width: width,
                height: height,
                depth: depth,
                direction: direction,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func createExtrudedRectangleFromCorners(
        target: CLIDocumentTarget,
        name: String,
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint,
        depth: CADExpression,
        direction: ExtrudeDirection,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        let command = AutomationCommand.createExtrudedRectangleFromCorners(
            name: name,
            plane: plane,
            firstCorner: firstCorner,
            oppositeCorner: oppositeCorner,
            depth: depth,
            direction: direction
        )
        return try executeModelingCommand(
            command,
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            client: client
        )
    }

    public func createExtrudedCircle(
        target: CLIDocumentTarget,
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        let command = AutomationCommand.createExtrudedCircle(
            name: name,
            plane: plane,
            center: center,
            radius: radius,
            depth: depth,
            direction: direction
        )
        return try executeModelingCommand(
            command,
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            client: client
        )
    }

    public func extrudeProfile(
        target: CLIDocumentTarget,
        name: String,
        profile: ProfileReference,
        distance: CADExpression,
        direction: ExtrudeDirection,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        let command = AutomationCommand.extrudeProfile(
            name: name,
            profile: profile,
            distance: distance,
            direction: direction
        )
        return try executeModelingCommand(
            command,
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            client: client
        )
    }

    public func createLineSketch(
        target: CLIDocumentTarget,
        name: String,
        plane: SketchPlane,
        start: SketchPoint,
        end: SketchPoint,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        let command = AutomationCommand.createLineSketch(
            name: name,
            plane: plane,
            start: start,
            end: end
        )
        return try executeSketchCommand(
            command,
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            client: client
        )
    }

    public func createCircleSketch(
        target: CLIDocumentTarget,
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        let command = AutomationCommand.createCircleSketch(
            name: name,
            plane: plane,
            center: center,
            radius: radius
        )
        return try executeSketchCommand(
            command,
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            client: client
        )
    }

    public func createRectangleSketch(
        target: CLIDocumentTarget,
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        let command = AutomationCommand.createRectangleSketch(
            name: name,
            plane: plane,
            width: width,
            height: height
        )
        return try executeSketchCommand(
            command,
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            client: client
        )
    }

    public func validateFile(
        at url: URL
    ) throws -> CLIResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        let result = try AutomationRunner().execute(.validateDocument, in: session)
        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: session.isDirty,
            saved: false,
            diagnostics: result.diagnostics
        )
    }

    public func evaluateFile(
        at url: URL
    ) throws -> CLIEvaluationResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        _ = try AutomationRunner().execute(.validateDocument, in: session)
        return CLIEvaluationResponse(
            snapshot: session.evaluationSnapshot,
            dirty: session.isDirty
        )
    }

    public func measureFile(
        at url: URL
    ) throws -> CLIMeasurementResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        return CLIMeasurementResponse(
            measurement: try MeasurementService().measure(document: session.document),
            generation: session.generation,
            dirty: session.isDirty
        )
    }

    public func meshSummaryFile(
        at url: URL
    ) throws -> CLIMeshSummaryResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        return CLIMeshSummaryResponse(
            meshSummary: try MeshSummaryService().summarize(
                document: session.document,
                objectRegistry: session.objectRegistry
            ),
            generation: session.generation,
            dirty: session.isDirty
        )
    }

    public func sketchEntitySummaryFile(
        at url: URL
    ) throws -> CLISketchEntitySummaryResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        return CLISketchEntitySummaryResponse(
            sketchEntitySummary: try SketchEntitySummaryService().summarize(
                document: session.document,
                objectRegistry: session.objectRegistry
            ),
            generation: session.generation,
            dirty: session.isDirty
        )
    }

    public func topologySummaryFile(
        at url: URL
    ) throws -> CLITopologySummaryResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        return CLITopologySummaryResponse(
            topologySummary: try TopologySummaryService().summarize(
                document: session.document,
                objectRegistry: session.objectRegistry,
                currentEvaluation: session.currentEvaluation,
                currentGeneration: session.generation
            ),
            generation: session.generation,
            dirty: session.isDirty
        )
    }

    public func curveAnalysisFile(
        at url: URL
    ) throws -> CLICurveAnalysisResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        return CLICurveAnalysisResponse(
            curveAnalysis: try CurveAnalysisService().analyze(
                document: session.document,
                objectRegistry: session.objectRegistry
            ),
            generation: session.generation,
            dirty: session.isDirty
        )
    }

    public func surfaceAnalysisFile(
        at url: URL,
        options: SurfaceAnalysisOptions = SurfaceAnalysisOptions()
    ) throws -> CLISurfaceAnalysisResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        return CLISurfaceAnalysisResponse(
            surfaceAnalysis: try SurfaceAnalysisService(options: options).analyze(
                document: session.document,
                objectRegistry: session.objectRegistry,
                currentEvaluation: session.currentEvaluation,
                currentGeneration: session.generation
            ),
            generation: session.generation,
            dirty: session.isDirty
        )
    }

    public func surfaceContinuitySummaryFile(
        at url: URL
    ) throws -> CLISurfaceContinuitySummaryResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        return CLISurfaceContinuitySummaryResponse(
            surfaceContinuitySummary: try SurfaceContinuityService().summarize(
                document: session.document,
                objectRegistry: session.objectRegistry,
                currentEvaluation: session.currentEvaluation,
                currentGeneration: session.generation
            ),
            generation: session.generation,
            dirty: session.isDirty
        )
    }

    public func surfaceSourceSummaryFile(
        at url: URL
    ) throws -> CLISurfaceSourceSummaryResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        return CLISurfaceSourceSummaryResponse(
            surfaceSourceSummary: try SurfaceSourceSummaryService().summarize(document: session.document),
            generation: session.generation,
            dirty: session.isDirty
        )
    }

    public func sketchDimensionSummaryFile(
        at url: URL,
        targets: [SelectionTarget]
    ) throws -> CLISketchDimensionSummaryResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        return CLISketchDimensionSummaryResponse(
            sketchDimensionSummary: try SketchDimensionSummaryService().summarize(
                document: session.document,
                targets: targets,
                objectRegistry: session.objectRegistry
            ),
            generation: session.generation,
            dirty: session.isDirty
        )
    }

    public func objectDimensionSummaryFile(
        at url: URL,
        targets: [SelectionTarget]
    ) throws -> CLIObjectDimensionSummaryResponse {
        let session = EditorSession(document: try fileService.load(from: url))
        return CLIObjectDimensionSummaryResponse(
            objectDimensionSummary: try ObjectDimensionSummaryService().summarize(
                document: session.document,
                targets: targets,
                objectRegistry: session.objectRegistry
            ),
            generation: session.generation,
            dirty: session.isDirty
        )
    }

    public func evaluateDocument(
        target: CLIDocumentTarget,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLIEvaluationResponse {
        switch mode {
        case .auto:
            return try evaluateDocumentAutomatically(
                target: target,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try evaluateFile(at: url)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try evaluateLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func measureDocument(
        target: CLIDocumentTarget,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLIMeasurementResponse {
        switch mode {
        case .auto:
            return try measureDocumentAutomatically(
                target: target,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try measureFile(at: url)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try measureLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func meshSummary(
        target: CLIDocumentTarget,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLIMeshSummaryResponse {
        switch mode {
        case .auto:
            return try meshSummaryAutomatically(
                target: target,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try meshSummaryFile(at: url)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try meshSummaryLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func sketchEntitySummary(
        target: CLIDocumentTarget,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLISketchEntitySummaryResponse {
        switch mode {
        case .auto:
            return try sketchEntitySummaryAutomatically(
                target: target,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try sketchEntitySummaryFile(at: url)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try sketchEntitySummaryLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func topologySummary(
        target: CLIDocumentTarget,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLITopologySummaryResponse {
        switch mode {
        case .auto:
            return try topologySummaryAutomatically(
                target: target,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try topologySummaryFile(at: url)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try topologySummaryLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func curveAnalysis(
        target: CLIDocumentTarget,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLICurveAnalysisResponse {
        switch mode {
        case .auto:
            return try curveAnalysisAutomatically(
                target: target,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try curveAnalysisFile(at: url)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try curveAnalysisLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func surfaceAnalysis(
        target: CLIDocumentTarget,
        options: SurfaceAnalysisOptions = SurfaceAnalysisOptions(),
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLISurfaceAnalysisResponse {
        switch mode {
        case .auto:
            return try surfaceAnalysisAutomatically(
                target: target,
                options: options,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try surfaceAnalysisFile(at: url, options: options)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try surfaceAnalysisLiveSession(
                sessionID: sessionID,
                options: options,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func surfaceContinuitySummary(
        target: CLIDocumentTarget,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLISurfaceContinuitySummaryResponse {
        switch mode {
        case .auto:
            return try surfaceContinuitySummaryAutomatically(
                target: target,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try surfaceContinuitySummaryFile(at: url)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try surfaceContinuitySummaryLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func surfaceSourceSummary(
        target: CLIDocumentTarget,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLISurfaceSourceSummaryResponse {
        switch mode {
        case .auto:
            return try surfaceSourceSummaryAutomatically(
                target: target,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try surfaceSourceSummaryFile(at: url)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try surfaceSourceSummaryLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func moveSurfaceControlPoint(
        target: CLIDocumentTarget,
        reference: SelectionReference,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        try executeModelingCommand(
            .moveSurfaceControlPoint(
                target: reference,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaZ: deltaZ
            ),
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            client: client
        )
    }

    public func slideSurfaceControlPoints(
        target: CLIDocumentTarget,
        references: [SelectionReference],
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: CADExpression,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        try executeModelingCommand(
            .slideSurfaceControlPoints(
                targets: references,
                direction: direction,
                distance: distance
            ),
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            client: client
        )
    }

    public func sketchDimensionSummary(
        target: CLIDocumentTarget,
        targets: [SelectionTarget],
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLISketchDimensionSummaryResponse {
        switch mode {
        case .auto:
            return try sketchDimensionSummaryAutomatically(
                target: target,
                targets: targets,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try sketchDimensionSummaryFile(at: url, targets: targets)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try sketchDimensionSummaryLiveSession(
                sessionID: sessionID,
                targets: targets,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func objectDimensionSummary(
        target: CLIDocumentTarget,
        targets: [SelectionTarget],
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol? = nil
    ) throws -> CLIObjectDimensionSummaryResponse {
        switch mode {
        case .auto:
            return try objectDimensionSummaryAutomatically(
                target: target,
                targets: targets,
                expectedGeneration: expectedGeneration,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try objectDimensionSummaryFile(at: url, targets: targets)
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try objectDimensionSummaryLiveSession(
                sessionID: sessionID,
                targets: targets,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func setSketchEntityDimension(
        target: CLIDocumentTarget,
        selectionTarget: SelectionTarget,
        kind: SketchEntityDimensionKind,
        value: CADExpression,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        try executeModelingCommand(
            .setSketchEntityDimension(
                target: selectionTarget,
                kind: kind,
                value: value
            ),
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            client: client
        )
    }

    public func setObjectDimension(
        target: CLIDocumentTarget,
        selectionTarget: SelectionTarget,
        kind: ObjectDimensionKind,
        value: CADExpression,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIResponse {
        try executeModelingCommand(
            .setObjectDimension(
                target: selectionTarget,
                kind: kind,
                value: value
            ),
            target: target,
            mode: mode,
            expectedGeneration: expectedGeneration,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            client: client
        )
    }

    public func saveFile(
        at url: URL,
        forceFileEdit: Bool = false,
        conflictClient: AgentClientProtocol? = nil
    ) throws -> CLISaveResponse {
        try rejectOpenDocumentConflict(
            fileURL: url,
            forceFileEdit: forceFileEdit,
            client: conflictClient
        )

        let session = EditorSession(document: try fileService.load(from: url))
        try fileService.save(session.document, to: url)
        session.store.markClean()
        return CLISaveResponse(
            result: SaveResult(
                message: "Document saved to \(url.path).",
                path: url.path,
                generation: session.generation,
                dirty: session.isDirty,
                diagnostics: session.diagnostics
            )
        )
    }

    public func saveDocument(
        target: CLIDocumentTarget,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLISaveResponse {
        switch mode {
        case .auto:
            return try saveDocumentAutomatically(
                target: target,
                expectedGeneration: expectedGeneration,
                forceFileEdit: forceFileEdit,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try saveFile(
                at: url,
                forceFileEdit: forceFileEdit,
                conflictClient: client
            )
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try saveLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    public func exportFile(
        at url: URL,
        to outputURL: URL,
        options: ExportOptions = ExportOptions(),
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        conflictClient: AgentClientProtocol? = nil
    ) throws -> CLIExportResponse {
        try rejectOpenDocumentConflict(
            fileURL: url,
            forceFileEdit: forceFileEdit,
            client: conflictClient
        )

        let session = EditorSession(document: try fileService.load(from: url))
        let result = try exportService.export(
            document: session.document,
            generation: session.generation,
            to: outputURL,
            options: options,
            dryRun: dryRun,
            objectRegistry: session.objectRegistry
        )
        return CLIExportResponse(
            result: result,
            dirty: session.isDirty
        )
    }

    public func exportDocument(
        target: CLIDocumentTarget,
        outputURL: URL,
        mode: CLIEditMode = .auto,
        expectedGeneration: DocumentGeneration? = nil,
        options: ExportOptions = ExportOptions(),
        dryRun: Bool = false,
        forceFileEdit: Bool = false,
        client: AgentClientProtocol? = nil
    ) throws -> CLIExportResponse {
        switch mode {
        case .auto:
            return try exportDocumentAutomatically(
                target: target,
                outputURL: outputURL,
                expectedGeneration: expectedGeneration,
                options: options,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try exportFile(
                at: url,
                to: outputURL,
                options: options,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                conflictClient: client
            )
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try exportLiveSession(
                sessionID: sessionID,
                outputURL: outputURL,
                expectedGeneration: expectedGeneration,
                options: options,
                dryRun: dryRun,
                client: requiredClient(client)
            )
        }
    }

    public func renameLiveSession(
        sessionID: UUID,
        name: String,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLIResponse {
        let response = try client.send(
            .execute(
                sessionID: sessionID,
                command: .renameDocument(name: name),
                expectedGeneration: expectedGeneration
            )
        )
        let result = try commandResult(from: response)
        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: result.didMutate,
            saved: false,
            diagnostics: result.diagnostics
        )
    }

    public func setParameterLiveSession(
        sessionID: UUID,
        name: String,
        expression: CADExpression,
        kind: QuantityKind,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLIResponse {
        let response = try client.send(
            .execute(
                sessionID: sessionID,
                command: .upsertParameter(
                    name: name,
                    expression: expression,
                    kind: kind
                ),
                expectedGeneration: expectedGeneration
            )
        )
        let result = try commandResult(from: response)
        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: result.didMutate,
            saved: false,
            diagnostics: result.diagnostics
        )
    }

    public func setParameterExpressionLiveSession(
        sessionID: UUID,
        name: String,
        expression: String,
        kind: QuantityKind,
        defaults: ParameterExpressionDefaults = ParameterExpressionDefaults(),
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLIResponse {
        let response = try client.send(
            .setParameterExpression(
                sessionID: sessionID,
                name: name,
                expression: expression,
                kind: kind,
                defaults: defaults,
                expectedGeneration: expectedGeneration
            )
        )
        let result = try commandResult(from: response)
        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: result.didMutate,
            saved: false,
            diagnostics: result.diagnostics
        )
    }

    public func deleteParameterLiveSession(
        sessionID: UUID,
        name: String,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLIResponse {
        let response = try client.send(
            .execute(
                sessionID: sessionID,
                command: .deleteParameter(name: name),
                expectedGeneration: expectedGeneration
            )
        )
        let result = try commandResult(from: response)
        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: result.didMutate,
            saved: false,
            diagnostics: result.diagnostics
        )
    }

    public func selectTargetsLiveSession(
        sessionID: UUID,
        targets: [SelectionTarget],
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLISelectionResponse {
        let response = try client.send(
            .selectTargets(
                sessionID: sessionID,
                targets: targets,
                expectedGeneration: expectedGeneration
            )
        )
        return CLISelectionResponse(result: try selectionResult(from: response))
    }

    public func selectReferencesLiveSession(
        sessionID: UUID,
        references: [SelectionReference],
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLISelectionResponse {
        let response = try client.send(
            .selectReferences(
                sessionID: sessionID,
                references: references,
                expectedGeneration: expectedGeneration
            )
        )
        return CLISelectionResponse(result: try selectionResult(from: response))
    }

    public func createExtrudedRectangleLiveSession(
        sessionID: UUID,
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLIResponse {
        let response = try client.send(
            .execute(
                sessionID: sessionID,
                command: .createExtrudedRectangle(
                    name: name,
                    plane: plane,
                    width: width,
                    height: height,
                    depth: depth,
                    direction: direction
                ),
                expectedGeneration: expectedGeneration
            )
        )
        let result = try commandResult(from: response)
        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: result.didMutate,
            saved: false,
            diagnostics: result.diagnostics
        )
    }

    public func evaluateLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLIEvaluationResponse {
        let response = try client.send(
            .evaluate(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .evaluation(let snapshot):
            let dirty = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }?
                .dirty ?? false
            return CLIEvaluationResponse(
                snapshot: snapshot,
                dirty: dirty
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Evaluation request returned an unexpected response.")
        }
    }

    public func measureLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLIMeasurementResponse {
        let response = try client.send(
            .measure(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .measurement(let measurement):
            let summary = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }
            return CLIMeasurementResponse(
                measurement: measurement,
                generation: DocumentGeneration(summary?.generation.value ?? 0),
                dirty: summary?.dirty ?? false
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Measurement request returned an unexpected response.")
        }
    }

    public func meshSummaryLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLIMeshSummaryResponse {
        let response = try client.send(
            .meshSummary(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .meshSummary(let meshSummary):
            let summary = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }
            return CLIMeshSummaryResponse(
                meshSummary: meshSummary,
                generation: DocumentGeneration(summary?.generation.value ?? 0),
                dirty: summary?.dirty ?? false
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Mesh summary request returned an unexpected response.")
        }
    }

    public func sketchEntitySummaryLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLISketchEntitySummaryResponse {
        let response = try client.send(
            .sketchEntitySummary(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .sketchEntitySummary(let sketchEntitySummary):
            let summary = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }
            return CLISketchEntitySummaryResponse(
                sketchEntitySummary: sketchEntitySummary,
                generation: DocumentGeneration(summary?.generation.value ?? 0),
                dirty: summary?.dirty ?? false
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Sketch entity summary request returned an unexpected response.")
        }
    }

    public func topologySummaryLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLITopologySummaryResponse {
        let response = try client.send(
            .topologySummary(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .topologySummary(let topologySummary):
            let summary = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }
            return CLITopologySummaryResponse(
                topologySummary: topologySummary,
                generation: DocumentGeneration(summary?.generation.value ?? 0),
                dirty: summary?.dirty ?? false
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Topology summary request returned an unexpected response.")
        }
    }

    public func curveAnalysisLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLICurveAnalysisResponse {
        let response = try client.send(
            .curveAnalysis(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .curveAnalysis(let curveAnalysis):
            let summary = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }
            return CLICurveAnalysisResponse(
                curveAnalysis: curveAnalysis,
                generation: DocumentGeneration(summary?.generation.value ?? 0),
                dirty: summary?.dirty ?? false
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Curve analysis request returned an unexpected response.")
        }
    }

    public func surfaceAnalysisLiveSession(
        sessionID: UUID,
        options: SurfaceAnalysisOptions = SurfaceAnalysisOptions(),
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLISurfaceAnalysisResponse {
        let response = try client.send(
            .surfaceAnalysis(
                sessionID: sessionID,
                options: options,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .surfaceAnalysis(let surfaceAnalysis):
            let summary = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }
            return CLISurfaceAnalysisResponse(
                surfaceAnalysis: surfaceAnalysis,
                generation: DocumentGeneration(summary?.generation.value ?? 0),
                dirty: summary?.dirty ?? false
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Surface analysis request returned an unexpected response.")
        }
    }

    public func surfaceContinuitySummaryLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLISurfaceContinuitySummaryResponse {
        let response = try client.send(
            .surfaceContinuitySummary(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .surfaceContinuitySummary(let surfaceContinuitySummary):
            let summary = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }
            return CLISurfaceContinuitySummaryResponse(
                surfaceContinuitySummary: surfaceContinuitySummary,
                generation: DocumentGeneration(summary?.generation.value ?? 0),
                dirty: summary?.dirty ?? false
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Surface continuity summary request returned an unexpected response.")
        }
    }

    public func surfaceSourceSummaryLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLISurfaceSourceSummaryResponse {
        let response = try client.send(
            .surfaceSourceSummary(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .surfaceSourceSummary(let surfaceSourceSummary):
            let summary = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }
            return CLISurfaceSourceSummaryResponse(
                surfaceSourceSummary: surfaceSourceSummary,
                generation: DocumentGeneration(summary?.generation.value ?? 0),
                dirty: summary?.dirty ?? false
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Surface source summary request returned an unexpected response.")
        }
    }

    public func sketchDimensionSummaryLiveSession(
        sessionID: UUID,
        targets: [SelectionTarget],
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLISketchDimensionSummaryResponse {
        let response = try client.send(
            .sketchDimensionSummary(
                sessionID: sessionID,
                targets: targets,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .sketchDimensionSummary(let sketchDimensionSummary):
            let summary = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }
            return CLISketchDimensionSummaryResponse(
                sketchDimensionSummary: sketchDimensionSummary,
                generation: DocumentGeneration(summary?.generation.value ?? 0),
                dirty: summary?.dirty ?? false
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Sketch dimension summary request returned an unexpected response.")
        }
    }

    public func objectDimensionSummaryLiveSession(
        sessionID: UUID,
        targets: [SelectionTarget],
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLIObjectDimensionSummaryResponse {
        let response = try client.send(
            .objectDimensionSummary(
                sessionID: sessionID,
                targets: targets,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .objectDimensionSummary(let objectDimensionSummary):
            let summary = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }
            return CLIObjectDimensionSummaryResponse(
                objectDimensionSummary: objectDimensionSummary,
                generation: DocumentGeneration(summary?.generation.value ?? 0),
                dirty: summary?.dirty ?? false
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Object dimension summary request returned an unexpected response.")
        }
    }

    public func listParametersLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLIParameterListResponse {
        let response = try client.send(
            .parameters(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .parameters(let result):
            return CLIParameterListResponse(result: result)
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Parameter list request returned an unexpected response.")
        }
    }

    public func saveLiveSession(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration? = nil,
        client: AgentClientProtocol
    ) throws -> CLISaveResponse {
        let response = try client.send(
            .save(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            )
        )
        switch response {
        case .save(let result):
            return CLISaveResponse(result: result)
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Save request returned an unexpected response.")
        }
    }

    public func exportLiveSession(
        sessionID: UUID,
        outputURL: URL,
        expectedGeneration: DocumentGeneration? = nil,
        options: ExportOptions = ExportOptions(),
        dryRun: Bool = false,
        client: AgentClientProtocol
    ) throws -> CLIExportResponse {
        let response = try client.send(
            .export(
                sessionID: sessionID,
                outputPath: outputURL.path,
                expectedGeneration: expectedGeneration,
                options: options,
                dryRun: dryRun
            )
        )
        switch response {
        case .export(let result):
            let dirty = try sessions(client: client)
                .sessions
                .first { $0.id == sessionID }?
                .dirty ?? false
            return CLIExportResponse(
                result: result,
                dirty: dirty
            )
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Export request returned an unexpected response.")
        }
    }

    private func evaluateDocumentAutomatically(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLIEvaluationResponse {
        if let sessionID = target.sessionID {
            return try evaluateLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try evaluateLiveSession(
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Evaluation requires a document file path or live session ID.")
        }
        return try evaluateFile(at: url)
    }

    private func measureDocumentAutomatically(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLIMeasurementResponse {
        if let sessionID = target.sessionID {
            return try measureLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try measureLiveSession(
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Measurement requires a document file path or live session ID.")
        }
        return try measureFile(at: url)
    }

    private func meshSummaryAutomatically(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLIMeshSummaryResponse {
        if let sessionID = target.sessionID {
            return try meshSummaryLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try meshSummaryLiveSession(
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Mesh summary requires a document file path or live session ID.")
        }
        return try meshSummaryFile(at: url)
    }

    private func sketchEntitySummaryAutomatically(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLISketchEntitySummaryResponse {
        if let sessionID = target.sessionID {
            return try sketchEntitySummaryLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try sketchEntitySummaryLiveSession(
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Sketch entity summary requires a document file path or live session ID.")
        }
        return try sketchEntitySummaryFile(at: url)
    }

    private func topologySummaryAutomatically(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLITopologySummaryResponse {
        if let sessionID = target.sessionID {
            return try topologySummaryLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try topologySummaryLiveSession(
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Topology summary requires a document file path or live session ID.")
        }
        return try topologySummaryFile(at: url)
    }

    private func curveAnalysisAutomatically(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLICurveAnalysisResponse {
        if let sessionID = target.sessionID {
            return try curveAnalysisLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try curveAnalysisLiveSession(
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Curve analysis requires a document file path or live session ID.")
        }
        return try curveAnalysisFile(at: url)
    }

    private func surfaceAnalysisAutomatically(
        target: CLIDocumentTarget,
        options: SurfaceAnalysisOptions,
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLISurfaceAnalysisResponse {
        if let sessionID = target.sessionID {
            return try surfaceAnalysisLiveSession(
                sessionID: sessionID,
                options: options,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try surfaceAnalysisLiveSession(
                sessionID: session.id,
                options: options,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Surface analysis requires a document file path or live session ID.")
        }
        return try surfaceAnalysisFile(at: url, options: options)
    }

    private func surfaceContinuitySummaryAutomatically(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLISurfaceContinuitySummaryResponse {
        if let sessionID = target.sessionID {
            return try surfaceContinuitySummaryLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try surfaceContinuitySummaryLiveSession(
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Surface continuity summary requires a document file path or live session ID.")
        }
        return try surfaceContinuitySummaryFile(at: url)
    }

    private func surfaceSourceSummaryAutomatically(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLISurfaceSourceSummaryResponse {
        if let sessionID = target.sessionID {
            return try surfaceSourceSummaryLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try surfaceSourceSummaryLiveSession(
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Surface source summary requires a document file path or live session ID.")
        }
        return try surfaceSourceSummaryFile(at: url)
    }

    private func sketchDimensionSummaryAutomatically(
        target: CLIDocumentTarget,
        targets: [SelectionTarget],
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLISketchDimensionSummaryResponse {
        if let sessionID = target.sessionID {
            return try sketchDimensionSummaryLiveSession(
                sessionID: sessionID,
                targets: targets,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try sketchDimensionSummaryLiveSession(
                sessionID: session.id,
                targets: targets,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Sketch dimension summary requires a document file path or live session ID.")
        }
        return try sketchDimensionSummaryFile(at: url, targets: targets)
    }

    private func objectDimensionSummaryAutomatically(
        target: CLIDocumentTarget,
        targets: [SelectionTarget],
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLIObjectDimensionSummaryResponse {
        if let sessionID = target.sessionID {
            return try objectDimensionSummaryLiveSession(
                sessionID: sessionID,
                targets: targets,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try objectDimensionSummaryLiveSession(
                sessionID: session.id,
                targets: targets,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Object dimension summary requires a document file path or live session ID.")
        }
        return try objectDimensionSummaryFile(at: url, targets: targets)
    }

    private func saveDocumentAutomatically(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> CLISaveResponse {
        if let sessionID = target.sessionID {
            return try saveLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           !forceFileEdit,
           let client,
           let session = try openSession(for: url, client: client) {
            return try saveLiveSession(
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Save requires a document file path or live session ID.")
        }
        return try saveFile(
            at: url,
            forceFileEdit: forceFileEdit,
            conflictClient: client
        )
    }

    private func renameDocumentAutomatically(
        target: CLIDocumentTarget,
        name: String,
        expectedGeneration: DocumentGeneration?,
        dryRun: Bool,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> CLIResponse {
        if let sessionID = target.sessionID {
            return try renameLiveSession(
                sessionID: sessionID,
                name: name,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           !forceFileEdit,
           let client,
           let session = try openSession(for: url, client: client) {
            guard !dryRun else {
                throw invalidCommand("Dry-run is not supported for live document mutation.")
            }
            return try renameLiveSession(
                sessionID: session.id,
                name: name,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Rename requires a document file path or live session ID.")
        }
        return try renameFile(
            at: url,
            name: name,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            conflictClient: client
        )
    }

    private func setParameterAutomatically(
        target: CLIDocumentTarget,
        name: String,
        expression: CADExpression,
        kind: QuantityKind,
        expectedGeneration: DocumentGeneration?,
        dryRun: Bool,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> CLIResponse {
        if let sessionID = target.sessionID {
            return try setParameterLiveSession(
                sessionID: sessionID,
                name: name,
                expression: expression,
                kind: kind,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           !forceFileEdit,
           let client,
           let session = try openSession(for: url, client: client) {
            guard !dryRun else {
                throw invalidCommand("Dry-run is not supported for live document mutation.")
            }
            return try setParameterLiveSession(
                sessionID: session.id,
                name: name,
                expression: expression,
                kind: kind,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Parameter set requires a document file path or live session ID.")
        }
        return try setParameterFile(
            at: url,
            name: name,
            expression: expression,
            kind: kind,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            conflictClient: client
        )
    }

    private func setParameterExpressionAutomatically(
        target: CLIDocumentTarget,
        name: String,
        expression: String,
        kind: QuantityKind,
        defaults: ParameterExpressionDefaults,
        expectedGeneration: DocumentGeneration?,
        dryRun: Bool,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> CLIResponse {
        if let sessionID = target.sessionID {
            return try setParameterExpressionLiveSession(
                sessionID: sessionID,
                name: name,
                expression: expression,
                kind: kind,
                defaults: defaults,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           !forceFileEdit,
           let client,
           let session = try openSession(for: url, client: client) {
            guard !dryRun else {
                throw invalidCommand("Dry-run is not supported for live document mutation.")
            }
            return try setParameterExpressionLiveSession(
                sessionID: session.id,
                name: name,
                expression: expression,
                kind: kind,
                defaults: defaults,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Parameter set requires a document file path or live session ID.")
        }
        return try setParameterExpressionFile(
            at: url,
            name: name,
            expression: expression,
            kind: kind,
            defaults: defaults,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            conflictClient: client
        )
    }

    private func deleteParameterAutomatically(
        target: CLIDocumentTarget,
        name: String,
        expectedGeneration: DocumentGeneration?,
        dryRun: Bool,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> CLIResponse {
        if let sessionID = target.sessionID {
            return try deleteParameterLiveSession(
                sessionID: sessionID,
                name: name,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           !forceFileEdit,
           let client,
           let session = try openSession(for: url, client: client) {
            guard !dryRun else {
                throw invalidCommand("Dry-run is not supported for live document mutation.")
            }
            return try deleteParameterLiveSession(
                sessionID: session.id,
                name: name,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Parameter delete requires a document file path or live session ID.")
        }
        return try deleteParameterFile(
            at: url,
            name: name,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            conflictClient: client
        )
    }

    private func listParametersAutomatically(
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol?
    ) throws -> CLIParameterListResponse {
        if let sessionID = target.sessionID {
            return try listParametersLiveSession(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           let client,
           let session = try openSession(for: url, client: client) {
            return try listParametersLiveSession(
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Parameter listing requires a document file path or live session ID.")
        }
        return try listParametersFile(at: url)
    }

    private func createExtrudedRectangleAutomatically(
        target: CLIDocumentTarget,
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection,
        expectedGeneration: DocumentGeneration?,
        dryRun: Bool,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> CLIResponse {
        if let sessionID = target.sessionID {
            return try createExtrudedRectangleLiveSession(
                sessionID: sessionID,
                name: name,
                plane: plane,
                width: width,
                height: height,
                depth: depth,
                direction: direction,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           !forceFileEdit,
           let client,
           let session = try openSession(for: url, client: client) {
            guard !dryRun else {
                throw invalidCommand("Dry-run is not supported for live document mutation.")
            }
            return try createExtrudedRectangleLiveSession(
                sessionID: session.id,
                name: name,
                plane: plane,
                width: width,
                height: height,
                depth: depth,
                direction: direction,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Modeling requires a document file path or live session ID.")
        }
        return try createExtrudedRectangleFile(
            at: url,
            name: name,
            plane: plane,
            width: width,
            height: height,
            depth: depth,
            direction: direction,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            conflictClient: client
        )
    }

    private func executeModelingCommand(
        _ command: AutomationCommand,
        target: CLIDocumentTarget,
        mode: CLIEditMode,
        expectedGeneration: DocumentGeneration?,
        dryRun: Bool,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> CLIResponse {
        switch mode {
        case .auto:
            return try executeModelingCommandAutomatically(
                command,
                target: target,
                expectedGeneration: expectedGeneration,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try executeModelingCommandFile(
                command,
                at: url,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                conflictClient: client
            )
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try executeModelingCommandLiveSession(
                command,
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    private func executeModelingCommandAutomatically(
        _ command: AutomationCommand,
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        dryRun: Bool,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> CLIResponse {
        if let sessionID = target.sessionID {
            return try executeModelingCommandLiveSession(
                command,
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           !forceFileEdit,
           let client,
           let session = try openSession(for: url, client: client) {
            guard !dryRun else {
                throw invalidCommand("Dry-run is not supported for live document mutation.")
            }
            return try executeModelingCommandLiveSession(
                command,
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Modeling requires a document file path or live session ID.")
        }
        return try executeModelingCommandFile(
            command,
            at: url,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            conflictClient: client
        )
    }

    private func executeSketchCommand(
        _ command: AutomationCommand,
        target: CLIDocumentTarget,
        mode: CLIEditMode,
        expectedGeneration: DocumentGeneration?,
        dryRun: Bool,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> CLIResponse {
        switch mode {
        case .auto:
            return try executeSketchCommandAutomatically(
                command,
                target: target,
                expectedGeneration: expectedGeneration,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: client
            )
        case .file:
            guard let url = target.fileURL else {
                throw invalidCommand("File mode requires a document file path.")
            }
            return try executeModelingCommandFile(
                command,
                at: url,
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                conflictClient: client
            )
        case .live:
            let sessionID = try resolvedLiveSessionID(
                target: target,
                client: client
            )
            return try executeModelingCommandLiveSession(
                command,
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }
    }

    private func executeSketchCommandAutomatically(
        _ command: AutomationCommand,
        target: CLIDocumentTarget,
        expectedGeneration: DocumentGeneration?,
        dryRun: Bool,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> CLIResponse {
        if let sessionID = target.sessionID {
            return try executeModelingCommandLiveSession(
                command,
                sessionID: sessionID,
                expectedGeneration: expectedGeneration,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           !forceFileEdit,
           let client,
           let session = try openSession(for: url, client: client) {
            guard !dryRun else {
                throw invalidCommand("Dry-run is not supported for live document mutation.")
            }
            return try executeModelingCommandLiveSession(
                command,
                sessionID: session.id,
                expectedGeneration: expectedGeneration,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Sketch creation requires a document file path or live session ID.")
        }
        return try executeModelingCommandFile(
            command,
            at: url,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            conflictClient: client
        )
    }

    private func executeModelingCommandFile(
        _ command: AutomationCommand,
        at url: URL,
        dryRun: Bool,
        forceFileEdit: Bool,
        conflictClient: AgentClientProtocol?
    ) throws -> CLIResponse {
        try rejectOpenDocumentConflict(
            fileURL: url,
            forceFileEdit: forceFileEdit,
            client: conflictClient
        )

        let session = EditorSession(document: try fileService.load(from: url))
        let result = try AutomationRunner().execute(command, in: session)

        if !dryRun {
            try fileService.save(session.document, to: url)
            session.store.markClean()
        }

        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: session.isDirty,
            saved: !dryRun,
            diagnostics: result.diagnostics
        )
    }

    private func executeModelingCommandLiveSession(
        _ command: AutomationCommand,
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?,
        client: AgentClientProtocol
    ) throws -> CLIResponse {
        let response = try client.send(
            .execute(
                sessionID: sessionID,
                command: command,
                expectedGeneration: expectedGeneration
            )
        )
        let result = try commandResult(from: response)
        return CLIResponse(
            message: result.message,
            generation: result.generation.value,
            dirty: result.didMutate,
            saved: false,
            diagnostics: result.diagnostics
        )
    }

    private func exportDocumentAutomatically(
        target: CLIDocumentTarget,
        outputURL: URL,
        expectedGeneration: DocumentGeneration?,
        options: ExportOptions,
        dryRun: Bool,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws -> CLIExportResponse {
        if let sessionID = target.sessionID {
            return try exportLiveSession(
                sessionID: sessionID,
                outputURL: outputURL,
                expectedGeneration: expectedGeneration,
                options: options,
                dryRun: dryRun,
                client: requiredClient(client)
            )
        }

        if let url = target.fileURL,
           !forceFileEdit,
           let client,
           let session = try openSession(for: url, client: client) {
            return try exportLiveSession(
                sessionID: session.id,
                outputURL: outputURL,
                expectedGeneration: expectedGeneration,
                options: options,
                dryRun: dryRun,
                client: client
            )
        }

        guard let url = target.fileURL else {
            throw invalidCommand("Export requires a document file path or live session ID.")
        }
        return try exportFile(
            at: url,
            to: outputURL,
            options: options,
            dryRun: dryRun,
            forceFileEdit: forceFileEdit,
            conflictClient: client
        )
    }

    private func rejectOpenDocumentConflict(
        fileURL: URL,
        forceFileEdit: Bool,
        client: AgentClientProtocol?
    ) throws {
        guard !forceFileEdit, let client else {
            return
        }
        let openSessions = try sessions(client: client).sessions
        let requestedPath = canonicalPath(fileURL)
        let matchingSession = openSessions.first { session in
            guard let path = session.path else {
                return false
            }
            return canonicalPath(URL(fileURLWithPath: path)) == requestedPath
        }

        guard matchingSession == nil else {
            throw EditorError(
                code: .documentOpenInApp,
                message: "Document is open in Rupa. Use live mode or explicitly force a file edit."
            )
        }
    }

    private func commandResult(from response: AgentResponse) throws -> AutomationResult {
        switch response {
        case .command(let result):
            return result
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Command request returned an unexpected response.")
        }
    }

    private func selectionResult(from response: AgentResponse) throws -> SelectionStateResult {
        switch response {
        case .selection(let result):
            return result
        case .failure(let error):
            throw error
        default:
            throw unexpectedResponse("Selection request returned an unexpected response.")
        }
    }

    private func unexpectedResponse(_ message: String) -> EditorError {
        EditorError(
            code: .commandFailed,
            message: message
        )
    }

    private func invalidCommand(_ message: String) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: message
        )
    }

    private func requiredClient(
        _ client: AgentClientProtocol?
    ) throws -> AgentClientProtocol {
        guard let client else {
            throw invalidCommand("Live mode requires a Rupa agent connection.")
        }
        return client
    }

    private func resolvedLiveSessionID(
        target: CLIDocumentTarget,
        client: AgentClientProtocol?
    ) throws -> UUID {
        if let sessionID = target.sessionID {
            return sessionID
        }
        guard let url = target.fileURL else {
            throw invalidCommand("Live mode requires a document file path or live session ID.")
        }
        guard let session = try openSession(
            for: url,
            client: requiredClient(client)
        ) else {
            throw EditorError(
                code: .sessionNotFound,
                message: "No open Rupa session matches \(url.path)."
            )
        }
        return session.id
    }

    private func openSession(
        for fileURL: URL,
        client: AgentClientProtocol
    ) throws -> WorkspaceSessionSummary? {
        let requestedPath = canonicalPath(fileURL)
        return try sessions(client: client)
            .sessions
            .first { session in
                guard let path = session.path else {
                    return false
                }
                return canonicalPath(URL(fileURLWithPath: path)) == requestedPath
            }
    }

    private func canonicalPath(_ url: URL) -> String {
        url
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}
