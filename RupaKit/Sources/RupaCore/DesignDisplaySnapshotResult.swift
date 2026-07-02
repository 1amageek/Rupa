import RupaCoreTypes
public struct DesignDisplaySnapshotResult: Codable, Equatable, Sendable {
    public var generation: DocumentGeneration
    public var dirty: Bool
    public var workspaceScale: WorkspaceScaleSnapshot
    public var workspaceInteractionScale: WorkspaceInteractionScaleSnapshot
    public var viewportGridSettings: ViewportGridSettings
    public var workspaceBounds: MeasurementResult.Bounds?
    public var workspacePrecision: WorkspacePrecisionReport?
    public var workspaceScaleRecommendation: WorkspaceScaleRecommendation?
    public var workspaceScalePresetOptions: [WorkspaceScalePresetProfile]
    public var sketches: [SketchDisplaySnapshot]
    public var extrudes: [ExtrudeDisplaySnapshot]
    public var straightPrismSweeps: [StraightPrismSweepDisplaySnapshot]
    public var bodies: [BodyDisplaySnapshot]
    public var componentDefinitions: [ComponentDefinitionDisplaySnapshot]
    public var componentInstances: [ComponentInstanceDisplaySnapshot]
    public var patternArrays: [PatternArrayDisplaySnapshot]

    public init(
        generation: DocumentGeneration,
        dirty: Bool,
        workspaceScale: WorkspaceScaleSnapshot = WorkspaceScaleSnapshot(ruler: .standard(for: .millimeter)),
        workspaceInteractionScale: WorkspaceInteractionScaleSnapshot = WorkspaceInteractionScaleSnapshot(ruler: .standard(for: .millimeter)),
        viewportGridSettings: ViewportGridSettings = .standard,
        workspaceBounds: MeasurementResult.Bounds? = nil,
        workspacePrecision: WorkspacePrecisionReport? = nil,
        workspaceScaleRecommendation: WorkspaceScaleRecommendation? = nil,
        workspaceScalePresetOptions: [WorkspaceScalePresetProfile] = WorkspaceScalePreset
            .allCases
            .map(\.profile),
        sketches: [SketchDisplaySnapshot],
        extrudes: [ExtrudeDisplaySnapshot],
        straightPrismSweeps: [StraightPrismSweepDisplaySnapshot],
        bodies: [BodyDisplaySnapshot],
        componentDefinitions: [ComponentDefinitionDisplaySnapshot] = [],
        componentInstances: [ComponentInstanceDisplaySnapshot] = [],
        patternArrays: [PatternArrayDisplaySnapshot] = []
    ) {
        self.generation = generation
        self.dirty = dirty
        self.workspaceScale = workspaceScale
        self.workspaceInteractionScale = workspaceInteractionScale
        self.viewportGridSettings = viewportGridSettings
        self.workspaceBounds = workspaceBounds
        self.workspacePrecision = workspacePrecision
        self.workspaceScaleRecommendation = workspaceScaleRecommendation
        self.workspaceScalePresetOptions = workspaceScalePresetOptions
        self.sketches = sketches
        self.extrudes = extrudes
        self.straightPrismSweeps = straightPrismSweeps
        self.bodies = bodies
        self.componentDefinitions = componentDefinitions
        self.componentInstances = componentInstances
        self.patternArrays = patternArrays
    }

    private enum CodingKeys: String, CodingKey {
        case generation
        case dirty
        case workspaceScale
        case workspaceInteractionScale
        case viewportGridSettings
        case workspaceBounds
        case workspacePrecision
        case workspaceScaleRecommendation
        case workspaceScalePresetOptions
        case sketches
        case extrudes
        case straightPrismSweeps
        case bodies
        case componentDefinitions
        case componentInstances
        case patternArrays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let workspaceScale = try container.decode(
            WorkspaceScaleSnapshot.self,
            forKey: .workspaceScale
        )
        self.init(
            generation: try container.decode(DocumentGeneration.self, forKey: .generation),
            dirty: try container.decode(Bool.self, forKey: .dirty),
            workspaceScale: workspaceScale,
            workspaceInteractionScale: try container.decodeIfPresent(
                WorkspaceInteractionScaleSnapshot.self,
                forKey: .workspaceInteractionScale
            ) ?? WorkspaceInteractionScaleSnapshot(
                defaults: WorkspaceInteractionScaleDefaults(
                    ruler: RulerConfiguration(
                        displayUnit: workspaceScale.displayUnit,
                        minorTickMeters: workspaceScale.minorTickMeters,
                        majorTickMeters: workspaceScale.majorTickMeters,
                        visibleSpanMeters: workspaceScale.visibleSpanMeters
                    )
                ),
                displayUnit: workspaceScale.displayUnit
            ),
            viewportGridSettings: try container.decode(
                ViewportGridSettings.self,
                forKey: .viewportGridSettings
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
            ) ?? WorkspaceScalePreset.allCases.map(\.profile),
            sketches: try container.decode([SketchDisplaySnapshot].self, forKey: .sketches),
            extrudes: try container.decode([ExtrudeDisplaySnapshot].self, forKey: .extrudes),
            straightPrismSweeps: try container.decode(
                [StraightPrismSweepDisplaySnapshot].self,
                forKey: .straightPrismSweeps
            ),
            bodies: try container.decode([BodyDisplaySnapshot].self, forKey: .bodies),
            componentDefinitions: try container.decodeIfPresent(
                [ComponentDefinitionDisplaySnapshot].self,
                forKey: .componentDefinitions
            ) ?? [],
            componentInstances: try container.decodeIfPresent(
                [ComponentInstanceDisplaySnapshot].self,
                forKey: .componentInstances
            ) ?? [],
            patternArrays: try container.decodeIfPresent(
                [PatternArrayDisplaySnapshot].self,
                forKey: .patternArrays
            ) ?? []
        )
    }
}
