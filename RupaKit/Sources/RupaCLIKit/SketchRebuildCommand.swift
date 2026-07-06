import ArgumentParser
import Foundation
import RupaAutomation
import RupaCore

public struct SketchRebuildCommand: ParsableCommand {
    public enum Method: String, ExpressibleByArgument, Sendable {
        case points
        case refit
        case explicitControl = "explicit-control"
    }

    public static let configuration = CommandConfiguration(
        commandName: "rebuild",
        abstract: "Rebuild a supported source sketch curve."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Option(help: "Rebuild method: points, refit, or explicit-control.")
    public var method: Method

    @Option(parsing: .unconditional, help: "Requested control point count for the points method.")
    public var controlPointCount: Int?

    @Option(parsing: .unconditional, help: "Refit tolerance numeric literal.")
    public var tolerance: Double?

    @Option(help: "Length unit for the refit tolerance. Defaults to the document display unit.")
    public var unit: String?

    @Flag(help: "Keep sharp internal corners during refit when supported.")
    public var keepsCorners: Bool = false

    @Option(parsing: .unconditional, help: "Requested degree for explicit-control rebuild.")
    public var degree: Int?

    @Option(parsing: .unconditional, help: "Requested span count for explicit-control rebuild.")
    public var spanCount: Int?

    @Option(parsing: .unconditional, help: "Explicit-control rebuild weight.")
    public var weight: Double?

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(document: document) { sessionID in
            return .rebuildSketchCurve(
                target: try selection.decodedTarget(),
                options: try rebuildOptions(sessionID: sessionID)
            )
        }
    }

    private func rebuildOptions(sessionID: UUID?) throws -> CurveRebuildOptions {
        switch method {
        case .points:
            guard let controlPointCount else {
                throw ValidationError("Points rebuild requires --control-point-count.")
            }
            return .points(controlPointCount: controlPointCount)
        case .refit:
            guard let tolerance else {
                throw ValidationError("Refit rebuild requires --tolerance.")
            }
            let lengthUnit = try CLIAutomationCommandRunner.lengthUnit(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return .refit(
                tolerance: try CLIAutomationCommandRunner.lengthExpression(
                    value: tolerance,
                    unit: lengthUnit,
                    valueName: "Refit tolerance"
                ),
                keepsCorners: keepsCorners
            )
        case .explicitControl:
            guard let degree else {
                throw ValidationError("Explicit-control rebuild requires --degree.")
            }
            guard let spanCount else {
                throw ValidationError("Explicit-control rebuild requires --span-count.")
            }
            guard let weight else {
                throw ValidationError("Explicit-control rebuild requires --weight.")
            }
            return .explicitControl(
                degree: degree,
                spanCount: spanCount,
                weight: weight
            )
        }
    }
}
