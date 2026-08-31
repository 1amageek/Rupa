import ArgumentParser
import Foundation
import RupaAgentProtocol
import RupaAutomation
import RupaCore

public struct CLICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rupa",
        abstract: "Run Rupa command line tools.",
        subcommands: [
            AgentCommand.self,
            AttachDocument.self,
            BatchCommand.self,
            Capabilities.self,
            AutomationCommandGroup.self,
            DimensionCommand.self,
            EvaluateDocument.self,
            ExportDocument.self,
            FeatureCommand.self,
            InspectCommand.self,
            MeasureDocument.self,
            MeshDocument.self,
            ModelCommand.self,
            ParameterCommand.self,
            PlaneCommand.self,
            RenameDocument.self,
            SaveDocument.self,
            SelectionCommand.self,
            SketchCommand.self,
            Sessions.self,
            SurfaceCommand.self,
            ValidateDocument.self,
            ViewCommand.self,
        ],
        defaultSubcommand: Capabilities.self
    )

    public init() {}
}

public struct Capabilities: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "capabilities",
        abstract: "Print supported command capabilities."
    )

    public init() {}

    public func run() async throws {
        try await CLIExitCode.run {
            let capabilities = try await CLIService().capabilities()
            print(capabilities.joined(separator: "\n"))
        }
    }
}

extension ExportPreset.DestinationPolicy: ExpressibleByArgument {}
extension LengthDisplayUnit: ExpressibleByArgument {}
extension SurfaceBoundaryContinuityLevel: ExpressibleByArgument {}
extension SurfaceBoundaryMatchSide: ExpressibleByArgument {}
extension SurfaceBoundaryReferenceDirection: ExpressibleByArgument {}
extension SurfaceTrimEndpoint: ExpressibleByArgument {}

public enum CLIParameterKind: String, CaseIterable, ExpressibleByArgument, Sendable {
    case length
    case angle
    case scalar

    public var quantityKind: QuantityKind {
        switch self {
        case .length:
            .length
        case .angle:
            .angle
        case .scalar:
            .scalar
        }
    }
}

public enum CLISketchPlane: String, CaseIterable, ExpressibleByArgument, Sendable {
    case xy
    case yz
    case zx

    public var sketchPlane: SketchPlane {
        switch self {
        case .xy:
            .xy
        case .yz:
            .yz
        case .zx:
            .zx
        }
    }
}

public enum CLIExtrudeDirection: String, CaseIterable, ExpressibleByArgument, Sendable {
    case normal
    case symmetric

    public var extrudeDirection: ExtrudeDirection {
        switch self {
        case .normal:
            .normal
        case .symmetric:
            .symmetric
        }
    }
}

public enum CLISurfaceSlideDirection: String, CaseIterable, ExpressibleByArgument, Sendable {
    case positiveU
    case negativeU
    case normal
    case positiveV
    case negativeV

    public var slideDirection: PolySplineSurfaceVertexSlideDirection {
        switch self {
        case .positiveU:
            .positiveU
        case .negativeU:
            .negativeU
        case .normal:
            .normal
        case .positiveV:
            .positiveV
        case .negativeV:
            .negativeV
        }
    }
}

extension SketchEntityDimensionKind: ExpressibleByArgument {}
extension ObjectDimensionKind: ExpressibleByArgument {}

public struct AgentCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "agent",
        abstract: "Inspect or control the running Rupa agent.",
        subcommands: [
            AgentStatusCommand.self,
        ],
        defaultSubcommand: AgentStatusCommand.self
    )

    public init() {}
}

public struct AgentStatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Print Rupa agent status."
    )

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() async throws {
        try await CLIExitCode.run {
            let response = try await CLIService().agentStatus()
            try CLIOutput.write(response: response, asJSON: json)
        }
    }
}

public struct AttachDocument: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Resolve an open Rupa document session."
    )

    @Argument(help: "Path to the open .rupa project.")
    public var file: String?

    @Option(help: "Open document session UUID.")
    public var session: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() async throws {
        let id = try parsedSessionID(session)

        try await CLIExitCode.run {
            let response = try await CLIService().attach(
                target: CLIDocumentTarget(
                    fileURL: file.map(URL.init(fileURLWithPath:)),
                    sessionID: id
                )
            )
            try CLIOutput.write(response: response, asJSON: json)
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let uuid = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a valid UUID.")
        }
        return uuid
    }
}

public struct ModelCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "model",
        abstract: "Create generic CAD model features.",
        subcommands: [
            BoxModelCommand.self,
            BoxCornersModelCommand.self,
            CylinderModelCommand.self,
            ExtrudeModelCommand.self,
            RevolveModelCommand.self,
            SweepModelCommand.self,
            LoftModelCommand.self,
            ModelFaceOffsetCommand.self,
            ModelEdgeChamferCommand.self,
            ModelEdgeFilletCommand.self,
            ModelVertexMoveCommand.self,
        ],
        defaultSubcommand: BoxModelCommand.self
    )

    public init() {}
}

public struct SketchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sketch",
        abstract: "Create generic CAD sketch features.",
        subcommands: [
            LineSketchCommand.self,
            CircleSketchCommand.self,
            ArcSketchCommand.self,
            SplineSketchCommand.self,
            RectangleSketchCommand.self,
            PolygonSketchCommand.self,
            SketchReverseCommand.self,
            SketchSplitCommand.self,
            SketchTrimCommand.self,
            SketchExtendCommand.self,
            SketchJoinCommand.self,
            SketchUnjoinCommand.self,
            SketchSlotCommand.self,
            SketchOffsetCommand.self,
            SketchOffsetRegionsCommand.self,
            SketchCornerTreatmentCommand.self,
            SketchConstraintAddCommand.self,
            SketchConstraintRemoveCommand.self,
            SketchConvertLineToArcCommand.self,
            SketchConvertLineToSplineCommand.self,
            SketchInsertControlPointCommand.self,
            SketchRebuildCommand.self,
            SketchCutCommand.self,
            SketchBridgeCommand.self,
            SketchBridgeUpdateCommand.self,
            SketchCurvatureDisplayCommand.self,
            SketchPointDisplayCommand.self,
        ],
        defaultSubcommand: LineSketchCommand.self
    )

    public init() {}
}

