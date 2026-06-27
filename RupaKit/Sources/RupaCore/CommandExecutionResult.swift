import Foundation
import SwiftCAD
import RupaCoreTypes

public struct CommandExecutionResult: Equatable, Sendable {
    public var commandName: String
    public var generation: DocumentGeneration
    public var didMutate: Bool
    public var diagnostics: [EditorDiagnostic]
    public var curveRebuildReport: CurveRebuildReport?
    public var addedSelectionDimensionID: SelectionDimensionID?

    public init(
        commandName: String,
        generation: DocumentGeneration,
        didMutate: Bool,
        diagnostics: [EditorDiagnostic],
        curveRebuildReport: CurveRebuildReport? = nil,
        addedSelectionDimensionID: SelectionDimensionID? = nil
    ) {
        self.commandName = commandName
        self.generation = generation
        self.didMutate = didMutate
        self.diagnostics = diagnostics
        self.curveRebuildReport = curveRebuildReport
        self.addedSelectionDimensionID = addedSelectionDimensionID
    }
}
