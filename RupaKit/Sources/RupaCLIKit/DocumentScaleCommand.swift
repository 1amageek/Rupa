import ArgumentParser
import RupaAutomation
import RupaCore
import SwiftCAD

extension WorkspaceScalePreset: ExpressibleByArgument {}
extension ViewportGridVisualSpacingMode: ExpressibleByArgument {}

public struct DescribeDocumentCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "describe",
        abstract: "Describe the current document settings, including workspace scale."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .describeDocument
        )
    }
}

public struct SetDisplayUnitCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-display-unit",
        abstract: "Set the document display unit and its standard workspace ruler."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Argument(help: "Display unit: micrometer, millimeter, centimeter, meter, kilometer, inch, or foot.")
    public var unit: LengthDisplayUnit

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .setDisplayUnit(unit)
        )
    }
}

public struct SetWorkspaceScalePresetCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-scale-preset",
        abstract: "Apply a workspace scale preset from micro fabrication through regional planning."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Argument(help: "Workspace scale preset.")
    public var preset: WorkspaceScalePreset

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .setWorkspaceScalePreset(preset)
        )
    }
}

public struct FitWorkspaceScaleCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "fit-workspace-scale",
        abstract: "Apply the recommended workspace scale preset for the current model size."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .fitWorkspaceScaleToModel
        )
    }
}

public struct RebaseWorkspaceOriginCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rebase-origin",
        abstract: "Translate authored CAD source coordinates by a meter-space vector."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    // `.unconditional` lets a negative translation (e.g. `--x -1000000000000`)
    // parse as the option value instead of being mistaken for another flag.
    // Rebasing a far-from-origin model toward the origin inherently needs
    // negative translations, so the space-separated negative form must work.
    @Option(parsing: .unconditional, help: "Translation along the world X axis in meters.")
    public var x: Double = 0.0

    @Option(parsing: .unconditional, help: "Translation along the world Y axis in meters.")
    public var y: Double = 0.0

    @Option(parsing: .unconditional, help: "Translation along the world Z axis in meters.")
    public var z: Double = 0.0

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .rebaseWorkspaceOrigin(
                translation: Vector3D(x: x, y: y, z: z)
            )
        )
    }
}

public struct SetViewportGridCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-grid",
        abstract: "Set viewport grid display behavior without changing snap precision."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Argument(help: "Viewport grid visual spacing mode: adaptive or fixed.")
    public var visualSpacingMode: ViewportGridVisualSpacingMode

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .setViewportGridSettings(
                ViewportGridSettings(visualSpacingMode: visualSpacingMode)
            )
        )
    }
}

public struct SetRulerConfigurationCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-ruler",
        abstract: "Set the document display unit, ruler tick spacing, and visible workspace span."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Display unit: micrometer, millimeter, centimeter, meter, kilometer, inch, or foot.")
    public var displayUnit: LengthDisplayUnit

    @Option(help: "Minor ruler tick in meters.")
    public var minorTickMeters: Double

    @Option(help: "Major ruler tick in meters.")
    public var majorTickMeters: Double

    @Option(help: "Visible workspace span in meters.")
    public var visibleSpanMeters: Double

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .setRulerConfiguration(
                RulerConfiguration(
                    displayUnit: displayUnit,
                    minorTickMeters: minorTickMeters,
                    majorTickMeters: majorTickMeters,
                    visibleSpanMeters: visibleSpanMeters
                )
            )
        )
    }
}