public struct SelectionCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "selection",
        abstract: "Select live-session object, subobject, or Swift-CAD reference targets.",
        subcommands: [
            SelectionReferencesCommand.self,
            SelectionTargetsCommand.self,
        ],
        defaultSubcommand: SelectionReferencesCommand.self
    )

    public init() {}
}

public struct SelectionReferencesCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "references",
        abstract: "Replace live-session selection with Swift-CAD SelectionReference values."
    )

    @Option(help: "Open document session UUID.")
    public var sessionID: String

    @Option(
        name: .customLong("reference"),
        help: "SelectionReference JSON object. Repeat to select multiple references."
    )
    public var referencePayloads: [String] = []

    @Option(help: "JSON file containing one SelectionReference object or an array of SelectionReference objects.")
    public var referencesFile: String?

    @Flag(help: "Clear selected references.")
    public var clear: Bool = false

    @Option(help: "Expected document generation.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() async throws {
        let id = try CLISelectionInputParser.sessionID(sessionID)
        let references = try decodedReferences()

        try await CLIExitCode.run {
            let response = try await CLIService().send(
                target: CLIDocumentTarget(sessionID: id)
            ) { sessionID in
                .selectReferences(
                    sessionID: sessionID,
                    references: references,
                    expectedGeneration: expectedGeneration.map(DocumentGeneration.init)
                )
            }
            try CLIOutput.write(
                response: try CLIResponseProjector.selection(response),
                asJSON: json
            )
        }
    }

    private func decodedReferences() throws -> [SelectionReference] {
        try CLISelectionInputParser.decodeSelectionInput(
            inlinePayloads: referencePayloads,
            filePath: referencesFile,
            clear: clear,
            valueName: "SelectionReference",
            arrayName: "SelectionReference"
        )
    }
}

public struct SelectionTargetsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "targets",
        abstract: "Replace live-session selection with rendered object or subobject SelectionTarget values."
    )

    @Option(help: "Open document session UUID.")
    public var sessionID: String

    @Option(
        name: .customLong("target"),
        help: "SelectionTarget JSON object. Repeat to select multiple targets."
    )
    public var targetPayloads: [String] = []

    @Option(help: "JSON file containing one SelectionTarget object or an array of SelectionTarget objects.")
    public var targetsFile: String?

    @Flag(help: "Clear selected targets.")
    public var clear: Bool = false

    @Option(help: "Expected document generation.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() async throws {
        let id = try CLISelectionInputParser.sessionID(sessionID)
        let targets = try decodedTargets()

        try await CLIExitCode.run {
            let response = try await CLIService().send(
                target: CLIDocumentTarget(sessionID: id)
            ) { sessionID in
                .selectTargets(
                    sessionID: sessionID,
                    targets: targets,
                    expectedGeneration: expectedGeneration.map(DocumentGeneration.init)
                )
            }
            try CLIOutput.write(
                response: try CLIResponseProjector.selection(response),
                asJSON: json
            )
        }
    }

    private func decodedTargets() throws -> [SelectionTarget] {
        try CLISelectionInputParser.decodeSelectionInput(
            inlinePayloads: targetPayloads,
            filePath: targetsFile,
            clear: clear,
            valueName: "SelectionTarget",
            arrayName: "SelectionTarget"
        )
    }
}

enum CLISelectionInputParser {
    static func sessionID(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    static func optionalSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        return try sessionID(value)
    }

    static func decodeSingleSelectionInput<Value: Decodable>(
        inlinePayload: String?,
        filePath: String?,
        valueName: String
    ) throws -> Value {
        guard (inlinePayload != nil) != (filePath != nil) else {
            throw ValidationError("Provide exactly one \(valueName) JSON input.")
        }
        let values: [Value]
        if let inlinePayload {
            values = try decodeSelectionInput(
                inlinePayloads: [inlinePayload],
                filePath: nil,
                clear: false,
                valueName: valueName,
                arrayName: valueName
            )
        } else {
            values = try decodeSelectionInput(
                inlinePayloads: [],
                filePath: filePath,
                clear: false,
                valueName: valueName,
                arrayName: valueName
            )
        }
        guard values.count == 1, let value = values.first else {
            throw ValidationError("\(valueName) JSON input must contain exactly one value.")
        }
        return value
    }

    static func decodeOptionalSelectionInput<Value: Decodable>(
        inlinePayloads: [String],
        filePath: String?,
        valueName: String,
        arrayName: String
    ) throws -> [Value] {
        guard !inlinePayloads.isEmpty || filePath != nil else {
            return []
        }
        return try decodeSelectionInput(
            inlinePayloads: inlinePayloads,
            filePath: filePath,
            clear: false,
            valueName: valueName,
            arrayName: arrayName
        )
    }

    static func decodeSelectionInput<Value: Decodable>(
        inlinePayloads: [String],
        filePath: String?,
        clear: Bool,
        valueName: String,
        arrayName: String
    ) throws -> [Value] {
        let hasPayloadInput = !inlinePayloads.isEmpty || filePath != nil
        guard clear == false || hasPayloadInput == false else {
            throw ValidationError("Use --clear without JSON selection input.")
        }
        guard clear || hasPayloadInput else {
            throw ValidationError("Provide JSON selection input or --clear.")
        }
        guard clear == false else {
            return []
        }

        var values: [Value] = []
        let decoder = JSONDecoder()
        for payload in inlinePayloads {
            let data = Data(payload.utf8)
            do {
                values.append(try decoder.decode(Value.self, from: data))
            } catch {
                throw ValidationError("\(valueName) JSON is invalid: \(error.localizedDescription)")
            }
        }
        if let filePath {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            values.append(contentsOf: try decodeFilePayload(
                data,
                decoder: decoder,
                valueName: valueName,
                arrayName: arrayName
            ))
        }
        return values
    }

