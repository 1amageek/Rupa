import ArgumentParser
import RupaAutomation

public struct SketchCurvatureDisplayCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "curvature-display",
        abstract: "Set or toggle source curve curvature-comb display."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Flag(help: "Show curvature combs for the selected source curve.")
    public var show: Bool = false

    @Flag(help: "Hide curvature combs for the selected source curve.")
    public var hide: Bool = false

    @Option(parsing: .unconditional, help: "Positive curvature comb scale.")
    public var combScale: Double?

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .setCurveCurvatureDisplay(
                target: selection.decodedTarget(),
                isVisible: try visibility(),
                combScale: combScale
            )
        )
    }

    private func visibility() throws -> Bool? {
        guard show == false || hide == false else {
            throw ValidationError("Provide at most one of --show or --hide.")
        }
        if show {
            return true
        }
        if hide {
            return false
        }
        return nil
    }
}

public struct SketchPointDisplayCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "point-display",
        abstract: "Set or toggle source curve point display."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Flag(help: "Show points for the selected source curve.")
    public var show: Bool = false

    @Flag(help: "Hide points for the selected source curve.")
    public var hide: Bool = false

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .setPointDisplay(
                target: selection.decodedTarget(),
                isVisible: try visibility()
            )
        )
    }

    private func visibility() throws -> Bool? {
        guard show == false || hide == false else {
            throw ValidationError("Provide at most one of --show or --hide.")
        }
        if show {
            return true
        }
        if hide {
            return false
        }
        return nil
    }
}
