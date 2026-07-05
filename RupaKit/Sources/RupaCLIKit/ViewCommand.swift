import ArgumentParser
import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD

public struct ViewCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "Create and manage saved drawing and viewport views.",
        subcommands: [
            ViewListCommand.self,
            ViewCreateCommand.self,
            ViewUpdateCommand.self,
            ViewRemoveCommand.self,
        ],
        defaultSubcommand: ViewListCommand.self
    )

    public init() {}
}

public struct ViewListCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List saved views in a document."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .describeSavedViews
        )
    }
}

public struct ViewCreateCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a saved view from explicit camera, projection, and scale data."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Saved view UUID. Omit to generate one.")
    public var id: String?

    @OptionGroup
    private var definition: CLISavedViewDefinitionOptions

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .createSavedView(
                definition.savedView(id: try CLISavedViewIDParser.optionalID(id))
            )
        )
    }
}

public struct ViewUpdateCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Replace an existing saved view with explicit camera, projection, and scale data."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Saved view UUID.")
    public var id: String

    @OptionGroup
    private var definition: CLISavedViewDefinitionOptions

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .updateSavedView(
                definition.savedView(id: try CLISavedViewIDParser.id(id))
            )
        )
    }
}

public struct ViewRemoveCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a saved view."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Saved view UUID.")
    public var id: String

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .removeSavedView(id: try CLISavedViewIDParser.id(id))
        )
    }
}

private struct CLISavedViewDefinitionOptions: ParsableArguments {
    @Option(help: "Saved view name.")
    var name: String

    @Option(help: "Camera target X coordinate in the selected length unit.")
    var targetX: Double = 0.0

    @Option(help: "Camera target Y coordinate in the selected length unit.")
    var targetY: Double = 0.0

    @Option(help: "Camera target Z coordinate in the selected length unit.")
    var targetZ: Double = 0.0

    @Option(help: "Length unit for target, distance, and orthographic height.")
    var unit: LengthDisplayUnit = .meter

    @Option(help: "Camera distance in the selected length unit.")
    var distance: Double

    @Option(help: "Camera yaw angle in degrees.")
    var yawDegrees: Double

    @Option(help: "Camera pitch angle in degrees.")
    var pitchDegrees: Double

    @Option(help: "Camera roll angle in degrees.")
    var rollDegrees: Double = 0.0

    @Option(help: "Projection mode: orthographic or perspective.")
    var projection: CLISavedViewProjectionMode = .orthographic

    @Option(help: "Orthographic view height in the selected length unit.")
    var orthographicHeight: Double?

    @Option(help: "Perspective field of view in degrees.")
    var fieldOfViewDegrees: Double?

    @Option(help: "Workspace scale preset to save with the view.")
    var scalePreset: WorkspaceScalePreset?

    @Option(help: "Custom display unit when no scale preset is supplied.")
    var displayUnit: LengthDisplayUnit?

    @Option(help: "Custom minor ruler tick in meters.")
    var minorTickMeters: Double?

    @Option(help: "Custom major ruler tick in meters.")
    var majorTickMeters: Double?

    @Option(help: "Custom visible workspace span in meters.")
    var visibleSpanMeters: Double?

    @Option(help: "Scale bar length in meters.")
    var scaleBarMeters: Double?

    func savedView(id: SavedViewID?) throws -> SavedView {
        let savedView = SavedView(
            id: id ?? SavedViewID(),
            name: name,
            camera: try camera(),
            projection: try savedProjection(),
            displayScale: try displayScale()
        )
        return savedView
    }

    private func camera() throws -> SavedViewCamera {
        let camera = SavedViewCamera(
            target: Point3D(
                x: unit.meters(from: targetX),
                y: unit.meters(from: targetY),
                z: unit.meters(from: targetZ)
            ),
            distanceMeters: unit.meters(from: distance),
            yawRadians: radians(fromDegrees: yawDegrees),
            pitchRadians: radians(fromDegrees: pitchDegrees),
            rollRadians: radians(fromDegrees: rollDegrees)
        )
        try camera.validate()
        return camera
    }

    private func savedProjection() throws -> SavedViewProjection {
        switch projection {
        case .orthographic:
            guard let orthographicHeight else {
                throw ValidationError("Orthographic saved views require --orthographic-height.")
            }
            guard fieldOfViewDegrees == nil else {
                throw ValidationError("Orthographic saved views must not include --field-of-view-degrees.")
            }
            let savedProjection = SavedViewProjection.orthographic(
                heightMeters: unit.meters(from: orthographicHeight)
            )
            try savedProjection.validate()
            return savedProjection
        case .perspective:
            guard let fieldOfViewDegrees else {
                throw ValidationError("Perspective saved views require --field-of-view-degrees.")
            }
            guard orthographicHeight == nil else {
                throw ValidationError("Perspective saved views must not include --orthographic-height.")
            }
            let savedProjection = SavedViewProjection.perspective(
                fieldOfViewRadians: radians(fromDegrees: fieldOfViewDegrees)
            )
            try savedProjection.validate()
            return savedProjection
        }
    }

    private func displayScale() throws -> SavedViewDisplayScale {
        if let scalePreset {
            try rejectCustomRulerFieldsWithScalePreset()
            return SavedViewDisplayScale(
                ruler: scalePreset.rulerConfiguration.normalizedForWorkspaceScale(),
                scaleBarLengthMeters: scaleBarMeters
            )
        }

        guard let displayUnit,
              let minorTickMeters,
              let majorTickMeters,
              let visibleSpanMeters,
              let scaleBarMeters else {
            throw ValidationError(
                "Provide --scale-preset or all custom scale fields: --display-unit, --minor-tick-meters, --major-tick-meters, --visible-span-meters, and --scale-bar-meters."
            )
        }

        let scale = SavedViewDisplayScale(
            displayUnit: displayUnit,
            minorTickMeters: minorTickMeters,
            majorTickMeters: majorTickMeters,
            visibleSpanMeters: visibleSpanMeters,
            scaleBarLengthMeters: scaleBarMeters
        )
        try scale.validate()
        return scale
    }

    private func rejectCustomRulerFieldsWithScalePreset() throws {
        let hasCustomRuler = displayUnit != nil
            || minorTickMeters != nil
            || majorTickMeters != nil
            || visibleSpanMeters != nil
        guard !hasCustomRuler else {
            throw ValidationError(
                "--scale-preset cannot be combined with custom ruler fields. Use --scale-bar-meters only for a scale-bar override."
            )
        }
    }

    private func radians(fromDegrees degrees: Double) -> Double {
        degrees * Double.pi / 180.0
    }
}

private enum CLISavedViewProjectionMode: String, ExpressibleByArgument {
    case orthographic
    case perspective
}

private enum CLISavedViewIDParser {
    static func id(_ value: String) throws -> SavedViewID {
        guard let uuid = UUID(uuidString: value) else {
            throw ValidationError("Saved view ID must be a UUID.")
        }
        return SavedViewID(uuid)
    }

    static func optionalID(_ value: String?) throws -> SavedViewID? {
        guard let value else {
            return nil
        }
        return try id(value)
    }
}