    private static func decodeFilePayload<Value: Decodable>(
        _ data: Data,
        decoder: JSONDecoder,
        valueName: String,
        arrayName: String
    ) throws -> [Value] {
        do {
            return try decoder.decode([Value].self, from: data)
        } catch let arrayError {
            do {
                return [try decoder.decode(Value.self, from: data)]
            } catch {
                throw ValidationError(
                    "\(arrayName) file must contain one \(valueName) object or an array. \(arrayError.localizedDescription)"
                )
            }
        }
    }
}

public struct DimensionCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "dimension",
        abstract: "Discover and edit supported sketch and object dimensions.",
        subcommands: [
            DimensionSketchSummaryCommand.self,
            DimensionObjectSummaryCommand.self,
            DimensionAddSelectionCommand.self,
            DimensionSetSelectionCommand.self,
            DimensionApplySelectionCommand.self,
            DimensionRemoveSelectionCommand.self,
            DimensionSetSketchCommand.self,
            DimensionSetObjectCommand.self,
        ],
        defaultSubcommand: DimensionObjectSummaryCommand.self
    )

    public init() {}
}

public struct DimensionSketchSummaryCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sketch-summary",
        abstract: "Return editable sketch dimension candidates for SelectionTarget values."
    )

    @OptionGroup
    public var document: CLIReadDocumentOptions

    @Option(
        name: .customLong("target"),
        help: "SelectionTarget JSON object. Repeat for multiple targets. Live mode may omit this to use current selection."
    )
    public var targetPayloads: [String] = []

    @Option(help: "JSON file containing one SelectionTarget object or an array.")
    public var targetsFile: String?

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()
        let targets: [SelectionTarget] = try CLISelectionInputParser.decodeOptionalSelectionInput(
            inlinePayloads: targetPayloads,
            filePath: targetsFile,
            valueName: "SelectionTarget",
            arrayName: "SelectionTarget"
        )

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: document.target(sessionID: id),
                expectedGeneration: document.generation()
            ) { sessionID in
                .sketchDimensionSummary(
                    sessionID: sessionID,
                    targets: targets,
                    expectedGeneration: document.generation()
                )
            }
            try CLIOutput.write(
                response: try CLIResponseProjector.sketchDimensionSummary(envelope),
                asJSON: document.json
            )
        }
    }
}

public struct DimensionObjectSummaryCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "object-summary",
        abstract: "Return editable object dimension candidates for SelectionTarget values."
    )

    @OptionGroup
    public var document: CLIReadDocumentOptions

    @Option(
        name: .customLong("target"),
        help: "SelectionTarget JSON object. Repeat for multiple targets. Live mode may omit this to use current selection."
    )
    public var targetPayloads: [String] = []

    @Option(help: "JSON file containing one SelectionTarget object or an array.")
    public var targetsFile: String?

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()
        let targets: [SelectionTarget] = try CLISelectionInputParser.decodeOptionalSelectionInput(
            inlinePayloads: targetPayloads,
            filePath: targetsFile,
            valueName: "SelectionTarget",
            arrayName: "SelectionTarget"
        )

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: document.target(sessionID: id),
                expectedGeneration: document.generation()
            ) { sessionID in
                .objectDimensionSummary(
                    sessionID: sessionID,
                    targets: targets,
                    expectedGeneration: document.generation()
                )
            }
            try CLIOutput.write(
                response: try CLIResponseProjector.objectDimensionSummary(envelope),
                asJSON: document.json
            )
        }
    }
}

public struct DimensionSetSketchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-sketch",
        abstract: "Set a supported sketch dimension on one SelectionTarget."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionTarget JSON object.")
    public var target: String?

    @Option(help: "JSON file containing one SelectionTarget object.")
    public var targetFile: String?

    @Option(help: "Sketch dimension kind: length, radius, diameter, or angle.")
    public var kind: SketchEntityDimensionKind

    @Option(parsing: .unconditional, help: "Dimension value numeric literal.")
    public var value: Double

    @Option(help: "Unit for the value. Length dimensions default to the workspace display unit; angle dimensions default to degree.")
    public var unit: String?

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()
        let selectionTarget: SelectionTarget = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: target,
            filePath: targetFile,
            valueName: "SelectionTarget"
        )

        try await CLIExitCode.run {
            let expression = try await CLIDimensionExpressionParser.expression(
                value: value,
                unitName: unit,
                sketchKind: kind,
                document: document,
                sessionID: id
            )
            let response = try await CLIService().applyAutomationCommand(
                target: document.target(sessionID: id),
                command: .setSketchEntityDimension(
                    target: selectionTarget,
                    kind: kind,
                    value: expression
                ),
                expectedGeneration: document.generation(),
                expectedWorkspaceRevision: document.workspaceRevision()
            )
            try CLIOutput.write(
                response: response,
                asJSON: document.json
            )
        }
    }
}

public struct DimensionSetObjectCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-object",
        abstract: "Set a supported object dimension on one SelectionTarget."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionTarget JSON object.")
    public var target: String?

    @Option(help: "JSON file containing one SelectionTarget object.")
    public var targetFile: String?

    @Option(help: "Object dimension kind: sizeX, sizeY, sizeZ, radius, or diameter.")
    public var kind: ObjectDimensionKind

    @Option(parsing: .unconditional, help: "Dimension value numeric literal.")
    public var value: Double

    @Option(help: "Length unit for the value. Defaults to the workspace display unit.")
    public var unit: String?

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()
        let selectionTarget: SelectionTarget = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: target,
            filePath: targetFile,
            valueName: "SelectionTarget"
        )
        try await CLIExitCode.run {
            let expression = try await CLIDimensionExpressionParser.lengthExpression(
                value: value,
                unitName: unit,
                document: document,
                sessionID: id
            )
            let response = try await CLIService().applyAutomationCommand(
                target: document.target(sessionID: id),
                command: .setObjectDimension(
                    target: selectionTarget,
                    kind: kind,
                    value: expression
                ),
                expectedGeneration: document.generation(),
                expectedWorkspaceRevision: document.workspaceRevision()
            )
            try CLIOutput.write(
                response: response,
                asJSON: document.json
            )
        }
    }
}

