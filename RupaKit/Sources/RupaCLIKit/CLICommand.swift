import ArgumentParser
import Foundation
import RupaAgent
import RupaAutomation
import RupaCore
import SwiftCAD

public struct CLICommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rupa",
        abstract: "Run Rupa command line tools.",
        subcommands: [
            AgentCommand.self,
            AttachDocument.self,
            Capabilities.self,
            EvaluateDocument.self,
            ExportDocument.self,
            MeasureDocument.self,
            MeshDocument.self,
            ModelCommand.self,
            ParameterCommand.self,
            RenameDocument.self,
            RenameLiveDocument.self,
            SaveDocument.self,
            SketchCommand.self,
            Sessions.self,
            ValidateDocument.self,
        ],
        defaultSubcommand: Capabilities.self
    )

    public init() {}
}

public struct Capabilities: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "capabilities",
        abstract: "Print supported command capabilities."
    )

    public init() {}

    public func run() throws {
        print(CLIService().capabilities().joined(separator: "\n"))
    }
}

extension CLIEditMode: ExpressibleByArgument {}
extension ExportPreset.DestinationPolicy: ExpressibleByArgument {}

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

public struct AgentCommand: ParsableCommand {
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

public struct AgentStatusCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Print Rupa agent status."
    )

    @Option(help: "Path to the Rupa agent socket.")
    public var socket: String = AgentSocketPath.defaultPath

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        try CLIExitCode.run {
            let response = try CLIService().agentStatus(
                client: AgentClient(socketPath: AgentSocketPath(socket))
            )
            try CLIOutput.write(response: response, asJSON: json)
        }
    }
}

public struct AttachDocument: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Resolve an open Rupa document session."
    )

    @Argument(help: "Path to the open .swcad document.")
    public var file: String?

    @Option(help: "Open document session UUID.")
    public var session: String?

    @Option(help: "Path to the Rupa agent socket.")
    public var socket: String = AgentSocketPath.defaultPath

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(session)

        try CLIExitCode.run {
            let response = try CLIService().attach(
                target: CLIDocumentTarget(
                    fileURL: file.map(URL.init(fileURLWithPath:)),
                    sessionID: id
                ),
                client: AgentClient(socketPath: AgentSocketPath(socket))
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

public struct ModelCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "model",
        abstract: "Create generic CAD model features.",
        subcommands: [
            BoxModelCommand.self,
            BoxCornersModelCommand.self,
            CylinderModelCommand.self,
            ExtrudeModelCommand.self,
        ],
        defaultSubcommand: BoxModelCommand.self
    )

    public init() {}
}

public struct SketchCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sketch",
        abstract: "Create generic CAD sketch features.",
        subcommands: [
            LineSketchCommand.self,
            CircleSketchCommand.self,
            RectangleSketchCommand.self,
        ],
        defaultSubcommand: LineSketchCommand.self
    )

    public init() {}
}

