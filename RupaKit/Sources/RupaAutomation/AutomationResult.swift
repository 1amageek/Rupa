import Foundation
import RupaCore

public struct AutomationResult: Codable, Equatable, Sendable {
    public var message: String
    public var commandName: String?
    public var generation: DocumentGeneration
    public var didMutate: Bool
    public var diagnostics: [EditorDiagnostic]
    public var primaryFeatureID: FeatureID?
    public var createdFeatureIDs: [FeatureID]
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
    public var savedViews: [SavedView]?
    public var savedViewID: SavedViewID?
    public var sectionAnalysis: SectionAnalysisResult?
    public var sectionClippingPlan: SectionAnalysisClippingPlan?

    public init(
        message: String,
        commandName: String? = nil,
        generation: DocumentGeneration = DocumentGeneration(),
        didMutate: Bool = false,
        diagnostics: [EditorDiagnostic] = [],
        primaryFeatureID: FeatureID? = nil,
        createdFeatureIDs: [FeatureID] = [],
        curveRebuildReport: CurveRebuildReport? = nil,
        addedSelectionDimensionID: SelectionDimensionID? = nil,
        workspaceScale: WorkspaceScaleSnapshot? = nil,
        workspaceInteractionScale: WorkspaceInteractionScaleSnapshot? = nil,
        workspaceBounds: MeasurementResult.Bounds? = nil,
        workspacePrecision: WorkspacePrecisionReport? = nil,
        workspaceScaleRecommendation: WorkspaceScaleRecommendation? = nil,
        workspaceScalePresetOptions: [WorkspaceScalePresetProfile]? = nil,
        viewportGridSettings: ViewportGridSettings? = nil,
        viewportGridScale: ViewportGridScaleSnapshot? = nil,
        savedViews: [SavedView]? = nil,
        savedViewID: SavedViewID? = nil,
        sectionAnalysis: SectionAnalysisResult? = nil,
        sectionClippingPlan: SectionAnalysisClippingPlan? = nil
    ) {
        self.message = message
        self.commandName = commandName
        self.generation = generation
        self.didMutate = didMutate
        self.diagnostics = diagnostics
        self.primaryFeatureID = primaryFeatureID ?? createdFeatureIDs.first
        self.createdFeatureIDs = createdFeatureIDs
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
        self.savedViews = savedViews
        self.savedViewID = savedViewID
        self.sectionAnalysis = sectionAnalysis
        self.sectionClippingPlan = sectionClippingPlan
    }
}

extension AutomationResult {
    private enum CodingKeys: String, CodingKey {
        case message
        case commandName
        case generation
        case didMutate
        case diagnostics
        case primaryFeatureID
        case createdFeatureIDs
        case curveRebuildReport
        case addedSelectionDimensionID
        case workspaceScale
        case workspaceInteractionScale
        case workspaceBounds
        case workspacePrecision
        case workspaceScaleRecommendation
        case workspaceScalePresetOptions
        case viewportGridSettings
        case viewportGridScale
        case savedViews
        case savedViewID
        case sectionAnalysis
        case sectionClippingPlan
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdFeatureIDs = try container.decodeIfPresent(
            [FeatureID].self,
            forKey: .createdFeatureIDs
        ) ?? []
        let primaryFeatureID = try container.decodeIfPresent(
            FeatureID.self,
            forKey: .primaryFeatureID
        ) ?? createdFeatureIDs.first