private enum CLIDimensionExpressionParser {
    static func expression(
        value: Double,
        unitName: String?,
        sketchKind: SketchEntityDimensionKind,
        document: CLIWriteDocumentOptions,
        sessionID: UUID?
    ) async throws -> CADExpression {
        switch sketchKind {
        case .angle:
            let unit = unitName ?? AngleUnit.degree.rawValue
            guard let angleUnit = AngleUnit(rawValue: unit) else {
                throw ValidationError("Angle dimension unit must be degree or radian.")
            }
            return .constant(.angle(value, unit: angleUnit))
        case .length, .radius, .diameter:
            return try await lengthExpression(
                value: value,
                unitName: unitName,
                document: document,
                sessionID: sessionID
            )
        }
    }

    static func lengthExpression(
        value: Double,
        unitName: String?,
        document: CLIWriteDocumentOptions,
        sessionID: UUID?
    ) async throws -> CADExpression {
        let lengthUnit = try await CLILengthUnitResolver.resolve(
            unitName: unitName,
            document: document,
            sessionID: sessionID
        )
        return .constant(Quantity(value: lengthUnit.meters(from: value), kind: .length))
    }
}

public struct SurfaceCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "surface",
        abstract: "Inspect and edit source-owned surface control data.",
        subcommands: [
            SurfaceSourcesCommand.self,
            SurfaceMoveControlPointCommand.self,
            SurfaceMoveControlPointsInFrameCommand.self,
            SurfaceSetControlPointWeightCommand.self,
            SurfaceSetKnotValueCommand.self,
            SurfaceInsertKnotCommand.self,
            SurfaceSplitSpanCommand.self,
            SurfaceSetKnotMultiplicityCommand.self,
            SurfaceSetTrimDomainCommand.self,
            SurfaceSetTrimLoopsCommand.self,
            SurfaceMoveTrimEndpointCommand.self,
            SurfaceMoveTrimControlPointCommand.self,
            SurfaceSetTrimControlPointWeightCommand.self,
            SurfaceInsertTrimKnotCommand.self,
            SurfaceSetTrimKnotValueCommand.self,
            SurfaceSetTrimKnotMultiplicityCommand.self,
            SurfaceMatchBoundaryContinuityCommand.self,
            SurfaceSlideControlPointsCommand.self,
        ],
        defaultSubcommand: SurfaceSourcesCommand.self
    )

    public init() {}
}

public struct SurfaceSourcesCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sources",
        abstract: "Return source-owned surface references and editable control points."
    )

    @OptionGroup
    public var document: CLIReadDocumentOptions

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: document.target(sessionID: id),
                expectedGeneration: document.generation()
            ) { sessionID in
                .surfaceSourceSummary(
                    sessionID: sessionID,
                    expectedGeneration: document.generation()
                )
            }
            try CLIOutput.write(
                response: try CLIResponseProjector.surfaceSourceSummary(envelope),
                asJSON: document.json
            )
        }
    }
}

public struct SurfaceMoveControlPointCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "move-control-point",
        abstract: "Move one source-owned surface control point from a SelectionReference."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one surface control point.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "Delta X numeric literal.")
    public var deltaX: Double = 0.0

    @Option(parsing: .unconditional, help: "Delta Y numeric literal.")
    public var deltaY: Double = 0.0

    @Option(parsing: .unconditional, help: "Delta Z numeric literal.")
    public var deltaZ: Double = 0.0

    @Option(help: "Length unit for delta values. Defaults to the workspace display unit.")
    public var unit: String?

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()
        let surfaceReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )

        try await CLIExitCode.run {
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: id
            )
            let deltas = deltaExpressions(unit: lengthUnit)
            let response = try await CLIService().applyAutomationCommand(
                target: document.target(sessionID: id),
                command: .moveSurfaceControlPoint(
                    target: surfaceReference,
                    deltaX: deltas.x,
                    deltaY: deltas.y,
                    deltaZ: deltas.z
                ),
                expectedGeneration: document.generation(),
                expectedWorkspaceRevision: document.workspaceRevision()
            )
            try CLIOutput.write(
                response: response,
                asJSON: document.json
            )
        }
    }

    private func deltaExpressions(
        unit lengthUnit: LengthDisplayUnit
    ) -> (x: CADExpression, y: CADExpression, z: CADExpression) {
        return (
            lengthExpression(deltaX, unit: lengthUnit),
            lengthExpression(deltaY, unit: lengthUnit),
            lengthExpression(deltaZ, unit: lengthUnit)
        )
    }

    private func lengthExpression(_ value: Double, unit: LengthDisplayUnit) -> CADExpression {
        .constant(Quantity(value: unit.meters(from: value), kind: .length))
    }
}

public struct SurfaceSlideControlPointsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "slide-control-points",
        abstract: "Slide source-owned surface control points along local U, V, or normal directions."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(
        name: .customLong("reference"),
        help: "SelectionReference JSON object. Repeat to slide multiple surface control points."
    )
    public var referencePayloads: [String] = []

    @Option(help: "JSON file containing one SelectionReference object or an array.")
    public var referencesFile: String?

    @Option(help: "Slide direction: positiveU, negativeU, normal, positiveV, or negativeV.")
    public var direction: CLISurfaceSlideDirection

    @Option(parsing: .unconditional, help: "Slide distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for slide distance. Defaults to the workspace display unit.")
    public var unit: String?

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()
        let references: [SelectionReference] = try CLISelectionInputParser.decodeSelectionInput(
            inlinePayloads: referencePayloads,
            filePath: referencesFile,
            clear: false,
            valueName: "SelectionReference",
            arrayName: "SelectionReference"
        )

        try await CLIExitCode.run {
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: id
            )
            let distanceExpression = lengthExpression(unit: lengthUnit)
            let response = try await CLIService().applyAutomationCommand(
                target: document.target(sessionID: id),
                command: .slideSurfaceControlPoints(
                    targets: references,
                    direction: direction.slideDirection,
                    distance: distanceExpression
                ),
                expectedGeneration: document.generation(),
                expectedWorkspaceRevision: document.workspaceRevision()
            )
            try CLIOutput.write(
                response: response,
                asJSON: document.json
            )
        }
    }

    private func lengthExpression(unit lengthUnit: LengthDisplayUnit) -> CADExpression {
        return .constant(Quantity(value: lengthUnit.meters(from: distance), kind: .length))
    }
}

public struct LineSketchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "line",
        abstract: "Create a line sketch."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Line Sketch"

    @Option(parsing: .unconditional, help: "Line start X numeric literal.")
    public var startX: Double

    @Option(parsing: .unconditional, help: "Line start Y numeric literal.")
    public var startY: Double

    @Option(parsing: .unconditional, help: "Line end X numeric literal.")
    public var endX: Double

    @Option(parsing: .unconditional, help: "Line end Y numeric literal.")
    public var endY: Double

    @Option(help: "Length unit for point coordinates. Defaults to the workspace display unit.")
    public var unit: String?

    @Option(help: "Sketch plane: xy, yz, or zx. Defaults to the active construction plane.")
    public var plane: CLISketchPlane?

    @Option(help: "Saved construction plane UUID. Cannot be combined with --plane.")
    public var constructionPlaneID: String?

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            let points = pointExpressions(unit: lengthUnit)
            return .createLineSketch(
                name: name,
                plane: try CLISketchPlaneReferenceParser.reference(plane: plane, constructionPlaneID: constructionPlaneID),
                start: points.start,
                end: points.end
            )
        }
    }

    private func pointExpressions(
        unit lengthUnit: LengthDisplayUnit
    ) -> (
        start: SketchPoint,
        end: SketchPoint
    ) {
        return (
            SketchPoint(
                x: lengthExpression(startX, unit: lengthUnit),
                y: lengthExpression(startY, unit: lengthUnit)
            ),
            SketchPoint(
                x: lengthExpression(endX, unit: lengthUnit),
                y: lengthExpression(endY, unit: lengthUnit)
            )
        )
    }

    private func lengthExpression(_ value: Double, unit: LengthDisplayUnit) -> CADExpression {
        .constant(Quantity(value: unit.meters(from: value), kind: .length))
    }

}

public struct CircleSketchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "circle",
        abstract: "Create a circle sketch."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Circle Sketch"

    @Option(parsing: .unconditional, help: "Circle center X numeric literal.")
    public var centerX: Double

    @Option(parsing: .unconditional, help: "Circle center Y numeric literal.")
    public var centerY: Double

    @Option(parsing: .unconditional, help: "Circle radius numeric literal.")
    public var radius: Double

    @Option(help: "Length unit for center coordinates and radius. Defaults to the workspace display unit.")
    public var unit: String?

    @Option(help: "Sketch plane: xy, yz, or zx. Defaults to the active construction plane.")
    public var plane: CLISketchPlane?

    @Option(help: "Saved construction plane UUID. Cannot be combined with --plane.")
    public var constructionPlaneID: String?

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            let values = circleExpressions(unit: lengthUnit)
            return .createCircleSketch(
                name: name,
                plane: try CLISketchPlaneReferenceParser.reference(plane: plane, constructionPlaneID: constructionPlaneID),
                center: values.center,
                radius: values.radius
            )
        }
    }

    private func circleExpressions(
        unit lengthUnit: LengthDisplayUnit
    ) -> (
        center: SketchPoint,
        radius: CADExpression
    ) {
        return (
            SketchPoint(
                x: lengthExpression(centerX, unit: lengthUnit),
                y: lengthExpression(centerY, unit: lengthUnit)
            ),
            lengthExpression(radius, unit: lengthUnit)
        )
    }

    private func lengthExpression(_ value: Double, unit: LengthDisplayUnit) -> CADExpression {
        .constant(Quantity(value: unit.meters(from: value), kind: .length))
    }

}

public struct RectangleSketchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rectangle",
        abstract: "Create a rectangle sketch."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Rectangle Sketch"

    @Option(parsing: .unconditional, help: "Rectangle width numeric literal.")
    public var width: Double

    @Option(parsing: .unconditional, help: "Rectangle height numeric literal.")
    public var height: Double

    @Option(help: "Length unit for width and height. Defaults to the workspace display unit.")
    public var unit: String?

    @Option(help: "Sketch plane: xy, yz, or zx. Defaults to the active construction plane.")
    public var plane: CLISketchPlane?

    @Option(help: "Saved construction plane UUID. Cannot be combined with --plane.")
    public var constructionPlaneID: String?

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            let dimensions = dimensionExpressions(unit: lengthUnit)
            return .createRectangleSketch(
                name: name,
                plane: try CLISketchPlaneReferenceParser.reference(plane: plane, constructionPlaneID: constructionPlaneID),
                width: dimensions.width,
                height: dimensions.height
            )
        }
    }

    private func dimensionExpressions(
        unit lengthUnit: LengthDisplayUnit
    ) -> (
        width: CADExpression,
        height: CADExpression
    ) {
        return (
            lengthExpression(width, unit: lengthUnit),
            lengthExpression(height, unit: lengthUnit)
        )
    }

    private func lengthExpression(_ value: Double, unit: LengthDisplayUnit) -> CADExpression {
        .constant(Quantity(value: unit.meters(from: value), kind: .length))
    }

}

