import ArgumentParser
import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD

public struct PlaneCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "plane",
        abstract: "Create and manage saved construction planes.",
        subcommands: [
            PlaneCreateCommand.self,
            PlaneCreateViewCommand.self,
            PlaneCreateTargetCommand.self,
            PlaneCreateTargetsCommand.self,
            PlaneSetActiveCommand.self,
            PlaneRenameCommand.self,
        ],
        defaultSubcommand: PlaneCreateCommand.self
    )

    public init() {}
}

public struct PlaneCreateCommand: AsyncParsableCommand {
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

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .createConstructionPlane(
                name: name,
                plane: plane.sketchPlane
            )
        )
    }
}

public struct PlaneCreateViewCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "create-view",
        abstract: "Create a saved construction plane from an origin and view normal."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Saved construction-plane name.")
    public var name: String

    @Option(parsing: .unconditional, help: "Origin X coordinate.")
    public var originX: Double = 0.0

    @Option(parsing: .unconditional, help: "Origin Y coordinate.")
    public var originY: Double = 0.0

    @Option(parsing: .unconditional, help: "Origin Z coordinate.")
    public var originZ: Double = 0.0

    @Option(help: "Length unit for the origin coordinates.")
    public var unit: LengthDisplayUnit = .meter

    @Option(parsing: .unconditional, help: "View normal X component.")
    public var normalX: Double = 0.0

    @Option(parsing: .unconditional, help: "View normal Y component.")
    public var normalY: Double = 0.0

    @Option(parsing: .unconditional, help: "View normal Z component.")
    public var normalZ: Double = 1.0

    public init() {}

    public func run() async throws {
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

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .createViewAlignedConstructionPlane(
                name: name,
                origin: origin,
                viewNormal: viewNormal
            )
        )
    }
}

public struct PlaneCreateTargetCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "create-target",
        abstract: "Create a saved construction plane aligned to one selection target."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Saved construction-plane name.")
    public var name: String

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .createConstructionPlaneFromTarget(
                name: name,
                target: selection.decodedTarget()
            )
        )
    }
}

public struct PlaneCreateTargetsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "create-targets",
        abstract: "Create a saved construction plane from multiple selection targets."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Saved construction-plane name.")
    public var name: String

    @OptionGroup
    public var selection: CLISelectionTargetsOptions

    @Option(parsing: .unconditional, help: "View normal X component for target combinations that need camera context.")
    public var viewNormalX: Double?

    @Option(parsing: .unconditional, help: "View normal Y component for target combinations that need camera context.")
    public var viewNormalY: Double?

    @Option(parsing: .unconditional, help: "View normal Z component for target combinations that need camera context.")
    public var viewNormalZ: Double?

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .createConstructionPlaneFromTargets(
                name: name,
                targets: selection.decodedTargets(),
                viewNormal: try viewNormal()
            )
        )
    }

    private func viewNormal() throws -> Vector3D? {
        let values = [viewNormalX, viewNormalY, viewNormalZ]
        guard values.contains(where: { $0 != nil }) else {
            return nil
        }
        guard let x = viewNormalX,
              let y = viewNormalY,
              let z = viewNormalZ else {
            throw ValidationError("Provide all view normal components or none.")
        }
        return Vector3D(x: x, y: y, z: z)
    }
}

public struct PlaneSetActiveCommand: AsyncParsableCommand {
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

    public func run() async throws {
        guard (id != nil) != clear else {
            throw ValidationError("Provide exactly one of --id or --clear.")
        }
        let planeID = try CLIConstructionPlaneIDParser.optionalID(id)
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .setActiveConstructionPlane(id: planeID)
        )
    }
}

public struct PlaneRenameCommand: AsyncParsableCommand {
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

    public func run() async throws {
        let planeID = try CLIConstructionPlaneIDParser.id(id)
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .renameConstructionPlane(
                id: planeID,
                name: name
            )
        )
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