        self.init(
            message: try container.decode(String.self, forKey: .message),
            commandName: try container.decodeIfPresent(String.self, forKey: .commandName),
            generation: try container.decodeIfPresent(
                DocumentGeneration.self,
                forKey: .generation
            ) ?? DocumentGeneration(),
            didMutate: try container.decodeIfPresent(Bool.self, forKey: .didMutate) ?? false,
            diagnostics: try container.decodeIfPresent(
                [EditorDiagnostic].self,
                forKey: .diagnostics
            ) ?? [],
            primaryFeatureID: primaryFeatureID,
            createdFeatureIDs: createdFeatureIDs,
            curveRebuildReport: try container.decodeIfPresent(
                CurveRebuildReport.self,
                forKey: .curveRebuildReport
            ),
            addedSelectionDimensionID: try container.decodeIfPresent(
                SelectionDimensionID.self,
                forKey: .addedSelectionDimensionID
            ),
            workspaceScale: try container.decodeIfPresent(
                WorkspaceScaleSnapshot.self,
                forKey: .workspaceScale
            ),
            workspaceInteractionScale: try container.decodeIfPresent(
                WorkspaceInteractionScaleSnapshot.self,
                forKey: .workspaceInteractionScale
            ),
            workspaceBounds: try container.decodeIfPresent(
                MeasurementResult.Bounds.self,
                forKey: .workspaceBounds
            ),
            workspacePrecision: try container.decodeIfPresent(
                WorkspacePrecisionReport.self,
                forKey: .workspacePrecision
            ),
            workspaceScaleRecommendation: try container.decodeIfPresent(
                WorkspaceScaleRecommendation.self,
                forKey: .workspaceScaleRecommendation
            ),
            workspaceScalePresetOptions: try container.decodeIfPresent(
                [WorkspaceScalePresetProfile].self,
                forKey: .workspaceScalePresetOptions
            ),
            viewportGridSettings: try container.decodeIfPresent(
                ViewportGridSettings.self,
                forKey: .viewportGridSettings
            ),
            viewportGridScale: try container.decodeIfPresent(
                ViewportGridScaleSnapshot.self,
                forKey: .viewportGridScale
            ),
            savedViews: try container.decodeIfPresent([SavedView].self, forKey: .savedViews),
            savedViewID: try container.decodeIfPresent(SavedViewID.self, forKey: .savedViewID),
            sectionAnalysis: try container.decodeIfPresent(
                SectionAnalysisResult.self,
                forKey: .sectionAnalysis
            ),
            sectionClippingPlan: try container.decodeIfPresent(
                SectionAnalysisClippingPlan.self,
                forKey: .sectionClippingPlan
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(commandName, forKey: .commandName)
        try container.encode(generation, forKey: .generation)
        try container.encode(didMutate, forKey: .didMutate)
        try container.encode(diagnostics, forKey: .diagnostics)
        try container.encodeIfPresent(primaryFeatureID, forKey: .primaryFeatureID)
        try container.encode(createdFeatureIDs, forKey: .createdFeatureIDs)
        try container.encodeIfPresent(curveRebuildReport, forKey: .curveRebuildReport)
        try container.encodeIfPresent(
            addedSelectionDimensionID,
            forKey: .addedSelectionDimensionID
        )
        try container.encodeIfPresent(workspaceScale, forKey: .workspaceScale)
        try container.encodeIfPresent(
            workspaceInteractionScale,
            forKey: .workspaceInteractionScale
        )
        try container.encodeIfPresent(workspaceBounds, forKey: .workspaceBounds)
        try container.encodeIfPresent(workspacePrecision, forKey: .workspacePrecision)
        try container.encodeIfPresent(
            workspaceScaleRecommendation,
            forKey: .workspaceScaleRecommendation
        )
        try container.encodeIfPresent(
            workspaceScalePresetOptions,
            forKey: .workspaceScalePresetOptions
        )
        try container.encodeIfPresent(viewportGridSettings, forKey: .viewportGridSettings)
        try container.encodeIfPresent(viewportGridScale, forKey: .viewportGridScale)
        try container.encodeIfPresent(savedViews, forKey: .savedViews)
        try container.encodeIfPresent(savedViewID, forKey: .savedViewID)
        try container.encodeIfPresent(sectionAnalysis, forKey: .sectionAnalysis)
        try container.encodeIfPresent(sectionClippingPlan, forKey: .sectionClippingPlan)
    }
}