public struct BoxModelCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "box",
        abstract: "Create an extruded rectangle body."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Box"

    @Option(parsing: .unconditional, help: "Rectangle width numeric literal.")
    public var width: Double

    @Option(parsing: .unconditional, help: "Rectangle height numeric literal.")
    public var height: Double

    @Option(parsing: .unconditional, help: "Extrude depth numeric literal.")
    public var depth: Double

    @Option(help: "Length unit for width, height, and depth. Defaults to the workspace display unit.")
    public var unit: String?

    @Option(help: "Sketch plane: xy, yz, or zx. Defaults to the active construction plane.")
    public var plane: CLISketchPlane?

    @Option(help: "Saved construction plane UUID. Cannot be combined with --plane.")
    public var constructionPlaneID: String?

    @Option(help: "Extrude direction: normal or symmetric.")
    public var direction: CLIExtrudeDirection = .normal

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            let dimensions = dimensionExpressions(unit: lengthUnit)
            return .createExtrudedRectangle(
                name: name,
                plane: try CLISketchPlaneReferenceParser.reference(plane: plane, constructionPlaneID: constructionPlaneID),
                width: dimensions.width,
                height: dimensions.height,
                depth: dimensions.depth,
                direction: direction.extrudeDirection
            )
        }
    }

    private func dimensionExpressions(
        unit lengthUnit: LengthDisplayUnit
    ) -> (
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression
    ) {
        return (
            .constant(Quantity(value: lengthUnit.meters(from: width), kind: .length)),
            .constant(Quantity(value: lengthUnit.meters(from: height), kind: .length)),
            .constant(Quantity(value: lengthUnit.meters(from: depth), kind: .length))
        )
    }

}

public struct BoxCornersModelCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "box-corners",
        abstract: "Create an extruded rectangle body from two footprint corners."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Box"

    @Option(parsing: .unconditional, help: "First footprint corner X numeric literal.")
    public var firstX: Double

    @Option(parsing: .unconditional, help: "First footprint corner Y numeric literal.")
    public var firstY: Double

    @Option(parsing: .unconditional, help: "Opposite footprint corner X numeric literal.")
    public var oppositeX: Double

    @Option(parsing: .unconditional, help: "Opposite footprint corner Y numeric literal.")
    public var oppositeY: Double

    @Option(parsing: .unconditional, help: "Extrude depth numeric literal.")
    public var depth: Double

    @Option(help: "Length unit for coordinates and depth. Defaults to the workspace display unit.")
    public var unit: String?

    @Option(help: "Sketch plane: xy, yz, or zx. Defaults to the active construction plane.")
    public var plane: CLISketchPlane?

    @Option(help: "Saved construction plane UUID. Cannot be combined with --plane.")
    public var constructionPlaneID: String?

    @Option(help: "Extrude direction: normal or symmetric.")
    public var direction: CLIExtrudeDirection = .normal

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            let modelInputs = modelInputExpressions(unit: lengthUnit)
            return .createExtrudedRectangleFromCorners(
                name: name,
                plane: try CLISketchPlaneReferenceParser.reference(plane: plane, constructionPlaneID: constructionPlaneID),
                firstCorner: modelInputs.firstCorner,
                oppositeCorner: modelInputs.oppositeCorner,
                depth: modelInputs.depth,
                direction: direction.extrudeDirection
            )
        }
    }

    private func modelInputExpressions(
        unit lengthUnit: LengthDisplayUnit
    ) -> (
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint,
        depth: CADExpression
    ) {
        return (
            SketchPoint(
                x: lengthExpression(firstX, unit: lengthUnit),
                y: lengthExpression(firstY, unit: lengthUnit)
            ),
            SketchPoint(
                x: lengthExpression(oppositeX, unit: lengthUnit),
                y: lengthExpression(oppositeY, unit: lengthUnit)
            ),
            lengthExpression(depth, unit: lengthUnit)
        )
    }

    private func lengthExpression(_ value: Double, unit: LengthDisplayUnit) -> CADExpression {
        .constant(Quantity(value: unit.meters(from: value), kind: .length))
    }

}

public struct CylinderModelCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "cylinder",
        abstract: "Create an extruded circle body."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Cylinder"

    @Option(parsing: .unconditional, help: "Circle center X numeric literal.")
    public var centerX: Double = 0.0

    @Option(parsing: .unconditional, help: "Circle center Y numeric literal.")
    public var centerY: Double = 0.0

    @Option(parsing: .unconditional, help: "Circle radius numeric literal.")
    public var radius: Double

    @Option(parsing: .unconditional, help: "Extrude depth numeric literal.")
    public var depth: Double

    @Option(help: "Length unit for center, radius, and depth. Defaults to the workspace display unit.")
    public var unit: String?

    @Option(help: "Sketch plane: xy, yz, or zx. Defaults to the active construction plane.")
    public var plane: CLISketchPlane?

    @Option(help: "Saved construction plane UUID. Cannot be combined with --plane.")
    public var constructionPlaneID: String?

    @Option(help: "Extrude direction: normal or symmetric.")
    public var direction: CLIExtrudeDirection = .normal

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            let values = dimensionExpressions(unit: lengthUnit)
            return .createExtrudedCircle(
                name: name,
                plane: try CLISketchPlaneReferenceParser.reference(plane: plane, constructionPlaneID: constructionPlaneID),
                center: SketchPoint(x: values.centerX, y: values.centerY),
                radius: values.radius,
                depth: values.depth,
                direction: direction.extrudeDirection
            )
        }
    }

    private func dimensionExpressions(
        unit lengthUnit: LengthDisplayUnit
    ) -> (
        centerX: CADExpression,
        centerY: CADExpression,
        radius: CADExpression,
        depth: CADExpression
    ) {
        return (
            .constant(Quantity(value: lengthUnit.meters(from: centerX), kind: .length)),
            .constant(Quantity(value: lengthUnit.meters(from: centerY), kind: .length)),
            .constant(Quantity(value: lengthUnit.meters(from: radius), kind: .length)),
            .constant(Quantity(value: lengthUnit.meters(from: depth), kind: .length))
        )
    }

}

