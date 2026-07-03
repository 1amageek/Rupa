import Foundation
import RupaCore

public struct AutomationResult: Codable, Equatable, Sendable {
    public var message: String
    public var commandName: String?
    public var generation: DocumentGeneration
    public var didMutate: Bool
    public var diagnostics: [EditorDiagnostic]
    public var curveRebuildReport: CurveRebuildReport?
    public var addedSelectionDimensionID: SelectionDimensionID?
    public var workspaceScale: WorkspaceScaleSnapshot?
    public var workspaceInteractionScale: WorkspaceInteractionScaleSnapshot?
    public var workspaceBounds: MeasurementResult.Bounds?
    public var workspacePrecision: WorkspacePrecisionReport?
    public var workspaceScaleRecommendation: WorkspaceScaleRecommendation?
    public var workspaceScalePresetOptions: [WorkspaceScalePresetProfile]?
    public var viewportGridSettings: ViewportGridSettings?
    public var viewportGridScale: ViewportGridScaleSnapshot?

    public init(
        message: String,
        commandName: String? = nil,
        generation: DocumentGeneration = DocumentGeneration(),
        didMutate: Bool = false,
        diagnostics: [EditorDiagnostic] = [],
        curveRebuildReport: CurveRebuildReport? = nil,
        addedSelectionDimensionID: SelectionDimensionID? = nil,
        workspaceScale: WorkspaceScaleSnapshot? = nil,
        workspaceInteractionScale: WorkspaceInteractionScaleSnapshot? = nil,
        workspaceBounds: MeasurementResult.Bounds? = nil,
        workspacePrecision: WorkspacePrecisionReport? = nil,
        workspaceScaleRecommendation: WorkspaceScaleRecommendation? = nil,
        workspaceScalePresetOptions: [WorkspaceScalePresetProfile]? = nil,
        viewportGridSettings: ViewportGridSettings? = nil,
        viewportGridScale: ViewportGridScaleSnapshot? = nil
    ) {
        self.message = message
        self.commandName = commandName
        self.generation = generation
        self.didMutate = didMutate
        self.diagnostics = diagnostics
        self.curveRebuildReport = curveRebuildReport
        self.addedSelectionDimensionID = addedSelectionDimensionID
        self.workspaceScale = workspaceScale
        self.workspaceInteractionScale = workspaceInteractionScale
        self.workspaceBounds = workspaceBounds
        self.workspacePrecision = workspacePrecision
        self.workspaceScaleRecommendation = workspaceScaleRecommendation
        self.workspaceScalePresetOptions = workspaceScalePresetOptions
        self.viewportGridSettings = viewportGridSettings
        self.viewportGridScale = viewportGridScale
    }
}
