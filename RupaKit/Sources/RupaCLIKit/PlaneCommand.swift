import ArgumentParser
import Foundation
import RupaCore
import SwiftCAD

public struct PlaneCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "plane",
        abstract: "Create and manage saved construction planes.",
        subcommands: [
            PlaneCreateCommand.self,
            PlaneCreateViewCommand.self,
            PlaneSetActiveCommand.self,
            PlaneRenameCommand.self,
        ],
        defaultSubcommand: PlaneCreateCommand.self
    )

    public init() {}
}

public struct PlaneCreateCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a saved construction plane from a standard sketch plane."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Saved construction-plane name.")
    public var name: String

    @Option(help: "Sketch plane: xy, yz, or zx.")
    public var plane: CLISketchPlane = .xy

    @Flag(name: .customLong("no-activate"), help: "Create the plane without making it active.")
    public var noActivate: Bool = false

    public init() {}

    public func run() throws {
        let id = try document.resolvedSessionID()

        try CLIExitCode.run {
            let response = try CLIService().createConstructionPlane(
                target: document.target(sessionID: id),
                name: name,
                plane: plane.sketchPlane,
                activates: !noActivate,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: id)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }
}

public struct PlaneCreateViewCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "create-view",
        abstract: "Create a saved construction plane from an origin and view normal."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Saved construction-plane name.")
    public var name: String

    @Option(help: "Origin X coordinate.")
    public var originX: Double = 0.0

    @Option(help: "Origin Y coordinate.")
    public var originY: Double = 0.0

    @Option(help: "Origin Z coordinate.")
    public var originZ: Double = 0.0

    @Option(help: "Length unit for the origin coordinates.")
    public var unit: LengthDisplayUnit = .meter

    @Option(help: "View normal X component.")
    public var normalX: Double = 0.0

    @Option(help: "View normal Y component.")
    public var normalY: Double = 0.0

    @Option(help: "View normal Z component.")
    public var normalZ: Double = 1.0

    @Flag(name: .customLong("no-activate"), help: "Create the plane without making it active.")
    public var noActivate: Bool = false

    public init() {}

    public func run() throws {
        let id = try document.resolvedSessionID()
        let origin = Point3D(
            x: unit.meters(from: originX),
            y: unit.meters(from: originY),
            z: unit.meters(from: originZ)
        )
        let viewNormal = Vector3D(
            x: normalX,
            y: normalY,
            z: normalZ
        )

        try CLIExitCode.run {
            let response = try CLIService().createViewAlignedConstructionPlane(
                target: document.target(sessionID: id),
                name: name,
                origin: origin,
                viewNormal: viewNormal,
                activates: !noActivate,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: id)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }
}

public struct PlaneSetActiveCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-active",
        abstract: "Set or clear the active saved construction plane."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Construction plane UUID.")
    public var id: String?

    @Flag(help: "Clear the active construction plane.")
    public var clear: Bool = false

    public init() {}

    public func run() throws {
        guard (id != nil) != clear else {
            throw ValidationError("Provide exactly one of --id or --clear.")
        }
        let sessionID = try document.resolvedSessionID()
        let planeID = try CLIConstructionPlaneIDParser.optionalID(id)

        try CLIExitCode.run {
            let response = try CLIService().setActiveConstructionPlane(
                target: document.target(sessionID: sessionID),
                id: planeID,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }
}

public struct PlaneRenameCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a saved construction plane."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Construction plane UUID.")
    public var id: String

    @Option(help: "New saved construction-plane name.")
    public var name: String

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()
        let planeID = try CLIConstructionPlaneIDParser.id(id)

        try CLIExitCode.run {
            let response = try CLIService().renameConstructionPlane(
                target: document.target(sessionID: sessionID),
                id: planeID,
                name: name,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }
}

private enum CLIConstructionPlaneIDParser {
    static func id(_ value: String) throws -> ConstructionPlaneSourceID {
        guard let uuid = UUID(uuidString: value) else {
            throw ValidationError("Construction plane ID must be a UUID.")
        }
        return ConstructionPlaneSourceID(uuid)
    }

    static func optionalID(_ value: String?) throws -> ConstructionPlaneSourceID? {
        guard let value else {
            return nil
        }
        return try id(value)
    }
}
