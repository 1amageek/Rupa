import ArgumentParser
import Foundation
import RupaAgentProtocol
import RupaCore

public struct CLICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rupa",
        abstract: "Run Rupa command line tools.",
        subcommands: [
            AgentCommand.self,
            AttachDocument.self,
            CADCommand.self,
            Capabilities.self,
            DimensionCommand.self,
            EvaluateDocument.self,
            ExportDocument.self,
            InspectCommand.self,
            MeasureDocument.self,
            MeshDocument.self,
            ParameterCommand.self,
            SaveDocument.self,
            SelectionCommand.self,
            Sessions.self,
            SurfaceCommand.self,
            ValidateDocument.self,
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

    @Flag(name: .long, help: "Print typed capability descriptors as JSON.")
    public var json = false

    public init() {}

    public func run() async throws {
        try await CLIExitCode.run {
            let capabilities = try await CLIService().capabilityDescriptors()
            try CLIOutput.write(capabilities: capabilities, asJSON: json)
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
            DimensionSetSelectionCommand.self,
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
            let response = try await CLIService().executeTypedMutationRequest(
                target: document.target(sessionID: id)
            ) { sessionID in
                .setSketchEntityDimensionExpression(
                    sessionID: sessionID,
                    target: selectionTarget,
                    kind: kind,
                    expression: expression,
                    defaults: nil,
                    expectedGeneration: document.generation()
                )
            }
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
            let response = try await CLIService().executeTypedMutationRequest(
                target: document.target(sessionID: id)
            ) { sessionID in
                .setObjectDimensionExpression(
                    sessionID: sessionID,
                    target: selectionTarget,
                    kind: kind,
                    expression: expression,
                    defaults: nil,
                    expectedGeneration: document.generation()
                )
            }
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
    ) async throws -> String {
        guard value.isFinite else {
            throw ValidationError("Dimension value must be finite.")
        }
        switch sketchKind {
        case .angle:
            let unitName = unitName ?? AngleUnit.degree.rawValue
            guard let unit = AngleUnit(rawValue: unitName) else {
                throw ValidationError("Angle dimension unit must be degree or radian.")
            }
            return "\(value) \(unit.rawValue)"
        case .length, .radius, .diameter:
            let unit = try await CLILengthUnitResolver.resolve(
                unitName: unitName,
                document: document,
                sessionID: sessionID
            )
            return "\(value) \(unit.rawValue)"
        }
    }

    static func lengthExpression(
        value: Double,
        unitName: String?,
        document: CLIWriteDocumentOptions,
        sessionID: UUID?
    ) async throws -> String {
        guard value.isFinite else {
            throw ValidationError("Dimension value must be finite.")
        }
        let unit = try await CLILengthUnitResolver.resolve(
            unitName: unitName,
            document: document,
            sessionID: sessionID
        )
        return "\(value) \(unit.rawValue)"
    }
}

public struct SurfaceCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "surface",
        abstract: "Inspect source-owned surface control data.",
        subcommands: [
            SurfaceSourcesCommand.self,
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
            ListParameterCommand.self,
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
        abstract: "Set a document parameter through a typed expression request."
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
        let sessionID = try document.resolvedSessionID()
        guard (value != nil) != (expression != nil) else {
            throw ValidationError("Parameter set requires exactly one numeric value or --expression.")
        }

        try await CLIExitCode.run {
            let source = try await expressionSource(sessionID: sessionID)
            let defaults = expression == nil
                ? nil
                : try await expressionDefaults(sessionID: sessionID)
            let response = try await CLIService().executeTypedMutationRequest(
                target: document.target(sessionID: sessionID)
            ) { sessionID in
                .setParameterExpression(
                    sessionID: sessionID,
                    name: name,
                    expression: source,
                    kind: kind.quantityKind,
                    defaults: defaults,
                    expectedGeneration: document.generation()
                )
            }
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }

    private func expressionSource(sessionID: UUID?) async throws -> String {
        if let expression {
            return expression
        }
        guard let value else {
            throw ValidationError("Parameter set requires a numeric value or --expression.")
        }
        guard value.isFinite else {
            throw ValidationError("Parameter value must be finite.")
        }
        switch kind {
        case .length:
            let unit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return "\(value) \(unit.rawValue)"
        case .angle:
            let unitName = unit ?? AngleUnit.degree.rawValue
            guard let unit = AngleUnit(rawValue: unitName) else {
                throw ValidationError("Angle unit must be radian or degree.")
            }
            return "\(value) \(unit.rawValue)"
        case .scalar:
            guard unit == nil else {
                throw ValidationError("Scalar parameters do not accept a unit.")
            }
            return "\(value)"
        }
    }

    private func expressionDefaults(sessionID: UUID?) async throws -> ParameterExpressionDefaults {
        switch kind {
        case .length:
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return ParameterExpressionDefaults(lengthUnit: lengthUnit, angleUnit: .degree)
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
            return ParameterExpressionDefaults(lengthUnit: lengthUnit, angleUnit: angleUnit)
        case .scalar:
            guard unit == nil else {
                throw ValidationError("Scalar parameters do not accept a unit.")
            }
            return ParameterExpressionDefaults()
        }
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
            let response = try await CLIService().send(
                target: document.target(sessionID: id),
            ) { sessionID in
                .validateDocument(
                    sessionID: sessionID,
                    expectedGeneration: document.generation()
                )
            }
            try CLIOutput.write(
                response: try CLIResponseProjector.documentValidation(response),
                asJSON: document.json
            )
        }
    }
}

public enum CLIOutput {
    public static func write(
        capabilities: [AgentCapabilityDescriptor],
        asJSON: Bool
    ) throws {
        try write(
            capabilities,
            fallback: capabilities.map(\.name).joined(separator: "\n"),
            asJSON: asJSON
        )
    }

    public static func write(response: CLIResponse, asJSON: Bool) throws {
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
            FileHandle.standardOutput.write(try jsonData(response))
            print()
        } else {
            print(fallback)
        }
    }

    static func jsonData<Response: Encodable>(_ response: Response) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(response)
    }
}