public struct ExtrudeModelCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "extrude",
        abstract: "Extrude an existing closed sketch profile."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Extrude"

    @Option(help: "Sketch feature UUID to extrude.")
    public var profileFeatureID: String

    @Option(parsing: .unconditional, help: "Extrude distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for the distance. Defaults to the workspace display unit.")
    public var unit: String?

    @Option(help: "Extrude direction: normal or symmetric.")
    public var direction: CLIExtrudeDirection = .normal

    public init() {}

    public func run() async throws {
        let profile = try profileReference()

        try await CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            let distanceExpression = distanceExpression(unit: lengthUnit)
            return .extrudeProfile(
                name: name,
                profile: profile,
                distance: distanceExpression,
                direction: direction.extrudeDirection
            )
        }
    }

    private func profileReference() throws -> ProfileReference {
        guard let uuid = UUID(uuidString: profileFeatureID) else {
            throw ValidationError("Profile feature ID must be a UUID.")
        }
        return ProfileReference(featureID: FeatureID(uuid))
    }

    private func distanceExpression(
        unit lengthUnit: LengthDisplayUnit
    ) -> CADExpression {
        return .constant(Quantity(value: lengthUnit.meters(from: distance), kind: .length))
    }

}

public struct ExportDocument: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export a Rupa document to an exchange file."
    )

    @OptionGroup
    public var document: CLIReadDocumentOptions

    @Option(help: "Output file path. The extension selects the export format.")
    public var output: String

    @Option(help: "Export preset name.")
    public var preset: String?

    @Option(help: "Destination policy: prompt, overwrite, or versioned.")
    public var destinationPolicy: ExportPreset.DestinationPolicy?

    @Flag(help: "Evaluate and validate the export without writing the output file.")
    public var dryRun: Bool = false

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()

        try await CLIExitCode.run {
            let outputURL = URL(fileURLWithPath: output)
            let response = try await CLIService().exportDocument(
                target: document.target(sessionID: id),
                outputURL: outputURL,
                expectedGeneration: document.generation(),
                options: ExportOptions(
                    presetName: preset,
                    destinationPolicy: destinationPolicy
                ),
                dryRun: dryRun
            )
            try CLIOutput.write(
                response: response,
                asJSON: document.json
            )
        }
    }
}

public struct EvaluateDocument: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "eval",
        abstract: "Evaluate a Rupa document."
    )

    @OptionGroup
    public var document: CLIReadDocumentOptions

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: document.target(sessionID: id),
                expectedGeneration: document.generation()
            ) { sessionID in
                .evaluate(
                    sessionID: sessionID,
                    expectedGeneration: document.generation()
                )
            }
            try CLIOutput.write(
                response: try CLIResponseProjector.evaluation(envelope),
                asJSON: document.json
            )
        }
    }
}

public struct MeasureDocument: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "measure",
        abstract: "Measure a Rupa document."
    )

    @OptionGroup
    public var document: CLIReadDocumentOptions

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: document.target(sessionID: id),
                expectedGeneration: document.generation()
            ) { sessionID in
                .measure(
                    sessionID: sessionID,
                    expectedGeneration: document.generation()
                )
            }
            try CLIOutput.write(
                response: try CLIResponseProjector.measurement(envelope),
                asJSON: document.json
            )
        }
    }
}

public struct MeshDocument: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mesh",
        abstract: "Summarize evaluated Rupa document meshes."
    )

    @OptionGroup
    public var document: CLIReadDocumentOptions

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: document.target(sessionID: id),
                expectedGeneration: document.generation()
            ) { sessionID in
                .meshSummary(
                    sessionID: sessionID,
                    expectedGeneration: document.generation()
                )
            }
            try CLIOutput.write(
                response: try CLIResponseProjector.meshSummary(envelope),
                asJSON: document.json
            )
        }
    }
}

public struct SaveDocument: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "save",
        abstract: "Save a Rupa document."
    )

    @OptionGroup
    public var document: CLIReadDocumentOptions

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()

        try await CLIExitCode.run {
            let response = try await CLIService().saveDocument(
                target: document.target(sessionID: id),
                expectedGeneration: document.generation()
            )
            try CLIOutput.write(
                response: response,
                asJSON: document.json
            )
        }
    }
}

public struct ParameterCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "param",
        abstract: "Inspect or edit document parameters.",
        subcommands: [
            DeleteParameterCommand.self,
            ListParameterCommand.self,
            RenameParameterCommand.self,
            SetParameterCommand.self,
        ],
        defaultSubcommand: ListParameterCommand.self
    )

    public init() {}
}

public struct ListParameterCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List document parameters."
    )

    @OptionGroup
    public var document: CLIReadDocumentOptions

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()

        try await CLIExitCode.run {
            let response = try await CLIService().send(
                target: document.target(sessionID: id)
            ) { sessionID in
                .parameters(
                    sessionID: sessionID,
                    expectedGeneration: document.generation()
                )
            }
            try CLIOutput.write(
                response: try CLIResponseProjector.parameters(response),
                asJSON: document.json
            )
        }
    }
}