public struct LineSketchCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "line",
        abstract: "Create a line sketch."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Feature name.")
    public var name: String = "Line Sketch"

    @Option(help: "Line start X numeric literal.")
    public var startX: Double

    @Option(help: "Line start Y numeric literal.")
    public var startY: Double

    @Option(help: "Line end X numeric literal.")
    public var endX: Double

    @Option(help: "Line end Y numeric literal.")
    public var endY: Double

    @Option(help: "Length unit for point coordinates.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    @Option(help: "Sketch plane: xy, yz, or zx.")
    public var plane: CLISketchPlane = .xy

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)
        let points = try pointExpressions()

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().createLineSketch(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                name: name,
                plane: plane.sketchPlane,
                start: points.start,
                end: points.end,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func pointExpressions() throws -> (
        start: SketchPoint,
        end: SketchPoint
    ) {
        guard let lengthUnit = LengthDisplayUnit(rawValue: unit) else {
            throw ValidationError("Length unit must be a supported Rupa display unit.")
        }
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

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct CircleSketchCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "circle",
        abstract: "Create a circle sketch."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Feature name.")
    public var name: String = "Circle Sketch"

    @Option(help: "Circle center X numeric literal.")
    public var centerX: Double

    @Option(help: "Circle center Y numeric literal.")
    public var centerY: Double

    @Option(help: "Circle radius numeric literal.")
    public var radius: Double

    @Option(help: "Length unit for center coordinates and radius.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    @Option(help: "Sketch plane: xy, yz, or zx.")
    public var plane: CLISketchPlane = .xy

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)
        let values = try circleExpressions()

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().createCircleSketch(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                name: name,
                plane: plane.sketchPlane,
                center: values.center,
                radius: values.radius,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func circleExpressions() throws -> (
        center: SketchPoint,
        radius: CADExpression
    ) {
        guard let lengthUnit = LengthDisplayUnit(rawValue: unit) else {
            throw ValidationError("Length unit must be a supported Rupa display unit.")
        }
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

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct RectangleSketchCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rectangle",
        abstract: "Create a rectangle sketch."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Feature name.")
    public var name: String = "Rectangle Sketch"

    @Option(help: "Rectangle width numeric literal.")
    public var width: Double

    @Option(help: "Rectangle height numeric literal.")
    public var height: Double

    @Option(help: "Length unit for width and height.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    @Option(help: "Sketch plane: xy, yz, or zx.")
    public var plane: CLISketchPlane = .xy

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)
        let dimensions = try dimensionExpressions()

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().createRectangleSketch(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                name: name,
                plane: plane.sketchPlane,
                width: dimensions.width,
                height: dimensions.height,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func dimensionExpressions() throws -> (
        width: CADExpression,
        height: CADExpression
    ) {
        guard let lengthUnit = LengthDisplayUnit(rawValue: unit) else {
            throw ValidationError("Length unit must be a supported Rupa display unit.")
        }
        return (
            lengthExpression(width, unit: lengthUnit),
            lengthExpression(height, unit: lengthUnit)
        )
    }

    private func lengthExpression(_ value: Double, unit: LengthDisplayUnit) -> CADExpression {
        .constant(Quantity(value: unit.meters(from: value), kind: .length))
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct BoxModelCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "box",
        abstract: "Create an extruded rectangle body."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Feature name.")
    public var name: String = "Box"

    @Option(help: "Rectangle width numeric literal.")
    public var width: Double

    @Option(help: "Rectangle height numeric literal.")
    public var height: Double

    @Option(help: "Extrude depth numeric literal.")
    public var depth: Double

    @Option(help: "Length unit for width, height, and depth.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    @Option(help: "Sketch plane: xy, yz, or zx.")
    public var plane: CLISketchPlane = .xy

    @Option(help: "Extrude direction: normal or symmetric.")
    public var direction: CLIExtrudeDirection = .normal

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)
        let dimensions = try dimensionExpressions()

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().createExtrudedRectangle(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                name: name,
                plane: plane.sketchPlane,
                width: dimensions.width,
                height: dimensions.height,
                depth: dimensions.depth,
                direction: direction.extrudeDirection,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func dimensionExpressions() throws -> (
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression
    ) {
        guard let lengthUnit = LengthDisplayUnit(rawValue: unit) else {
            throw ValidationError("Length unit must be a supported Rupa display unit.")
        }
        return (
            .constant(Quantity(value: lengthUnit.meters(from: width), kind: .length)),
            .constant(Quantity(value: lengthUnit.meters(from: height), kind: .length)),
            .constant(Quantity(value: lengthUnit.meters(from: depth), kind: .length))
        )
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct BoxCornersModelCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "box-corners",
        abstract: "Create an extruded rectangle body from two footprint corners."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Feature name.")
    public var name: String = "Box"

    @Option(help: "First footprint corner X numeric literal.")
    public var firstX: Double

    @Option(help: "First footprint corner Y numeric literal.")
    public var firstY: Double

    @Option(help: "Opposite footprint corner X numeric literal.")
    public var oppositeX: Double

    @Option(help: "Opposite footprint corner Y numeric literal.")
    public var oppositeY: Double

    @Option(help: "Extrude depth numeric literal.")
    public var depth: Double

    @Option(help: "Length unit for coordinates and depth.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    @Option(help: "Sketch plane: xy, yz, or zx.")
    public var plane: CLISketchPlane = .xy

    @Option(help: "Extrude direction: normal or symmetric.")
    public var direction: CLIExtrudeDirection = .normal

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)
        let modelInputs = try modelInputExpressions()

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().createExtrudedRectangleFromCorners(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                name: name,
                plane: plane.sketchPlane,
                firstCorner: modelInputs.firstCorner,
                oppositeCorner: modelInputs.oppositeCorner,
                depth: modelInputs.depth,
                direction: direction.extrudeDirection,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func modelInputExpressions() throws -> (
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint,
        depth: CADExpression
    ) {
        guard let lengthUnit = LengthDisplayUnit(rawValue: unit) else {
            throw ValidationError("Length unit must be a supported Rupa display unit.")
        }
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

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct CylinderModelCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "cylinder",
        abstract: "Create an extruded circle body."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Feature name.")
    public var name: String = "Cylinder"

    @Option(help: "Circle center X numeric literal.")
    public var centerX: Double = 0.0

    @Option(help: "Circle center Y numeric literal.")
    public var centerY: Double = 0.0

    @Option(help: "Circle radius numeric literal.")
    public var radius: Double

    @Option(help: "Extrude depth numeric literal.")
    public var depth: Double

    @Option(help: "Length unit for center, radius, and depth.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    @Option(help: "Sketch plane: xy, yz, or zx.")
    public var plane: CLISketchPlane = .xy

    @Option(help: "Extrude direction: normal or symmetric.")
    public var direction: CLIExtrudeDirection = .normal

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)
        let values = try dimensionExpressions()

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().createExtrudedCircle(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                name: name,
                plane: plane.sketchPlane,
                center: SketchPoint(x: values.centerX, y: values.centerY),
                radius: values.radius,
                depth: values.depth,
                direction: direction.extrudeDirection,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func dimensionExpressions() throws -> (
        centerX: CADExpression,
        centerY: CADExpression,
        radius: CADExpression,
        depth: CADExpression
    ) {
        guard let lengthUnit = LengthDisplayUnit(rawValue: unit) else {
            throw ValidationError("Length unit must be a supported Rupa display unit.")
        }
        return (
            .constant(Quantity(value: lengthUnit.meters(from: centerX), kind: .length)),
            .constant(Quantity(value: lengthUnit.meters(from: centerY), kind: .length)),
            .constant(Quantity(value: lengthUnit.meters(from: radius), kind: .length)),
            .constant(Quantity(value: lengthUnit.meters(from: depth), kind: .length))
        )
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
            AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct ExtrudeModelCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "extrude",
        abstract: "Extrude an existing closed sketch profile."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Feature name.")
    public var name: String = "Extrude"

    @Option(help: "Sketch feature UUID to extrude.")
    public var profileFeatureID: String

    @Option(help: "Extrude distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for the distance.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    @Option(help: "Extrude direction: normal or symmetric.")
    public var direction: CLIExtrudeDirection = .normal

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)
        let profile = try profileReference()
        let distanceExpression = try distanceExpression()

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().extrudeProfile(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                name: name,
                profile: profile,
                distance: distanceExpression,
                direction: direction.extrudeDirection,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func profileReference() throws -> ProfileReference {
        guard let uuid = UUID(uuidString: profileFeatureID) else {
            throw ValidationError("Profile feature ID must be a UUID.")
        }
        return ProfileReference(featureID: FeatureID(uuid))
    }

    private func distanceExpression() throws -> CADExpression {
        guard let lengthUnit = LengthDisplayUnit(rawValue: unit) else {
            throw ValidationError("Length unit must be a supported Rupa display unit.")
        }
        return .constant(Quantity(value: lengthUnit.meters(from: distance), kind: .length))
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
            AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct ExportDocument: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export a Rupa document to an exchange file."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Output file path. The extension selects the export format.")
    public var output: String

    @Option(help: "Export mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Option(help: "Export preset name.")
    public var preset: String?

    @Option(help: "Destination policy: prompt, overwrite, or versioned.")
    public var destinationPolicy: ExportPreset.DestinationPolicy?

    @Flag(help: "Evaluate and validate the export without writing the output file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file export even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let outputURL = URL(fileURLWithPath: output)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().exportDocument(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                outputURL: outputURL,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                options: ExportOptions(
                    presetName: preset,
                    destinationPolicy: destinationPolicy
                ),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct EvaluateDocument: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "eval",
        abstract: "Evaluate a Rupa document."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Evaluation mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Option(help: "Optional Rupa agent socket used to detect open document sessions.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().evaluateDocument(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct MeasureDocument: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "measure",
        abstract: "Measure a Rupa document."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Measurement mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Option(help: "Optional Rupa agent socket used to detect open document sessions.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().measureDocument(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct MeshDocument: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mesh",
        abstract: "Summarize evaluated Rupa document meshes."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Mesh summary mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Option(help: "Optional Rupa agent socket used to detect open document sessions.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().meshSummary(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct SaveDocument: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "save",
        abstract: "Save a Rupa document."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Save mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Allow direct file save even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().saveDocument(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct ParameterCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "param",
        abstract: "Inspect or edit document parameters.",
        subcommands: [
            DeleteParameterCommand.self,
            ListParameterCommand.self,
            SetParameterCommand.self,
        ],
        defaultSubcommand: ListParameterCommand.self
    )

    public init() {}
}

public struct ListParameterCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List document parameters."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "Read mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Option(help: "Optional Rupa agent socket used to detect open document sessions.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().listParameters(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct SetParameterCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set a document parameter."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

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

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)
        let parameter = try parameterInput()

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let target = CLIDocumentTarget(
                fileURL: url,
                sessionID: id
            )
            let service = CLIService()
            let response: CLIResponse
            switch parameter {
            case .literal(let expression, let kind):
                response = try service.setParameter(
                    target: target,
                    name: name,
                    expression: expression,
                    kind: kind,
                    mode: mode,
                    expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                    dryRun: dryRun,
                    forceFileEdit: forceFileEdit,
                    client: agentClient
                )
            case .formula(let expression, let kind, let defaults):
                response = try service.setParameterExpression(
                    target: target,
                    name: name,
                    expression: expression,
                    kind: kind,
                    defaults: defaults,
                    mode: mode,
                    expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                    dryRun: dryRun,
                    forceFileEdit: forceFileEdit,
                    client: agentClient
                )
            }
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private enum ParameterInput {
        case literal(CADExpression, QuantityKind)
        case formula(String, QuantityKind, ParameterExpressionDefaults)
    }

    private func parameterInput() throws -> ParameterInput {
        if let expression {
            guard value == nil else {
                throw ValidationError("Use either a numeric value or --expression, not both.")
            }
            return .formula(
                expression,
                kind.quantityKind,
                try expressionDefaults()
            )
        }
        let parsed = try parameterExpression()
        return .literal(parsed.expression, parsed.kind)
    }

    private func parameterExpression() throws -> (expression: CADExpression, kind: QuantityKind) {
        guard let value else {
            throw ValidationError("Parameter set requires a numeric value or --expression.")
        }
        switch kind {
        case .length:
            let unitName = unit ?? LengthDisplayUnit.meter.rawValue
            guard let lengthUnit = LengthDisplayUnit(rawValue: unitName) else {
                throw ValidationError("Length unit must be a supported Rupa display unit.")
            }
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

    private func expressionDefaults() throws -> ParameterExpressionDefaults {
        switch kind {
        case .length:
            let unitName = unit ?? LengthDisplayUnit.meter.rawValue
            guard let lengthUnit = LengthDisplayUnit(rawValue: unitName) else {
                throw ValidationError("Length unit must be a supported Rupa display unit.")
            }
            return ParameterExpressionDefaults(
                lengthUnit: lengthUnit,
                angleUnit: .degree
            )
        case .angle:
            let unitName = unit ?? AngleUnit.degree.rawValue
            guard let angleUnit = AngleUnit(rawValue: unitName) else {
                throw ValidationError("Angle unit must be radian or degree.")
            }
            return ParameterExpressionDefaults(
                lengthUnit: .meter,
                angleUnit: angleUnit
            )
        case .scalar:
            guard unit == nil else {
                throw ValidationError("Scalar parameters do not accept a unit.")
            }
            return ParameterExpressionDefaults()
        }
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct DeleteParameterCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a document parameter."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Argument(help: "Parameter name.")
    public var name: String

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().deleteParameter(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                name: name,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct RenameDocument: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a closed Rupa document file."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Option(help: "New document display name.")
    public var name: String

    @Option(help: "Rename mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try parsedSessionID(sessionID)

        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let agentClient = makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().renameDocument(
                target: CLIDocumentTarget(
                    fileURL: url,
                    sessionID: id
                ),
                name: name,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(
                response: response,
                asJSON: json
            )
        }
    }

    private func parsedSessionID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Session ID must be a UUID.")
        }
        return id
    }

    private func makeAgentClient(
        mode: CLIEditMode,
        sessionID: UUID?,
        socket: String?
    ) -> AgentClient? {
        let resolvedSocket: String?
        if let socket {
            resolvedSocket = socket
        } else if mode == .live || sessionID != nil {
            resolvedSocket = AgentSocketPath.defaultPath
        } else {
            resolvedSocket = nil
        }
        return resolvedSocket.map { socket in
                AgentClient(socketPath: AgentSocketPath(socket))
        }
    }
}

public struct RenameLiveDocument: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rename-live",
        abstract: "Rename an open Rupa document through the running app session."
    )

    @Argument(help: "Open document session UUID.")
    public var sessionID: String

    @Option(help: "New document display name.")
    public var name: String

    @Option(help: "Expected document generation.")
    public var expectedGeneration: UInt64?

    @Option(help: "Path to the Rupa agent socket.")
    public var socket: String = AgentSocketPath.defaultPath

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        guard let id = UUID(uuidString: sessionID) else {
            throw ValidationError("Session ID must be a UUID.")
        }

        try CLIExitCode.run {
            let response = try CLIService().renameDocument(
                target: CLIDocumentTarget(sessionID: id),
                name: name,
                mode: .live,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                client: AgentClient(socketPath: AgentSocketPath(socket))
            )
            try CLIOutput.write(response: response, asJSON: json)
        }
    }
}

public struct Sessions: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "List open Rupa document sessions."
    )

    @Option(help: "Path to the Rupa agent socket.")
    public var socket: String = AgentSocketPath.defaultPath

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        try CLIExitCode.run {
            let response = try CLIService().sessions(
                client: AgentClient(socketPath: AgentSocketPath(socket))
            )
            try CLIOutput.write(response: response, asJSON: json)
        }
    }
}

public struct ValidateDocument: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a closed Rupa document file."
    )

    @Argument(help: "Path to the .swcad document.")
    public var file: String

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            let response = try CLIService().validateFile(at: url)
            try CLIOutput.write(
                response: response,
                asJSON: json
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
        response: CLISaveResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    private static func write<Response: Encodable>(
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