public struct SetParameterCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set a document parameter."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Argument(help: "Parameter name.")
    public var name: String

    @Argument(help: "Numeric literal value. Omit when --expression is supplied.")
    public var value: Double?

    @Option(help: "Parameter formula using numbers, units, existing parameter names, arithmetic, parentheses, sin, cos, or tan.")
    public var expression: String?

    @Option(help: "Parameter kind: length, angle, or scalar.")
    public var kind: CLIParameterKind = .length

    @Option(help: "Length unit or angle unit for the numeric literal.")
    public var unit: String?

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()

        try await CLIExitCode.run {
            let service = CLIService()
            let parameter = try await parameterInput(sessionID: id)
            let response: CLIResponse
            switch parameter {
            case .literal(let expression, let kind):
                response = try await service.applyAutomationCommand(
                    target: document.target(sessionID: id),
                    command: .upsertParameter(
                        name: name,
                        expression: expression,
                        kind: kind
                    ),
                    expectedGeneration: document.generation(),
                    expectedWorkspaceRevision: document.workspaceRevision()
                )
            case .formula(let expression, let kind, let defaults):
                response = try await service.executeCommandMutationRequest(
                    target: document.target(sessionID: id),
                    expectedGeneration: document.generation()
                ) { sessionID in
                    .setParameterExpression(
                        sessionID: sessionID,
                        name: name,
                        expression: expression,
                        kind: kind,
                        defaults: defaults,
                        expectedGeneration: document.generation()
                    )
                }
            }
            try CLIOutput.write(
                response: response,
                asJSON: document.json
            )
        }
    }

    private enum ParameterInput {
        case literal(CADExpression, QuantityKind)
        case formula(String, QuantityKind, ParameterExpressionDefaults)
    }

    private func parameterInput(sessionID: UUID?) async throws -> ParameterInput {
        if let expression {
            guard value == nil else {
                throw ValidationError("Use either a numeric value or --expression, not both.")
            }
            return .formula(
                expression,
                kind.quantityKind,
                try await expressionDefaults(sessionID: sessionID)
            )
        }
        let parsed = try await parameterExpression(sessionID: sessionID)
        return .literal(parsed.expression, parsed.kind)
    }

    private func parameterExpression(
        sessionID: UUID?
    ) async throws -> (expression: CADExpression, kind: QuantityKind) {
        guard let value else {
            throw ValidationError("Parameter set requires a numeric value or --expression.")
        }
        switch kind {
        case .length:
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return (
                .constant(
                    Quantity(
                        value: lengthUnit.meters(from: value),
                        kind: .length
                    )
                ),
                .length
            )
        case .angle:
            let unitName = unit ?? AngleUnit.degree.rawValue
            guard let angleUnit = AngleUnit(rawValue: unitName) else {
                throw ValidationError("Angle unit must be radian or degree.")
            }
            return (
                .constant(.angle(value, unit: angleUnit)),
                .angle
            )
        case .scalar:
            guard unit == nil else {
                throw ValidationError("Scalar parameters do not accept a unit.")
            }
            return (
                .constant(.scalar(value)),
                .scalar
            )
        }
    }

    private func expressionDefaults(
        sessionID: UUID?
    ) async throws -> ParameterExpressionDefaults {
        switch kind {
        case .length:
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return ParameterExpressionDefaults(
                lengthUnit: lengthUnit,
                angleUnit: .degree
            )
        case .angle:
            let unitName = unit ?? AngleUnit.degree.rawValue
            guard let angleUnit = AngleUnit(rawValue: unitName) else {
                throw ValidationError("Angle unit must be radian or degree.")
            }
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: nil,
                document: document,
                sessionID: sessionID
            )
            return ParameterExpressionDefaults(
                lengthUnit: lengthUnit,
                angleUnit: angleUnit
            )
        case .scalar:
            guard unit == nil else {
                throw ValidationError("Scalar parameters do not accept a unit.")
            }
            return ParameterExpressionDefaults()
        }
    }

}

public struct DeleteParameterCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a document parameter."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Argument(help: "Parameter name.")
    public var name: String

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .deleteParameter(name: name)
        )
    }
}

public struct RenameParameterCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a document parameter while preserving references."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Argument(help: "Current parameter name.")
    public var currentName: String

    @Argument(help: "New parameter name.")
    public var newName: String

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .renameParameter(currentName: currentName, newName: newName)
        )
    }
}

public struct RenameDocument: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a Rupa project."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "New document display name.")
    public var name: String

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .renameDocument(name: name)
        )
    }
}

public struct Sessions: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "List open Rupa document sessions."
    )

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() async throws {
        try await CLIExitCode.run {
            let response = try await CLIService().sessions()
            try CLIOutput.write(response: response, asJSON: json)
        }
    }
}

public struct ValidateDocument: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a Rupa project."
    )

    @OptionGroup
    public var document: CLIReadDocumentOptions

    public init() {}

    public func run() async throws {
        let id = try document.resolvedSessionID()

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: document.target(sessionID: id),
                expectedGeneration: document.generation()
            ) { sessionID in
                .execute(
                    sessionID: sessionID,
                    command: .validateDocument,
                    expectedGeneration: document.generation()
                )
            }
            try CLIOutput.write(
                response: try CLIResponseProjector.command(envelope),
                asJSON: document.json
            )
        }
    }
}

public enum CLIOutput {
    public static func write(response: CLIResponse, asJSON: Bool) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    public static func write(response: CLIBatchResponse, asJSON: Bool) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    public static func write(response: CLIDomainExecutionResponse, asJSON: Bool) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLIAgentStatusResponse,
        asJSON: Bool
    ) throws {
        let state = response.running ? "running" : "stopped"
        try write(
            response,
            fallback: "Rupa agent is \(state). Sessions: \(response.sessionCount).",
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLISessionsResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.sessions.map(\.displayName).joined(separator: "\n"),
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLIAttachResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: "\(response.displayName) \(response.sessionID.uuidString)",
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLIParameterListResponse,
        asJSON: Bool
    ) throws {
        let fallback = response.parameters
            .map { "\($0.name): \($0.expression)" }
            .joined(separator: "\n")
        try write(
            response,
            fallback: fallback,
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLIExportResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLIEvaluationResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLIMeasurementResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLIMeshSummaryResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLISurfaceSourceSummaryResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLISketchDimensionSummaryResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLIObjectDimensionSummaryResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLISaveResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    public static func write(
        response: CLISelectionResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    static func write<Response: Encodable>(
        _ response: Response,
        fallback: String,
        asJSON: Bool
    ) throws {
        if asJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(response)
            FileHandle.standardOutput.write(data)
            print()
        } else {
            print(fallback)
        }
    }
}
