import CoreGraphics
import Foundation
import RupaCore
import RupaGeometry
import RupaViewportScene
import SwiftCAD
import SwiftUI
import simd

/// Semantic owners for the world-space overlay routes that are being moved to
/// RealityKit.  The producer uses this value only for completeness checks; it
/// does not own selection, CAD, or persistence state.
enum ViewportSpatialOverlayFamily: String, CaseIterable, Hashable, Sendable {
    case grid
    case axes
    case body
    case curve
    case sketch
    case meshSelection
    case analysis
    case section
    case snapReference
    case placement
    case construction
    case transform
    case pattern
    case measurement

    /// Geometry derived from evaluated model items follows the same section
    /// clipping root as the surface. Guides and annotations remain world
    /// siblings so a construction/reference aid is not accidentally clipped.
    var attachment: RealityViewportSpatialBatch.Attachment {
        switch self {
        case .body, .curve, .sketch, .meshSelection, .analysis, .transform:
            .sectionedGeometry
        case .grid, .axes, .section, .snapReference, .placement,
             .construction, .pattern, .measurement:
            .world
        }
    }
}

/// Camera-independent immutable input for one spatial-overlay revision.
///
/// `Viewport` owns construction of this value from source geometry and
/// transient interaction snapshots.  The RealityKit cache may retain and
/// prepare it off the main actor; a camera update never recreates this value.
struct ViewportSpatialOverlayInput: Sendable {
    struct Mesh: Sendable {
        let family: ViewportSpatialOverlayFamily
        let value: RealityViewportSpatialBatch.Mesh

        init(family: ViewportSpatialOverlayFamily, value: RealityViewportSpatialBatch.Mesh) {
            self.family = family
            var value = value
            value.attachment = family.attachment
            self.value = value
        }
    }

    struct Path: Sendable {
        let family: ViewportSpatialOverlayFamily
        let value: RealityViewportSpatialBatch.PlanarPath

        init(family: ViewportSpatialOverlayFamily, value: RealityViewportSpatialBatch.PlanarPath) {
            self.family = family
            var value = value
            value.attachment = family.attachment
            self.value = value
        }
    }

    struct Label: Sendable {
        let family: ViewportSpatialOverlayFamily
        let value: RealityViewportSpatialBatch.Label

        init(family: ViewportSpatialOverlayFamily, value: RealityViewportSpatialBatch.Label) {
            self.family = family
            var value = value
            value.attachment = family.attachment
            self.value = value
        }
    }

    struct Marker: Sendable {
        let family: ViewportSpatialOverlayFamily
        let value: RealityViewportSpatialBatch.Marker

        init(family: ViewportSpatialOverlayFamily, value: RealityViewportSpatialBatch.Marker) {
            self.family = family
            var value = value
            value.attachment = family.attachment
            self.value = value
        }
    }

    struct CameraLine: Sendable {
        let family: ViewportSpatialOverlayFamily
        let value: RealityViewportSpatialBatch.CameraLine

        init(family: ViewportSpatialOverlayFamily, value: RealityViewportSpatialBatch.CameraLine) {
            self.family = family
            var value = value
            value.attachment = family.attachment
            self.value = value
        }
    }

    struct CameraPath: Sendable {
        let family: ViewportSpatialOverlayFamily
        let value: RealityViewportSpatialBatch.CameraPath

        init(family: ViewportSpatialOverlayFamily, value: RealityViewportSpatialBatch.CameraPath) {
            self.family = family
            var value = value
            value.attachment = family.attachment
            self.value = value
        }
    }

    let activeFamilies: Set<ViewportSpatialOverlayFamily>
    let meshes: [Mesh]
    let paths: [Path]
    let labels: [Label]
    let markers: [Marker]
    let cameraLines: [CameraLine]
    let cameraPaths: [CameraPath]
    let interactionRecords: [ViewportSpatialInteractionRecord]
    let boundsRuler: ViewportMeasurementBoundsRulerInput?
    let gridPlacement: RealityViewportSpatialBatch.GridPlacement?
    /// Requests the native camera-owned grid frame. Grid geometry and labels
    /// are intentionally not materialized in this immutable source batch.
    let includesGrid: Bool
    let includesAxes: Bool
    let renderOrigin: Point3D
    let retainedSurfaceByteCount: Int
    let topologyRevision: UInt64

    init(
        activeFamilies: Set<ViewportSpatialOverlayFamily> = [],
        meshes: [Mesh] = [],
        paths: [Path] = [],
        labels: [Label] = [],
        markers: [Marker] = [],
        cameraLines: [CameraLine] = [],
        cameraPaths: [CameraPath] = [],
        interactionRecords: [ViewportSpatialInteractionRecord] = [],
        boundsRuler: ViewportMeasurementBoundsRulerInput? = nil,
        gridPlacement: RealityViewportSpatialBatch.GridPlacement? = nil,
        includesGrid: Bool = false,
        includesAxes: Bool = false,
        renderOrigin: Point3D,
        retainedSurfaceByteCount: Int,
        topologyRevision: UInt64
    ) {
        self.activeFamilies = activeFamilies
        self.meshes = meshes
        self.paths = paths
        self.labels = labels
        self.markers = markers
        self.cameraLines = cameraLines
        self.cameraPaths = cameraPaths
        self.interactionRecords = interactionRecords
        self.boundsRuler = boundsRuler
        self.gridPlacement = gridPlacement
        self.includesGrid = includesGrid
        self.includesAxes = includesAxes
        self.renderOrigin = renderOrigin
        self.retainedSurfaceByteCount = retainedSurfaceByteCount
        self.topologyRevision = topologyRevision
    }

    func replacing(
        renderOrigin: Point3D,
        retainedSurfaceByteCount: Int
    ) -> Self {
        Self(
            activeFamilies: activeFamilies,
            meshes: meshes,
            paths: paths,
            labels: labels,
            markers: markers,
            cameraLines: cameraLines,
            cameraPaths: cameraPaths,
            interactionRecords: interactionRecords,
            boundsRuler: boundsRuler,
            gridPlacement: gridPlacement,
            includesGrid: includesGrid,
            includesAxes: includesAxes,
            renderOrigin: renderOrigin,
            retainedSurfaceByteCount: retainedSurfaceByteCount,
            topologyRevision: topologyRevision
        )
    }
}

/// Camera-independent source values retained for one spatial-overlay revision.
///
/// The scene and interaction values are copied while `Viewport` is isolated to
/// the main actor.  The producer consumes this value off the main actor and
/// performs world-geometry traversal there.  No `Viewport`, `ViewportLayout`,
/// camera, SwiftUI state, or project authority is captured by the worker.
struct ViewportSpatialOverlaySemanticSnapshot: Sendable {
    struct Interaction: Sendable {
        struct SketchRegion: Sendable {
            let featureID: FeatureID
            let componentID: SelectionComponentID
        }

        let selectedFeatureIDs: Set<FeatureID>
        let selectedSceneNodeIDs: Set<SceneNodeID>
        let hoveredFeatureIDs: Set<FeatureID>
        let hoveredSceneNodeIDs: Set<SceneNodeID>
        let selectedTargets: [SelectionTarget]
        let previewTargets: [SelectionTarget]
        let objectSelectionTargets: [SelectionTarget]
        let previewObjectSelectionTargets: [SelectionTarget]
        let selectedReferences: [SelectionReference]
        let hoveredReference: SelectionReference?
        let hoveredTarget: SelectionTarget?
        let selectedSketchEntities: [ViewportSketchEntitySelectionTarget]
        let previewSketchEntities: [ViewportSketchEntitySelectionTarget]
        let hoveredSketchEntity: ViewportSketchEntitySelectionTarget?
        let selectedSketchRegions: [SketchRegion]
        let previewSketchRegions: [SketchRegion]
        let hoveredSketchRegion: SketchRegion?

        init(
            selectedFeatureIDs: Set<FeatureID>,
            selectedSceneNodeIDs: Set<SceneNodeID>,
            hoveredFeatureIDs: Set<FeatureID>,
            hoveredSceneNodeIDs: Set<SceneNodeID>,
            selectedTargets: [SelectionTarget] = [],
            previewTargets: [SelectionTarget] = [],
            objectSelectionTargets: [SelectionTarget] = [],
            previewObjectSelectionTargets: [SelectionTarget] = [],
            selectedReferences: [SelectionReference] = [],
            hoveredReference: SelectionReference? = nil,
            hoveredTarget: SelectionTarget? = nil,
            selectedSketchEntities: [ViewportSketchEntitySelectionTarget],
            previewSketchEntities: [ViewportSketchEntitySelectionTarget],
            hoveredSketchEntity: ViewportSketchEntitySelectionTarget?,
            selectedSketchRegions: [SketchRegion],
            previewSketchRegions: [SketchRegion],
            hoveredSketchRegion: SketchRegion?
        ) {
            self.selectedFeatureIDs = selectedFeatureIDs
            self.selectedSceneNodeIDs = selectedSceneNodeIDs
            self.hoveredFeatureIDs = hoveredFeatureIDs
            self.hoveredSceneNodeIDs = hoveredSceneNodeIDs
            self.selectedTargets = selectedTargets
            self.previewTargets = previewTargets
            self.objectSelectionTargets = objectSelectionTargets
            self.previewObjectSelectionTargets = previewObjectSelectionTargets
            self.selectedReferences = selectedReferences
            self.hoveredReference = hoveredReference
            self.hoveredTarget = hoveredTarget
            self.selectedSketchEntities = selectedSketchEntities
            self.previewSketchEntities = previewSketchEntities
            self.hoveredSketchEntity = hoveredSketchEntity
            self.selectedSketchRegions = selectedSketchRegions
            self.previewSketchRegions = previewSketchRegions
            self.hoveredSketchRegion = hoveredSketchRegion
        }
    }

    struct WorldContext: Sendable {
        let modelBounds: CGRect
    }

    struct SnapReference: Sendable {
        enum Context: Sendable {
            case passiveHover
            case creationDrag
        }

        let result: SnapResolutionResult?
        let referenceLineAnchors: [SketchReferenceLineAnchor]
        let modelBounds: CGRect
        let context: Context
    }

    struct Placement: Sendable {
        let highlight: ViewportPlacementHighlight
        let defaults: WorkspaceScaleDefaults
    }

    struct DragPreview: Sendable {
        let kind: ViewportCanvasDragPreviewKind
        let drag: ViewportModelDrag
        let document: DesignDocument
        let ruler: RulerConfiguration
        let snapOptions: SnapResolutionOptions?
        let axisConstraint: SketchAxisConstraint?
        /// The evaluation the publisher already holds for `document`, stated so
        /// the producer resolves this drag against it instead of asking the
        /// kernel to evaluate the whole document twice per pointer move. A
        /// publisher holding none for the document it passes states none.
        let currentEvaluation: DocumentEvaluationContext?
        let currentGeneration: DocumentGeneration?
    }

    struct Measurement: Sendable {
        let start: Point3D?
        let end: Point3D?
        let label: String?
        let boundsRuler: ViewportMeasurementBoundsRulerInput?
    }

    /// Raw pattern inputs captured at the MainActor boundary.  Preview
    /// sorting, source-index traversal, curve-path sampling, and output
    /// planning are intentionally performed by the producer worker.
    typealias PatternSource = ViewportPatternAffordanceSource.RawInput

    /// Raw analysis inputs captured at the MainActor boundary.  Overlay
    /// filtering and continuity edge mapping remain a worker-side operation.
    struct AnalysisSource: Sendable {
        let result: SurfaceAnalysisResult?
        let continuity: RupaCore.SurfaceContinuityResult?
        let scene: ViewportScene
        let selection: SelectionModel
        let document: DesignDocument
        let options: ViewportSurfaceAnalysisOptions
    }

    /// Raw section inputs captured at the MainActor boundary.  Contour limits
    /// and hatch conversion are evaluated by the producer worker.
    struct SectionSource: Sendable {
        let result: SectionAnalysisResult?
        let ruler: RulerConfiguration
    }


    struct Analysis: Sendable {
        struct Item: Sendable {
            let direction: SurfaceAnalysisResult.Direction
            let position: Point3D
            let normal: Vector3D
            let normalCurvature: Double
        }

        struct PrincipalDirectionItem: Sendable {
            let position: Point3D
            let minimumPrincipalDirection: Vector3D
            let maximumPrincipalDirection: Vector3D
            let minimumPrincipalCurvature: Double
            let maximumPrincipalCurvature: Double
        }

        struct BoundaryItem: Sendable {
            let role: SurfaceAnalysisResult.TrimBoundaryRole
            let points: [Point3D]
            let isClosed: Bool
        }

        struct ContinuityItem: Sendable {
            let start: Point3D
            let end: Point3D
            let continuity: RupaCore.SurfaceContinuityResult.ContinuityLevel
            let requiresCurvatureContinuitySolve: Bool
        }

        let items: [Item]
        let principalDirectionItems: [PrincipalDirectionItem]
        let boundaryItems: [BoundaryItem]
        let continuityItems: [ContinuityItem]
    }

    struct Section: Sendable {
        struct Plane: Sendable {
            let origin: Point3D
            let normalEnd: Point3D
            let corners: [Point3D]
        }

        struct Segment: Sendable {
            let start: Point3D
            let end: Point3D
        }

        struct Contour: Sendable {
            let points: [Point3D]
            let isClosed: Bool
        }

        struct Hatch: Sendable {
            let start: Point3D
            let end: Point3D
        }

        let plane: Plane?
        let segments: [Segment]
        let contours: [Contour]
        let hatches: [Hatch]
        let sourceSegmentCount: Int
        let omittedSegmentCount: Int
        let sourceContourCount: Int
        let omittedContourCount: Int
        let hasTruncatedSourcePayload: Bool
    }

    let scene: ViewportScene
    let interaction: Interaction
    let meshSelection: ViewportMeshSelectionOverlay?
    let sketchCurveSource: ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput?
    let surfaceTransformSource: ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput?
    let patternSource: PatternSource?
    let analysisSource: AnalysisSource?
    let sectionSource: SectionSource?
    let editedBodies: [FeatureID: ViewportObjectEditState]
    let bodyPreviewTransforms: [String: Transform3D]
    let world: WorldContext
    let snapReference: SnapReference?
    let placement: Placement?
    let dragPreview: DragPreview?
    let includesGrid: Bool
    let measurement: Measurement?
    let drawsLegacyBodies: Bool
    let drawsDragPreviewBodies: Bool

    init(
        scene: ViewportScene,
        interaction: Interaction,
        meshSelection: ViewportMeshSelectionOverlay? = nil,
        sketchCurveSource: ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput? = nil,
        surfaceTransformSource: ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput? = nil,
        patternSource: PatternSource? = nil,
        analysisSource: AnalysisSource? = nil,
        sectionSource: SectionSource? = nil,
        editedBodies: [FeatureID: ViewportObjectEditState],
        bodyPreviewTransforms: [String: Transform3D] = [:],
        world: WorldContext,
        snapReference: SnapReference? = nil,
        placement: Placement? = nil,
        dragPreview: DragPreview? = nil,
        includesGrid: Bool = false,
        measurement: Measurement?,
        drawsLegacyBodies: Bool,
        drawsDragPreviewBodies: Bool
    ) {
        self.scene = scene
        self.interaction = interaction
        self.meshSelection = meshSelection
        self.sketchCurveSource = sketchCurveSource
        self.surfaceTransformSource = surfaceTransformSource
        self.patternSource = patternSource
        self.analysisSource = analysisSource
        self.sectionSource = sectionSource
        self.editedBodies = editedBodies
        self.bodyPreviewTransforms = bodyPreviewTransforms
        self.world = world
        self.snapReference = snapReference
        self.placement = placement
        self.dragPreview = dragPreview
        self.includesGrid = includesGrid
        self.measurement = measurement
        self.drawsLegacyBodies = drawsLegacyBodies
        self.drawsDragPreviewBodies = drawsDragPreviewBodies
    }
}

/// Converts semantic overlay descriptors into the bounded RealityKit batch.
///
/// This is intentionally a value-only seam.  Its worker-side conversion may
/// traverse only the immutable source snapshot; it performs no camera query,
/// resource generation, or fallback rendering.  The complete input is
/// admitted by `RealityViewportSpatialBatch` before any native resource is
/// allocated.
enum ViewportSpatialOverlayProducer {
    typealias Output = (spatialBatch: RealityViewportSpatialBatch, interactionRecords: [ViewportSpatialInteractionRecord])

    /// Returns a worker-safe builder.  Scene/grid/measurement traversal occurs
    /// inside the closure, after the immutable snapshot has crossed the
    /// isolation boundary.  Camera-only callers retain this builder and do not
    /// invoke it again.
    static func makeBuilder(
        from snapshot: ViewportSpatialOverlaySemanticSnapshot,
        topologyRevision: UInt64
    ) -> @Sendable (Point3D, Int) throws -> Output {
        { renderOrigin, retainedSurfaceByteCount in
            let input = try makeInput(
                from: snapshot,
                renderOrigin: renderOrigin,
                retainedSurfaceByteCount: retainedSurfaceByteCount,
                topologyRevision: topologyRevision
            )
            return (try makeBatch(from: input), input.interactionRecords)
        }
    }

    static func makeInput(
        from snapshot: ViewportSpatialOverlaySemanticSnapshot,
        renderOrigin: Point3D,
        retainedSurfaceByteCount: Int,
        topologyRevision: UInt64
    ) throws -> ViewportSpatialOverlayInput {
        try Task.checkCancellation()
        guard renderOrigin.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "Semantic spatial snapshot received a non-finite render origin."
            )
        }
        var activeFamilies: Set<ViewportSpatialOverlayFamily> = []
        var meshes: [ViewportSpatialOverlayInput.Mesh] = []
        var paths: [ViewportSpatialOverlayInput.Path] = []
        var labels: [ViewportSpatialOverlayInput.Label] = []
        var markers: [ViewportSpatialOverlayInput.Marker] = []
        var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
        var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
        var interactionRecords: [ViewportSpatialInteractionRecord] = []
        var boundsRuler: ViewportMeasurementBoundsRulerInput?
        var gridPlacement: RealityViewportSpatialBatch.GridPlacement?
        let limits = MeshSourcePresentationPlanLimits.standard
        var admittedItems = 0
        var admittedPositions = 0
        var admittedVisits = 0
        func checkpoint(_ items: Int, _ positions: Int, _ visits: Int) throws {
            try Task.checkCancellation()
            let nextItems = admittedItems.addingReportingOverflow(items)
            let nextPositions = admittedPositions.addingReportingOverflow(positions)
            let nextVisits = admittedVisits.addingReportingOverflow(visits)
            guard items >= 0, positions >= 0, visits >= 0,
                  !nextItems.overflow, !nextPositions.overflow, !nextVisits.overflow,
                  nextItems.partialValue <= limits.maxItemCount,
                  nextPositions.partialValue <= limits.maxPositionCount,
                  nextVisits.partialValue <= limits.maxPositionCount else {
                throw RealityViewportSpatialBatch.exhausted()
            }
            admittedItems = nextItems.partialValue
            admittedPositions = nextPositions.partialValue
            admittedVisits = nextVisits.partialValue
        }
        let pattern = try snapshot.patternSource.flatMap {
            try makePatternAffordanceSource(from: $0, checkpoint: checkpoint)
        }
        let analysis = try materializeAnalysis(from: snapshot.analysisSource, checkpoint: checkpoint)
        let section = try materializeSection(from: snapshot.sectionSource, checkpoint: checkpoint)
        try Task.checkCancellation()
        try appendScene(
            snapshot,
            meshes: &meshes,
            paths: &paths,
            markers: &markers,
            cameraLines: &cameraLines,
            activeFamilies: &activeFamilies
        )
        try appendMeshSelection(
            snapshot,
            meshes: &meshes,
            markers: &markers,
            activeFamilies: &activeFamilies
        )
        if let source = snapshot.sketchCurveSource {
            try appendSketchCurveAffordances(
                from: source, meshes: &meshes, paths: &paths, labels: &labels,
                markers: &markers, cameraLines: &cameraLines, cameraPaths: &cameraPaths,
                interactionRecords: &interactionRecords, activeFamilies: &activeFamilies,
                checkpoint: checkpoint
            )
        }
        if let raw = snapshot.surfaceTransformSource,
           let source = try makeSurfaceTransformAffordanceSource(from: raw, interactionRecords: &interactionRecords, checkpoint: checkpoint) {
            try appendSurfaceTransformAffordances(
                from: source, checkpoint: checkpoint,
                meshes: &meshes, paths: &paths, labels: &labels, markers: &markers,
                cameraLines: &cameraLines, cameraPaths: &cameraPaths,
                interactionRecords: &interactionRecords, activeFamilies: &activeFamilies
            )
        }
        if let pattern {
            try appendPatternAffordances(
                pattern, meshes: &meshes, labels: &labels, markers: &markers,
                cameraLines: &cameraLines,
                cameraPaths: &cameraPaths,
                activeFamilies: &activeFamilies, interactionRecords: &interactionRecords,
                checkpoint: checkpoint
            )
        }
        try appendAnalysis(
            analysis,
            modelBounds: snapshot.world.modelBounds,
            meshes: &meshes,
            labels: &labels,
            activeFamilies: &activeFamilies
        )
        try appendSection(
            section,
            paths: &paths,
            meshes: &meshes,
            activeFamilies: &activeFamilies
        )
        activeFamilies.insert(.axes)
        try appendMeasurement(
            snapshot,
            meshes: &meshes,
            labels: &labels,
            markers: &markers,
            cameraLines: &cameraLines,
            boundsRuler: &boundsRuler,
            activeFamilies: &activeFamilies
        )
        try appendSnapReference(
            snapshot,
            paths: &paths,
            labels: &labels,
            markers: &markers,
            activeFamilies: &activeFamilies
        )
        try appendPlacement(
            snapshot,
            meshes: &meshes,
            gridPlacement: &gridPlacement,
            activeFamilies: &activeFamilies
        )
        try appendTransform(
            snapshot,
            meshes: &meshes,
            paths: &paths,
            markers: &markers,
            activeFamilies: &activeFamilies
        )
        try appendDragPreview(
            snapshot,
            meshes: &meshes,
            activeFamilies: &activeFamilies
        )
        return ViewportSpatialOverlayInput(
            activeFamilies: activeFamilies,
            meshes: meshes,
            paths: paths,
            labels: labels,
            markers: markers,
            cameraLines: cameraLines,
            cameraPaths: cameraPaths,
            interactionRecords: interactionRecords,
            boundsRuler: boundsRuler,
            gridPlacement: gridPlacement,
            includesGrid: snapshot.includesGrid,
            includesAxes: true,
            renderOrigin: renderOrigin,
            retainedSurfaceByteCount: retainedSurfaceByteCount,
            topologyRevision: topologyRevision
        )
    }

    static func makeBuilder(
        from input: ViewportSpatialOverlayInput
    ) -> @Sendable (Point3D, Int) throws -> Output {
        { renderOrigin, retainedSurfaceByteCount in
            let batch = try makeBatch(
                from: input.replacing(
                    renderOrigin: renderOrigin,
                    retainedSurfaceByteCount: retainedSurfaceByteCount
                )
            )
            return (batch, input.interactionRecords)
        }
    }

    static func makeBatch(
        from input: ViewportSpatialOverlayInput,
        limits: MeshSourcePresentationPlanLimits = .standard
    ) throws -> RealityViewportSpatialBatch {
        let descriptorCounts = counts(in: input)
        for family in input.activeFamilies {
            guard descriptorCounts[family, default: 0] > 0 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Spatial overlay family \(family.rawValue) has no native descriptor."
                )
            }
        }
        let hasDescriptor = !input.meshes.isEmpty
            || !input.paths.isEmpty
            || !input.labels.isEmpty
            || !input.markers.isEmpty
            || !input.cameraLines.isEmpty
            || !input.cameraPaths.isEmpty
            || input.gridPlacement != nil
            || input.includesAxes
        let hasBoundsRuler = input.boundsRuler != nil
        guard hasDescriptor || hasBoundsRuler || input.activeFamilies.isEmpty else {
            throw RealityViewportSpatialBatch.invalid(
                "An active spatial overlay revision cannot publish an empty batch."
            )
        }

        let boundsRulers = input.boundsRuler.map {
            RealityViewportSpatialBatch.BoundsRulers(
                input: $0,
                heightPoints: 9,
                color: measurementColor
            )
        }

        // Do not prefix, cap, or silently omit any family.  The batch performs
        // the shared item/position/triangle/byte admission and throws the
        // typed resource-exhaustion error for an over-budget complete input.
        return try RealityViewportSpatialBatch(
            meshes: input.meshes.map(\.value),
            paths: input.paths.map(\.value),
            labels: input.labels.map(\.value),
            markers: input.markers.map(\.value),
            cameraLines: input.cameraLines.map(\.value),
            cameraPaths: input.cameraPaths.map(\.value),
            boundsRulers: boundsRulers,
            includesGrid: input.includesGrid,
            includesAxes: input.includesAxes,
            gridPlacement: input.gridPlacement,
            handleCount: input.interactionRecords.count,
            retainedSemanticByteCount: try ViewportSpatialInteractionRecord.retainedByteCount(for: input.interactionRecords, limits: limits),
            renderOrigin: input.renderOrigin,
            retainedSurfaceByteCount: input.retainedSurfaceByteCount,
            limits: limits
        )
    }

    private static func appendScene(
        _ snapshot: ViewportSpatialOverlaySemanticSnapshot,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        paths: inout [ViewportSpatialOverlayInput.Path],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        cameraLines: inout [ViewportSpatialOverlayInput.CameraLine],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        let selectedFeatures = snapshot.interaction.selectedFeatureIDs
        let selectedNodes = snapshot.interaction.selectedSceneNodeIDs
        let hoveredFeatures = snapshot.interaction.hoveredFeatureIDs
        let hoveredNodes = snapshot.interaction.hoveredSceneNodeIDs
        let selectedBodyGroup = snapshot.scene.items.filter { item in
            guard case .body = item.kind else { return false }
            return isObjectItem(
                item,
                selectedFeatures: selectedFeatures,
                selectedNodes: selectedNodes
            )
        }.count > 1
        let suppressedSketchFeatures = Set(
            snapshot.scene.items.compactMap { item -> FeatureID? in
                guard case .body = item.kind,
                      isObjectItem(item, selectedFeatures: selectedFeatures, selectedNodes: selectedNodes)
                        || snapshot.editedBodies[item.featureID] != nil else {
                    return nil
                }
                return item.sourceFeatureID
            }
        )
        let selectedSketchEntities = snapshot.interaction.selectedSketchEntities
        let previewSketchEntities = snapshot.interaction.previewSketchEntities
        let hoveredSketchEntity = snapshot.interaction.hoveredSketchEntity
        let selectedSketchRegions = snapshot.interaction.selectedSketchRegions
        let previewSketchRegions = snapshot.interaction.previewSketchRegions
        let hoveredSketchRegion = snapshot.interaction.hoveredSketchRegion

        for item in snapshot.scene.items {
            switch item.kind {
            case .body(let component):
                let isSelected = isObjectItem(
                    item,
                    selectedFeatures: selectedFeatures,
                    selectedNodes: selectedNodes
                ) && !selectedBodyGroup
                let isHovered = hoveredFeatures.contains(item.featureID)
                    || item.sceneNodeID.map(hoveredNodes.contains) == true
                let shouldDrawBody = snapshot.drawsLegacyBodies
                    || snapshot.drawsDragPreviewBodies
                    || snapshot.bodyPreviewTransforms[item.id] != nil
                    || snapshot.editedBodies[item.featureID] != nil
                guard shouldDrawBody else { continue }
                let color = isSelected ? selectionColor : bodyColor
                // An edit state owns the preview shape while a drag is running.
                // The component's mesh describes the body before the drag, so
                // drawing it here would show the pre-drag solid instead of the
                // box the edit is moving.  The interaction state decides the
                // geometry; carrying a prepared mesh does not.
                if snapshot.editedBodies[item.featureID] == nil, let mesh = component.mesh {
                    guard !mesh.positions.isEmpty,
                          !mesh.indices.isEmpty,
                          mesh.indices.count.isMultiple(of: 3) else {
                        throw RealityViewportSpatialBatch.invalid(
                            "Body mesh has no complete triangle source."
                        )
                    }
                    let limits = MeshSourcePresentationPlanLimits.standard
                    guard mesh.positions.count <= limits.maxPositionCount,
                          mesh.indices.count / 3 <= limits.maxTriangleCount else {
                        throw MeshSourcePresentationRenderError(
                            code: .resourceExhausted,
                            message: "The complete body mesh exceeds viewport admission limits."
                        )
                    }
                    // Validate the complete source before creating the transformed
                    // output buffer.  One body owns one indexed descriptor; splitting
                    // every triangle would consume one native item per triangle.
                    for position in mesh.positions {
                        try Task.checkCancellation()
                        guard position.isFinite else {
                            throw RealityViewportSpatialBatch.invalid(
                                "Body mesh contains a non-finite source position."
                            )
                        }
                    }
                    for rawIndex in mesh.indices {
                        try Task.checkCancellation()
                        guard mesh.positions.indices.contains(Int(rawIndex)) else {
                            throw RealityViewportSpatialBatch.invalid(
                                "Body mesh references an absent vertex."
                            )
                        }
                    }
                    var transformedPositions: [Point3D] = []
                    transformedPositions.reserveCapacity(mesh.positions.count)
                    for position in mesh.positions {
                        try Task.checkCancellation()
                        var transformed = ViewportLayout.transformedPoint(
                            position,
                            by: item.modelTransform
                        )
                        if let mutation = snapshot.bodyPreviewTransforms[item.id] {
                            transformed = try ViewportWorldTransformAlgebra.transformedPoint(transformed, by: mutation)
                        }
                        guard transformed.isFinite else {
                            throw RealityViewportSpatialBatch.invalid(
                                "Body mesh transform produced a non-finite position."
                            )
                        }
                        transformedPositions.append(transformed)
                    }
                    meshes.append(.init(
                        family: .body,
                        value: RealityViewportSpatialBatch.Mesh(
                            positions: transformedPositions,
                            indices: mesh.indices,
                            topology: .triangles,
                            color: color
                        )
                    ))
                    activeFamilies.insert(.body)
                } else {
                    var corners = snapshot.editedBodies[item.featureID]?.worldBoxCorners
                        ?? fallbackBodyCorners(item: item, component: component)
                    if let mutation = snapshot.bodyPreviewTransforms[item.id] {
                        corners = try corners.map { try ViewportWorldTransformAlgebra.transformedPoint($0, by: mutation) }
                    }
                    guard corners.count == 8, corners.allSatisfy(isFinitePoint) else {
                        throw RealityViewportSpatialBatch.invalid(
                            "Body fallback bounds do not contain eight finite world corners."
                        )
                    }
                    let faces = [
                        [0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4],
                        [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6],
                    ]
                    for face in faces {
                        let polygon = face.map { corners[$0] }
                        paths.append(.init(
                            family: .body,
                            value: try polygonFill(polygon, color: color)
                        ))
                        meshes.append(.init(
                            family: .body,
                            value: try closedLine(
                                polygon,
                                color: isSelected || isHovered
                                    ? selectionColor
                                    : SIMD4<Float>(0.05, 0.05, 0.05, 0.54)
                            )
                        ))
                    }
                    activeFamilies.insert(.body)
                }
            case .curve(let component):
                guard !component.segments.isEmpty else {
                    throw RealityViewportSpatialBatch.invalid(
                        "Curve item has no evaluated world segments."
                    )
                }
                let color = isObjectItem(
                    item,
                    selectedFeatures: selectedFeatures,
                    selectedNodes: selectedNodes
                ) ? selectionColor : (hoveredFeatures.contains(item.featureID)
                    || item.sceneNodeID.map(hoveredNodes.contains) == true
                    ? hoverColor : curveColor)
                for segment in component.segments {
                    guard segment.points.count >= 2 else {
                        throw RealityViewportSpatialBatch.invalid(
                            "Curve segment has fewer than two world points."
                        )
                    }
                    let points = segment.points.map {
                        ViewportLayout.transformedPoint($0, by: item.modelTransform)
                    }
                    guard points.allSatisfy(isFinitePoint) else {
                        throw RealityViewportSpatialBatch.invalid(
                            "Curve segment contains a non-finite world point."
                        )
                    }
                    meshes.append(.init(
                        family: .curve,
                        value: try line(
                            points,
                            color: color
                        )
                    ))
                    activeFamilies.insert(.curve)
                }
            case .sketch(let primitives):
                guard !suppressedSketchFeatures.contains(item.featureID) else { continue }
                let itemSelected = isObjectItem(
                    item,
                    selectedFeatures: selectedFeatures,
                    selectedNodes: selectedNodes
                )
                let color = itemSelected ? selectionColor : (hoveredFeatures.contains(item.featureID)
                    || item.sceneNodeID.map(hoveredNodes.contains) == true
                    ? hoverColor : sketchColor)
                let selectedEntityIDs = Set(selectedSketchEntities.compactMap {
                    $0.featureID == item.featureID ? $0.entityID : nil
                })
                let hoveredEntityIDs = Set((previewSketchEntities
                    + (hoveredSketchEntity.map { [$0] } ?? [])).compactMap {
                        $0.featureID == item.featureID ? $0.entityID : nil
                    })
                let selectedRegionIDs = Set(selectedSketchRegions.compactMap {
                    $0.featureID == item.featureID ? $0.componentID : nil
                })
                let hoveredRegionIDs = Set((previewSketchRegions
                    + (hoveredSketchRegion.map { [$0] } ?? [])).compactMap {
                        $0.featureID == item.featureID ? $0.componentID : nil
                    })
                for region in item.sketchRegions where selectedRegionIDs.contains(region.componentID)
                    || hoveredRegionIDs.contains(region.componentID) {
                    let regionColor = selectedRegionIDs.contains(region.componentID)
                        ? selectionColor : hoverColor
                    let points = region.points.map { point($0) }
                    guard points.count >= 3, points.allSatisfy(isFinitePoint) else {
                        throw RealityViewportSpatialBatch.invalid(
                            "Selected sketch region has fewer than three finite world points."
                        )
                    }
                    paths.append(.init(
                        family: .sketch,
                        value: try polygonFill(
                            points,
                            color: SIMD4<Float>(regionColor.x, regionColor.y, regionColor.z, 0.16),
                            depth: .annotation
                        )
                    ))
                    meshes.append(.init(
                        family: .sketch,
                        value: try closedLine(points, color: regionColor, depth: .annotation)
                    ))
                    activeFamilies.insert(.sketch)
                }
                for primitive in primitives {
                    let points = try sketchPrimitiveWorldPoints(primitive)
                    guard !points.isEmpty, points.allSatisfy(isFinitePoint) else {
                        throw RealityViewportSpatialBatch.invalid(
                            "Sketch primitive has no finite evaluated world points."
                        )
                    }
                    let isEntitySelected = selectedEntityIDs.contains(primitive.entityID)
                    let isEntityHovered = hoveredEntityIDs.contains(primitive.entityID)
                    let primitiveColor = isEntitySelected || itemSelected ? selectionColor
                        : (isEntityHovered || hoveredFeatures.contains(item.featureID)
                            ? hoverColor : color)
                    if points.count == 1 {
                        markers.append(.init(
                            family: .sketch,
                            value: marker(
                                anchor: points[0], diameterPoints: 6, color: primitiveColor
                            )
                        ))
                    } else {
                        var vertices = points
                        if primitiveIsClosed(primitive), vertices.first != vertices.last {
                            vertices.append(points[0])
                        }
                        cameraLines.append(.init(family: .sketch, value: .init(
                            points: vertices.map { .init(anchor: $0, offset: .zero) },
                            color: primitiveColor, depth: .scene,
                            objectPreviewOccurrenceID: item.id
                        )))
                    }
                    // Sampling vertices describe tessellation, not editable control points.
                    // The affordance producer alone owns edit markers and their hit targets.
                    activeFamilies.insert(.sketch)
                }
            }
        }
    }

    private static func appendMeshSelection(
        _ snapshot: ViewportSpatialOverlaySemanticSnapshot,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        guard let overlay = snapshot.meshSelection else { return }
        guard !overlay.isTruncated else {
            throw MeshSourcePresentationRenderError(
                code: .resourceExhausted,
                message: "The complete Mesh selection overlay is not available for native rendering."
            )
        }
        guard !overlay.selectedElements.isEmpty else { return }

        for segment in overlay.boundarySegments {
            let start = Point3D(
                x: segment.start.x,
                y: segment.start.y,
                z: segment.start.z
            )
            let end = Point3D(
                x: segment.end.x,
                y: segment.end.y,
                z: segment.end.z
            )
            guard isFinitePoint(start), isFinitePoint(end) else {
                throw RealityViewportSpatialBatch.invalid(
                    "Selected Mesh boundary contains a non-finite world point."
                )
            }
            meshes.append(.init(
                family: .meshSelection,
                value: try line(
                    [start, end],
                    color: editColor,
                    depth: .annotation
                )
            ))
        }
        for point in overlay.points {
            let world = Point3D(
                x: point.position.x,
                y: point.position.y,
                z: point.position.z
            )
            guard isFinitePoint(world) else {
                throw RealityViewportSpatialBatch.invalid(
                    "Selected Mesh element contains a non-finite world point."
                )
            }
            markers.append(.init(
                family: .meshSelection,
                value: marker(
                    .sphere,
                    anchor: world,
                    diameterPoints: 8,
                    color: editColor,
                    depth: .annotation
                )
            ))
        }
        guard !overlay.boundarySegments.isEmpty || !overlay.points.isEmpty else {
            throw RealityViewportSpatialBatch.invalid(
                "The selected Mesh elements have no spatial positions."
            )
        }
        activeFamilies.insert(.meshSelection)
    }


    /// Materializes the complete pattern semantic payload on the producer
    /// worker.  The MainActor only captures the immutable document, scene,
    /// selection, and interaction request that this operation needs.

    /// Builds the analysis selection map and continuity edge lookup on the
    /// producer worker from raw checked-Sendable values.
    private static func materializeAnalysis(
        from source: ViewportSpatialOverlaySemanticSnapshot.AnalysisSource?,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> ViewportSpatialOverlaySemanticSnapshot.Analysis? {
        guard let source else { return nil }
        try Task.checkCancellation()
        let overlay = try ViewportSurfaceAnalysisOverlay.build(
            result: source.result,
            selection: source.selection,
            document: source.document,
            options: source.options,
            checkpoint: checkpoint
        )
        try Task.checkCancellation()
        let continuity = try ViewportSurfaceContinuityOverlay.build(
            result: source.continuity,
            scene: source.scene,
            selection: source.selection,
            document: source.document,
            checkpoint: checkpoint
        )
        try Task.checkCancellation()
        guard !overlay.items.isEmpty
                || !overlay.principalDirectionItems.isEmpty
                || !overlay.boundaryItems.isEmpty
                || !continuity.items.isEmpty else {
            return nil
        }
        var items: [ViewportSpatialOverlaySemanticSnapshot.Analysis.Item] = []
        items.reserveCapacity(overlay.items.count)
        for item in overlay.items {
            try Task.checkCancellation()
            items.append(.init(
                direction: item.direction,
                position: item.position,
                normal: item.normal,
                normalCurvature: item.normalCurvature
            ))
        }
        var principalDirectionItems: [ViewportSpatialOverlaySemanticSnapshot.Analysis.PrincipalDirectionItem] = []
        principalDirectionItems.reserveCapacity(overlay.principalDirectionItems.count)
        for item in overlay.principalDirectionItems {
            try Task.checkCancellation()
            principalDirectionItems.append(.init(
                position: item.position,
                minimumPrincipalDirection: item.minimumPrincipalDirection,
                maximumPrincipalDirection: item.maximumPrincipalDirection,
                minimumPrincipalCurvature: item.minimumPrincipalCurvature,
                maximumPrincipalCurvature: item.maximumPrincipalCurvature
            ))
        }
        var boundaryItems: [ViewportSpatialOverlaySemanticSnapshot.Analysis.BoundaryItem] = []
        boundaryItems.reserveCapacity(overlay.boundaryItems.count)
        for item in overlay.boundaryItems {
            try Task.checkCancellation()
            boundaryItems.append(.init(
                role: item.role,
                points: item.points,
                isClosed: item.isClosed
            ))
        }
        var continuityItems: [ViewportSpatialOverlaySemanticSnapshot.Analysis.ContinuityItem] = []
        continuityItems.reserveCapacity(continuity.items.count)
        for item in continuity.items {
            try Task.checkCancellation()
            continuityItems.append(.init(
                start: item.start,
                end: item.end,
                continuity: item.continuity,
                requiresCurvatureContinuitySolve: item.requiresCurvatureContinuitySolve
            ))
        }
        return .init(
            items: items,
            principalDirectionItems: principalDirectionItems,
            boundaryItems: boundaryItems,
            continuityItems: continuityItems
        )
    }

    /// Converts section contours and their hatch segments on the producer
    /// worker.  Source truncation remains a typed failure; no prefix is
    /// silently accepted by the native path.
    private static func materializeSection(
        from source: ViewportSpatialOverlaySemanticSnapshot.SectionSource?,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> ViewportSpatialOverlaySemanticSnapshot.Section? {
        guard let source else { return nil }
        try Task.checkCancellation()
        guard let result = source.result else { return nil }
        guard !result.truncatedIntersectionSegments else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        for contour in result.intersectionContours {
            try checkpoint(0, 0, contour.points2D.count)
            guard contour.points.count == contour.points2D.count else {
                throw RealityViewportSpatialBatch.invalid("Section contour world and plane coordinates do not match.")
            }
            for point in contour.points2D {
                try Task.checkCancellation()
                guard point.x.isFinite, point.y.isFinite else {
                    throw RealityViewportSpatialBatch.invalid("Section contour has non-finite plane coordinates.")
                }
            }
        }
        let overlay = try ViewportSectionAnalysisOverlay.build(
            result: source.result,
            ruler: source.ruler,
            maximumVisibleSegments: .max,
            maximumVisibleContours: .max,
            maximumVisibleHatches: .max,
            checkpoint: checkpoint
        )
        try Task.checkCancellation()
        guard overlay.plane != nil || !overlay.segments.isEmpty
                || !overlay.contours.isEmpty || !overlay.hatches.isEmpty else {
            return nil
        }
        guard !overlay.hasTruncatedSourcePayload,
              overlay.omittedSegmentCount == 0,
              overlay.omittedContourCount == 0 else {
            throw MeshSourcePresentationRenderError(
                code: .resourceExhausted,
                message: "The complete section-analysis overlay is not available for native rendering."
            )
        }
        var segments: [ViewportSpatialOverlaySemanticSnapshot.Section.Segment] = []
        segments.reserveCapacity(overlay.segments.count)
        for segment in overlay.segments {
            try Task.checkCancellation()
            segments.append(.init(start: segment.start, end: segment.end))
        }
        var contours: [ViewportSpatialOverlaySemanticSnapshot.Section.Contour] = []
        contours.reserveCapacity(overlay.contours.count)
        for contour in overlay.contours {
            try Task.checkCancellation()
            contours.append(.init(points: contour.points, isClosed: contour.isClosed))
        }
        var hatches: [ViewportSpatialOverlaySemanticSnapshot.Section.Hatch] = []
        hatches.reserveCapacity(overlay.hatches.count)
        for hatch in overlay.hatches {
            try Task.checkCancellation()
            hatches.append(.init(start: hatch.start, end: hatch.end))
        }
        return .init(
            plane: overlay.plane.map {
                .init(
                    origin: $0.origin,
                    normalEnd: $0.normalEnd,
                    corners: $0.corners
                )
            },
            segments: segments,
            contours: contours,
            hatches: hatches,
            sourceSegmentCount: overlay.sourceSegmentCount,
            omittedSegmentCount: overlay.omittedSegmentCount,
            sourceContourCount: overlay.sourceContourCount,
            omittedContourCount: overlay.omittedContourCount,
            hasTruncatedSourcePayload: overlay.hasTruncatedSourcePayload
        )
    }


    private static func appendAnalysis(
        _ analysis: ViewportSpatialOverlaySemanticSnapshot.Analysis?,
        modelBounds: CGRect,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        labels: inout [ViewportSpatialOverlayInput.Label],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        guard let analysis else { return }
        try Task.checkCancellation()
        guard !analysis.items.isEmpty
                || !analysis.principalDirectionItems.isEmpty
                || !analysis.boundaryItems.isEmpty
                || !analysis.continuityItems.isEmpty else {
            throw RealityViewportSpatialBatch.invalid(
                "The active surface-analysis route has no native world descriptors."
            )
        }
        let bounds = modelBounds
        let diagonal = max(Double(hypot(bounds.width, bounds.height)), 1.0e-6)
        guard diagonal.isFinite, diagonal > 0 else {
            throw RealityViewportSpatialBatch.invalid("Surface-analysis bounds are invalid.")
        }
        for item in analysis.boundaryItems {
            try Task.checkCancellation()
            guard item.points.count >= 2 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Surface-analysis boundary has fewer than two world points."
                )
            }
            let color = item.role == .outer
                ? SIMD4<Float>(1.0, 0.82, 0.24, 0.90)
                : SIMD4<Float>(0.95, 0.36, 0.76, 0.90)
            meshes.append(.init(
                family: .analysis,
                value: try line(
                    item.points + (item.isClosed ? [item.points[0]] : []),
                    color: color,
                    depth: .annotation
                )
            ))
        }
        let maximumNormalCurvature = analysis.items.map { abs($0.normalCurvature) }.max() ?? 0
        guard maximumNormalCurvature.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Surface-analysis curvature is not finite.")
        }
        if maximumNormalCurvature > 1.0e-12 {
            let scale = diagonal * 0.16 / maximumNormalCurvature
            for item in analysis.items {
                try Task.checkCancellation()
                let end = offset(
                    item.position,
                    direction: item.normal,
                    distance: item.normalCurvature * scale
                )
                meshes.append(.init(
                    family: .analysis,
                    value: try line(
                        [item.position, end],
                        color: item.direction == .u
                            ? SIMD4<Float>(0.28, 0.86, 0.64, 0.80)
                            : SIMD4<Float>(0.95, 0.46, 0.78, 0.80),
                        depth: .annotation
                    )
                ))
            }
        }
        let maximumPrincipalCurvature = analysis.principalDirectionItems.flatMap {
            [abs($0.minimumPrincipalCurvature), abs($0.maximumPrincipalCurvature)]
        }.max() ?? 0
        guard maximumPrincipalCurvature.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Principal curvature is not finite.")
        }
        if maximumPrincipalCurvature > 1.0e-12 {
            let scale = diagonal * 0.10 / maximumPrincipalCurvature
            for item in analysis.principalDirectionItems {
                try Task.checkCancellation()
                let minimumHalfLength = abs(item.minimumPrincipalCurvature) * scale * 0.5
                let maximumHalfLength = abs(item.maximumPrincipalCurvature) * scale * 0.5
                if minimumHalfLength > 1.0e-12 {
                    meshes.append(.init(
                        family: .analysis,
                        value: try line(
                            [
                                offset(item.position, direction: item.minimumPrincipalDirection, distance: -minimumHalfLength),
                                offset(item.position, direction: item.minimumPrincipalDirection, distance: minimumHalfLength),
                            ],
                            color: SIMD4<Float>(1.0, 0.72, 0.22, 0.82),
                            depth: .annotation
                        )
                    ))
                }
                if maximumHalfLength > 1.0e-12 {
                    meshes.append(.init(
                        family: .analysis,
                        value: try line(
                            [
                                offset(item.position, direction: item.maximumPrincipalDirection, distance: -maximumHalfLength),
                                offset(item.position, direction: item.maximumPrincipalDirection, distance: maximumHalfLength),
                            ],
                            color: SIMD4<Float>(0.34, 0.68, 1.0, 0.82),
                            depth: .annotation
                        )
                    ))
                }
            }
        }
        for item in analysis.continuityItems {
            try Task.checkCancellation()
            let color = continuityColor(item.continuity)
            meshes.append(.init(
                family: .analysis,
                value: try line(
                    [item.start, item.end],
                    color: color,
                    depth: .annotation
                )
            ))
            labels.append(.init(
                family: .analysis,
                value: try label(
                    continuityLabel(item.continuity, requiresSolve: item.requiresCurvatureContinuitySolve),
                    anchor: midpoint(item.start, item.end),
                    offset: CGPoint(x: 0, y: -18),
                    color: color,
                    alignment: .center,
                    heightPoints: 9
                )
            ))
        }
        activeFamilies.insert(.analysis)
    }

    static func appendSection(
        _ section: ViewportSpatialOverlaySemanticSnapshot.Section?,
        paths: inout [ViewportSpatialOverlayInput.Path],
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        guard let section else { return }
        try Task.checkCancellation()
        guard !section.hasTruncatedSourcePayload,
              section.omittedSegmentCount == 0,
              section.omittedContourCount == 0 else {
            throw MeshSourcePresentationRenderError(
                code: .resourceExhausted,
                message: "The complete section-analysis overlay is not available for native rendering."
            )
        }
        guard section.plane != nil || !section.segments.isEmpty
                || !section.contours.isEmpty || !section.hatches.isEmpty else {
            throw RealityViewportSpatialBatch.invalid(
                "The active section-analysis route has no native world descriptors."
            )
        }
        if let plane = section.plane {
            guard plane.corners.count >= 4 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Section plane has an incomplete corner source."
                )
            }
            let origin = plane.corners[0]
            let xAxis = Vector3D(
                x: plane.corners[1].x - origin.x,
                y: plane.corners[1].y - origin.y,
                z: plane.corners[1].z - origin.z
            )
            let yAxis = Vector3D(
                x: plane.corners[3].x - origin.x,
                y: plane.corners[3].y - origin.y,
                z: plane.corners[3].z - origin.z
            )
            var border = Path()
            border.move(to: .zero)
            border.addLine(to: CGPoint(x: 1, y: 0))
            border.addLine(to: CGPoint(x: 1, y: 1))
            border.addLine(to: CGPoint(x: 0, y: 1))
            border.closeSubpath()
            paths.append(.init(
                family: .section,
                value: RealityViewportSpatialBatch.PlanarPath(
                    path: border,
                    origin: origin,
                    xAxis: SIMD3<Double>(xAxis.x, xAxis.y, xAxis.z),
                    yAxis: SIMD3<Double>(yAxis.x, yAxis.y, yAxis.z),
                    color: sectionPlaneColor,
                    depth: .annotation
                )
            ))
            meshes.append(.init(
                family: .section,
                value: try line(
                    [plane.origin, plane.normalEnd],
                    color: sectionNormalColor,
                    depth: .annotation
                )
            ))
        }
        for segment in section.segments {
            try Task.checkCancellation()
            meshes.append(.init(
                family: .section,
                value: try line(
                    [segment.start, segment.end],
                    color: sectionColor,
                    depth: .annotation
                )
            ))
        }
        for contour in section.contours where contour.isClosed && contour.points.count >= 3 {
            try Task.checkCancellation()
            paths.append(.init(
                family: .section,
                value: try polygonFill(
                    contour.points,
                    color: SIMD4<Float>(0.98, 0.84, 0.26, 0.10),
                    depth: .annotation
                )
            ))
            meshes.append(.init(
                family: .section,
                value: try closedLine(
                    contour.points,
                    color: SIMD4<Float>(0.98, 0.84, 0.26, 0.42),
                    depth: .annotation
                )
            ))
        }
        for hatch in section.hatches {
            try Task.checkCancellation()
            meshes.append(.init(
                family: .section,
                value: try line(
                    [hatch.start, hatch.end],
                    color: SIMD4<Float>(0.98, 0.84, 0.26, 0.34),
                    depth: .annotation
                )
            ))
        }
        activeFamilies.insert(.section)
    }

    private static func appendMeasurement(
        _ snapshot: ViewportSpatialOverlaySemanticSnapshot,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        labels: inout [ViewportSpatialOverlayInput.Label],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        cameraLines: inout [ViewportSpatialOverlayInput.CameraLine],
        boundsRuler: inout ViewportMeasurementBoundsRulerInput?,
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        _ = cameraLines
        guard let measurement = snapshot.measurement else { return }
        boundsRuler = measurement.boundsRuler
        if let start = measurement.start,
           let end = measurement.end {
            guard let text = measurement.label, !text.isEmpty else {
                throw RealityViewportSpatialBatch.invalid(
                    "Measurement geometry is missing its formatted distance label."
                )
            }
            meshes.append(.init(
                family: .measurement,
                value: try line(
                    [start, end],
                    color: measurementColor,
                    depth: .annotation
                )
            ))
            markers.append(.init(
                family: .measurement,
                value: marker(
                    anchor: start,
                    diameterPoints: 8,
                    color: measurementColor
                )
            ))
            markers.append(.init(
                family: .measurement,
                value: marker(
                    anchor: end,
                    diameterPoints: 8,
                    color: measurementColor
                )
            ))
            labels.append(.init(
                family: .measurement,
                value: try label(
                    text,
                    anchor: midpoint(start, end),
                    offset: CGPoint(x: 0, y: -14),
                    color: measurementColor,
                    alignment: .center,
                    heightPoints: 10
                )
            ))
            activeFamilies.insert(.measurement)
        }
        if measurement.boundsRuler != nil {
            activeFamilies.insert(.measurement)
        }
    }

    private static func appendSnapReference(
        _ snapshot: ViewportSpatialOverlaySemanticSnapshot,
        paths: inout [ViewportSpatialOverlayInput.Path],
        labels: inout [ViewportSpatialOverlayInput.Label],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        guard let overlay = snapshot.snapReference else { return }
        var emitted = false
        let context: ViewportSnapOverlayContext = switch overlay.context {
        case .passiveHover: .passiveHover
        case .creationDrag: .creationDrag
        }

        if let result = overlay.result,
           let candidate = result.selectedCandidate,
           ViewportSnapOverlayPolicy.drawsOverlay(kind: candidate.kind, context: context) {
            let anchor = result.selectedWorldPoint
                ?? Point3D(x: result.resolvedPoint.x, y: 0.0, z: result.resolvedPoint.y)
            guard isFinitePoint(anchor) else {
                throw RealityViewportSpatialBatch.invalid(
                    "Snap reference anchor is not a finite world point."
                )
            }
            markers.append(.init(
                family: .snapReference,
                value: marker(
                    anchor: anchor,
                    diameterPoints: 8,
                    color: referenceColor
                )
            ))
            if ViewportSnapOverlayPolicy.drawsLabel(kind: candidate.kind, context: context),
               !candidate.label.isEmpty {
                labels.append(.init(
                    family: .snapReference,
                    value: try label(
                        candidate.label,
                        anchor: anchor,
                        offset: CGPoint(x: 8, y: -10),
                        color: referenceColor,
                        heightPoints: 9
                    )
                ))
            }
            emitted = true
        }

        guard !overlay.referenceLineAnchors.isEmpty else {
            if emitted { activeFamilies.insert(.snapReference) }
            return
        }
        let bounds = overlay.modelBounds
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "Snap reference bounds are not finite."
            )
        }
        let span = max(bounds.width, bounds.height, 1.0e-3)
        let minX = bounds.minX - span
        let maxX = bounds.maxX + span
        let minZ = bounds.minY - span
        let maxZ = bounds.maxY + span
        guard minX.isFinite, maxX.isFinite, minZ.isFinite, maxZ.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "Snap reference extent is not finite."
            )
        }
        for anchor in overlay.referenceLineAnchors {
            guard anchor.point.x.isFinite, anchor.point.y.isFinite else {
                throw RealityViewportSpatialBatch.invalid(
                    "Snap reference line anchor is not finite."
                )
            }
            let x = anchor.point.x
            let z = anchor.point.y
            let horizontal = dashedPath([
                CGPoint(x: minX, y: z), CGPoint(x: maxX, y: z)
            ])
            let vertical = dashedPath([
                CGPoint(x: x, y: minZ), CGPoint(x: x, y: maxZ)
            ])
            paths.append(.init(
                family: .snapReference,
                value: RealityViewportSpatialBatch.PlanarPath(
                    path: horizontal,
                    origin: .origin,
                    xAxis: SIMD3<Double>(1, 0, 0),
                    yAxis: SIMD3<Double>(0, 0, 1),
                    color: referenceColor,
                    depth: .annotation
                )
            ))
            paths.append(.init(
                family: .snapReference,
                value: RealityViewportSpatialBatch.PlanarPath(
                    path: vertical,
                    origin: .origin,
                    xAxis: SIMD3<Double>(1, 0, 0),
                    yAxis: SIMD3<Double>(0, 0, 1),
                    color: referenceColor,
                    depth: .annotation
                )
            ))
            markers.append(.init(
                family: .snapReference,
                value: marker(
                    anchor: Point3D(x: x, y: 0, z: z),
                    diameterPoints: 7,
                    color: referenceColor
                )
            ))
            emitted = true
        }
        if emitted { activeFamilies.insert(.snapReference) }
    }

    private static func appendPlacement(
        _ snapshot: ViewportSpatialOverlaySemanticSnapshot,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        gridPlacement: inout RealityViewportSpatialBatch.GridPlacement?,
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        guard let placement = snapshot.placement else { return }
        let highlight = placement.highlight
        guard highlight.point.x.isFinite, highlight.point.y.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Placement preview point is not finite.")
        }
        let coordinateSystem: SketchPlaneCoordinateSystem
        do {
            coordinateSystem = try SketchPlaneCoordinateSystem(plane: highlight.sketchPlane)
        } catch {
            throw RealityViewportSpatialBatch.invalid("Placement preview sketch plane is invalid.")
        }
        let center = coordinateSystem.point(
            from: SketchPlaneCanvasMapper(sketchPlane: highlight.sketchPlane)
                .localPoint(fromCanvas: highlight.point)
        )

        if case .rectangle(let widthMeters, let heightMeters, .visibleCell) = highlight.previewKind,
           widthMeters == nil || heightMeters == nil {
            let xAxis = coordinateSystem.u
            let yAxis = coordinateSystem.v
            let xLength = xAxis.length
            let yLength = yAxis.length
            let orthogonality = xAxis.dot(yAxis)
            guard isFiniteVector(xAxis), isFiniteVector(yAxis),
                  xLength.isFinite, yLength.isFinite,
                  abs(xLength - 1.0) <= 1.0e-9,
                  abs(yLength - 1.0) <= 1.0e-9,
                  orthogonality.isFinite, abs(orthogonality) <= 1.0e-9 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Placement sketch plane axes are not a finite orthonormal basis."
                )
            }
            gridPlacement = .init(
                center: center,
                uAxis: SIMD3(xAxis.x, xAxis.y, xAxis.z),
                vAxis: SIMD3(yAxis.x, yAxis.y, yAxis.z),
                widthMeters: widthMeters,
                heightMeters: heightMeters,
                color: referenceColor
            )
            activeFamilies.insert(.placement)
            return
        }

        let points: [Point3D]
        do {
            points = try placementPoints(
                kind: highlight.previewKind,
                center: center,
                coordinateSystem: coordinateSystem,
                defaults: placement.defaults,
                visibleCellMeters: placement.defaults.placedSolidSideMeters
            )
        } catch {
            throw RealityViewportSpatialBatch.invalid("Placement preview source is invalid.")
        }
        guard points.count >= 2, points.allSatisfy(isFinitePoint) else {
            throw RealityViewportSpatialBatch.invalid("Placement preview has no finite world geometry.")
        }
        meshes.append(.init(
            family: .placement,
            value: try line(points, color: referenceColor, depth: .annotation)
        ))
        if placementPreviewIsClosed(highlight.previewKind), points.count >= 3 {
            meshes.append(.init(
                family: .placement,
                value: try closedLine(points, color: referenceColor, depth: .annotation)
            ))
        }
        activeFamilies.insert(.placement)
    }

    private static func appendTransform(
        _ snapshot: ViewportSpatialOverlaySemanticSnapshot,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        paths: inout [ViewportSpatialOverlayInput.Path],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        var emitted = false
        let topologyTargets = snapshot.interaction.selectedTargets
            + snapshot.interaction.previewTargets
            + (snapshot.interaction.hoveredTarget.map { [$0] } ?? [])
        for target in topologyTargets {
            guard let item = sceneItem(for: target, in: snapshot.scene),
                  case .body(let component) = item.kind,
                  let topology = component.topology else {
                continue
            }
            switch target.component {
            case .object, .sketchEntity, .region, .constructionPlane:
                continue
            case .face(let componentID):
                guard let face = topology.faces.first(where: { $0.componentID == componentID }) else {
                    throw RealityViewportSpatialBatch.invalid("Selected face is missing from body topology.")
                }
                let points = face.points.map {
                    ViewportLayout.transformedPoint($0, by: item.modelTransform)
                }
                guard points.count >= 3, points.allSatisfy(isFinitePoint) else {
                    throw RealityViewportSpatialBatch.invalid("Selected face has invalid world points.")
                }
                let color = target == snapshot.interaction.hoveredTarget ? hoverColor : selectionColor
                paths.append(.init(
                    family: .transform,
                    value: try polygonFill(
                        points,
                        color: SIMD4<Float>(color.x, color.y, color.z, 0.16),
                        depth: .annotation
                    )
                ))
                meshes.append(.init(
                    family: .transform,
                    value: try closedLine(points, color: color, depth: .annotation)
                ))
                emitted = true
            case .edge(let componentID):
                guard let edge = topology.edges.first(where: { $0.componentID == componentID }) else {
                    throw RealityViewportSpatialBatch.invalid("Selected edge is missing from body topology.")
                }
                let points = [
                    ViewportLayout.transformedPoint(edge.start, by: item.modelTransform),
                    ViewportLayout.transformedPoint(edge.end, by: item.modelTransform),
                ]
                guard points.allSatisfy(isFinitePoint) else {
                    throw RealityViewportSpatialBatch.invalid("Selected edge has invalid world points.")
                }
                let color = target == snapshot.interaction.hoveredTarget ? hoverColor : selectionColor
                meshes.append(.init(
                    family: .transform,
                    value: try line(points, color: color, depth: .annotation)
                ))
                for point in points {
                    markers.append(.init(
                        family: .transform,
                        value: marker(anchor: point, diameterPoints: 8, color: color)
                    ))
                }
                emitted = true
            case .vertex(let componentID):
                guard let vertex = topology.vertices.first(where: { $0.componentID == componentID }) else {
                    throw RealityViewportSpatialBatch.invalid("Selected vertex is missing from body topology.")
                }
                let point = ViewportLayout.transformedPoint(vertex.point, by: item.modelTransform)
                guard isFinitePoint(point) else {
                    throw RealityViewportSpatialBatch.invalid("Selected vertex has an invalid world point.")
                }
                let color = target == snapshot.interaction.hoveredTarget ? hoverColor : selectionColor
                markers.append(.init(
                    family: .transform,
                    value: marker(anchor: point, diameterPoints: 9, color: color)
                ))
                emitted = true
            }
        }

        if emitted { activeFamilies.insert(.transform) }
    }

    private static func appendDragPreview(
        _ snapshot: ViewportSpatialOverlaySemanticSnapshot,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        guard let preview = snapshot.dragPreview else { return }
        let resolvedDrag = ViewportCanvasDragSnapResolver().resolvedDrag(
            preview.drag,
            document: preview.document,
            ruler: preview.ruler,
            snapOptions: preview.snapOptions,
            axisConstraint: preview.axisConstraint,
            currentEvaluation: preview.currentEvaluation,
            currentGeneration: preview.currentGeneration
        )
        let coordinateSystem: SketchPlaneCoordinateSystem
        do {
            coordinateSystem = try SketchPlaneCoordinateSystem(plane: resolvedDrag.sketchPlane)
        } catch {
            throw RealityViewportSpatialBatch.invalid("Creation drag sketch plane is invalid.")
        }
        let canvasMapper = SketchPlaneCanvasMapper(sketchPlane: resolvedDrag.sketchPlane)
        let start = canvasMapper.localPoint(fromCanvas: resolvedDrag.start)
        let end = canvasMapper.localPoint(fromCanvas: resolvedDrag.end)
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Creation drag points are not finite.")
        }
        // A press can publish a creation drag before the pointer has moved.  It
        // is not malformed source and must not invalidate the whole native
        // frame; the existing Canvas preview simply has no drawable geometry
        // until its minimum extent is reached.
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let hasMovement = abs(deltaX) > 1.0e-12 || abs(deltaY) > 1.0e-12
        if !hasMovement {
            let hasExplicitSize: Bool
            switch preview.kind {
            case .rectangle(let width, let height):
                hasExplicitSize = (width ?? 0).isFinite && (height ?? 0).isFinite
                    && (width ?? 0) > 0 && (height ?? 0) > 0
            case .polygon(_, let radius, _), .arc(let radius, _), .circle(let radius):
                hasExplicitSize = radius?.isFinite == true && (radius ?? 0) > 0
            case .spline:
                hasExplicitSize = false
            }
            guard hasExplicitSize else { return }
        } else if case .rectangle(let width, let height) = preview.kind {
            let resolvedWidth = width ?? abs(deltaX)
            let resolvedHeight = height ?? abs(deltaY)
            guard resolvedWidth.isFinite, resolvedWidth > 0,
                  resolvedHeight.isFinite, resolvedHeight > 0 else {
                return
            }
        }
        let points: [Point3D]
        let closed: Bool
        do {
            switch preview.kind {
            case .rectangle(let widthOverride, let heightOverride):
                let width = widthOverride ?? abs(end.x - start.x)
                let height = heightOverride ?? abs(end.y - start.y)
                guard width.isFinite, height.isFinite, width > 0, height > 0 else {
                    throw RealityViewportSpatialBatch.invalid("Creation rectangle dimensions are invalid.")
                }
                let resolvedEnd = Point2D(
                    x: start.x + (end.x < start.x ? -width : width),
                    y: start.y + (end.y < start.y ? -height : height)
                )
                let local = [
                    Point2D(x: min(start.x, resolvedEnd.x), y: min(start.y, resolvedEnd.y)),
                    Point2D(x: max(start.x, resolvedEnd.x), y: min(start.y, resolvedEnd.y)),
                    Point2D(x: max(start.x, resolvedEnd.x), y: max(start.y, resolvedEnd.y)),
                    Point2D(x: min(start.x, resolvedEnd.x), y: max(start.y, resolvedEnd.y)),
                ]
                points = local.map(coordinateSystem.point(from:))
                closed = true
            case .polygon(let state, let radius, let rotation):
                let draft = try CanvasSketchCurveDrafts.polygon(
                    fromCenter: start,
                    toRadiusPoint: end,
                    sides: state.sideCount,
                    sizingMode: state.sizingMode,
                    inclinationMode: state.inclinationMode,
                    radiusMeters: radius,
                    rotationAngleRadians: rotation
                )
                points = draft.vertices.map(coordinateSystem.point(from:))
                closed = true
            case .arc(let radius, let span):
                let draft = try CanvasSketchCurveDrafts.arc(
                    fromCenter: start,
                    toRadiusPoint: end,
                    radiusMeters: radius,
                    spanAngleRadians: span
                )
                let arcSpan = normalizedArcSpan(
                    startAngle: draft.startAngleRadians,
                    endAngle: draft.endAngleRadians
                )
                points = (0 ... 24).map { index in
                    let t = Double(index) / 24.0
                    let angle = draft.startAngleRadians + arcSpan * t
                    return coordinateSystem.point(from: Point2D(
                        x: draft.center.x + cos(angle) * draft.radiusMeters,
                        y: draft.center.y + sin(angle) * draft.radiusMeters
                    ))
                }
                closed = false
            case .spline:
                let draft = try CanvasSketchCurveDrafts.spline(from: start, to: end)
                points = cubicBezierPoints(controlPoints: draft.controlPoints, segmentCount: 32)
                    .map(coordinateSystem.point(from:))
                closed = false
            case .circle(let radius):
                let deltaX = end.x - start.x
                let deltaY = end.y - start.y
                let resolvedRadius = radius ?? sqrt(deltaX * deltaX + deltaY * deltaY)
                guard resolvedRadius.isFinite, resolvedRadius > 1.0e-12 else {
                    throw RealityViewportSpatialBatch.invalid("Creation circle radius is invalid.")
                }
                points = (0 ... 48).map { index in
                    let angle = Double(index) / 48.0 * Double.pi * 2.0
                    return coordinateSystem.point(from: Point2D(
                        x: start.x + cos(angle) * resolvedRadius,
                        y: start.y + sin(angle) * resolvedRadius
                    ))
                }
                closed = true
            }
        } catch let error as MeshSourcePresentationRenderError {
            throw error
        } catch {
            throw RealityViewportSpatialBatch.invalid("Creation drag preview source is invalid.")
        }
        guard points.count >= 2, points.allSatisfy(isFinitePoint) else {
            throw RealityViewportSpatialBatch.invalid("Creation drag preview has no finite world path.")
        }
        meshes.append(.init(
            family: .placement,
            value: try line(points, color: referenceColor, depth: .annotation)
        ))
        if closed {
            meshes.append(.init(
                family: .placement,
                value: try closedLine(points, color: referenceColor, depth: .annotation)
            ))
        }
        activeFamilies.insert(.placement)
    }

    private static func dashedPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        let dashed = path.cgPath.copy(dashingWithPhase: 0, lengths: [5, 4])
        return Path(dashed).strokedPath(
            StrokeStyle(lineWidth: 0.001, lineCap: .butt, lineJoin: .miter)
        )
    }

    private static func placementPoints(
        kind: ViewportCanvasPlacementPreviewKind,
        center: Point3D,
        coordinateSystem: SketchPlaneCoordinateSystem,
        defaults: WorkspaceScaleDefaults,
        visibleCellMeters: Double
    ) throws -> [Point3D] {
        let localCenter = coordinateSystem.project(center).point
        guard localCenter.x.isFinite, localCenter.y.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "Placement preview center is not finite in its sketch plane."
            )
        }
        switch kind {
        case .rectangle(let widthOverride, let heightOverride, let fallback):
            let fallbackWidth: Double
            let fallbackHeight: Double
            switch fallback {
            case .workspaceDefault:
                fallbackWidth = defaults.placedRectangleWidthMeters
                fallbackHeight = defaults.placedRectangleHeightMeters
            case .visibleCell:
                fallbackWidth = visibleCellMeters
                fallbackHeight = visibleCellMeters
            }
            let width = widthOverride ?? fallbackWidth
            let height = heightOverride ?? fallbackHeight
            guard width.isFinite, width > 0, height.isFinite, height > 0 else {
                throw RealityViewportSpatialBatch.invalid("Placement rectangle dimensions are invalid.")
            }
            let halfWidth = width / 2
            let halfHeight = height / 2
            let local = [
                Point2D(x: localCenter.x - halfWidth, y: localCenter.y - halfHeight),
                Point2D(x: localCenter.x + halfWidth, y: localCenter.y - halfHeight),
                Point2D(x: localCenter.x + halfWidth, y: localCenter.y + halfHeight),
                Point2D(x: localCenter.x - halfWidth, y: localCenter.y + halfHeight),
            ]
            return local.map(coordinateSystem.point(from:))
        case .polygon(let state, let radiusOverride, let rotationOverride):
            let draft = try CanvasSketchCurveDrafts.polygon(
                centeredAt: localCenter,
                sides: state.sideCount,
                sizingMode: state.sizingMode,
                inclinationMode: state.inclinationMode,
                defaults: defaults,
                radiusMeters: radiusOverride,
                rotationAngleRadians: rotationOverride
            )
            return draft.vertices.map(coordinateSystem.point(from:))
        case .arc(let radiusOverride, let spanOverride):
            let draft = try CanvasSketchCurveDrafts.arc(
                centeredAt: localCenter,
                defaults: defaults,
                radiusMeters: radiusOverride,
                spanAngleRadians: spanOverride
            )
            let span = normalizedArcSpan(
                startAngle: draft.startAngleRadians,
                endAngle: draft.endAngleRadians
            )
            return (0 ... 24).map { index in
                let t = Double(index) / 24
                let angle = draft.startAngleRadians + span * t
                return coordinateSystem.point(from: Point2D(
                    x: draft.center.x + cos(angle) * draft.radiusMeters,
                    y: draft.center.y + sin(angle) * draft.radiusMeters
                ))
            }
        case .spline:
            let draft = try CanvasSketchCurveDrafts.spline(
                centeredAt: localCenter,
                defaults: defaults
            )
            return cubicBezierPoints(controlPoints: draft.controlPoints, segmentCount: 32)
                .map(coordinateSystem.point(from:))
        case .circle(let radiusOverride):
            let radius = radiusOverride ?? defaults.curveRadiusMeters
            guard radius.isFinite, radius > 0 else {
                throw RealityViewportSpatialBatch.invalid("Placement circle radius is invalid.")
            }
            return (0 ... 48).map { index in
                let angle = Double(index) / 48 * Double.pi * 2
                return coordinateSystem.point(from: Point2D(
                    x: localCenter.x + cos(angle) * radius,
                    y: localCenter.y + sin(angle) * radius
                ))
            }
        }
    }

    private static func placementPreviewIsClosed(
        _ kind: ViewportCanvasPlacementPreviewKind
    ) -> Bool {
        switch kind {
        case .rectangle, .polygon, .circle:
            true
        case .arc, .spline:
            false
        }
    }

    private static func normalizedArcSpan(
        startAngle: Double,
        endAngle: Double
    ) -> Double {
        let twoPi = Double.pi * 2
        var span = endAngle - startAngle
        while span < 0 { span += twoPi }
        while span > twoPi { span -= twoPi }
        return span
    }

    private static func cubicBezierPoints(
        controlPoints: [Point2D],
        segmentCount: Int
    ) -> [Point2D] {
        guard controlPoints.count == 4 else { return [] }
        let count = max(segmentCount, 2)
        return (0 ... count).map { index in
            let t = Double(index) / Double(count)
            let inverse = 1 - t
            let a = inverse * inverse * inverse
            let b = 3 * inverse * inverse * t
            let c = 3 * inverse * t * t
            let d = t * t * t
            return Point2D(
                x: controlPoints[0].x * a + controlPoints[1].x * b
                    + controlPoints[2].x * c + controlPoints[3].x * d,
                y: controlPoints[0].y * a + controlPoints[1].y * b
                    + controlPoints[2].y * c + controlPoints[3].y * d
            )
        }
    }

    private static func sceneItem(
        for target: SelectionTarget,
        in scene: ViewportScene
    ) -> ViewportSceneItem? {
        scene.items.first { item in
            item.sceneNodeID == target.sceneNodeID
        }
    }

    static func midpoint(_ first: Point3D, _ second: Point3D) -> Point3D {
        Point3D(
            x: (first.x + second.x) * 0.5,
            y: (first.y + second.y) * 0.5,
            z: (first.z + second.z) * 0.5
        )
    }

    static func isFinitePoint(_ point: Point3D) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }

    private static func isFiniteVector(_ vector: Vector3D) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    private static func offset(
        _ point: Point3D,
        direction: Vector3D,
        distance: Double
    ) -> Point3D {
        Point3D(
            x: point.x + direction.x * distance,
            y: point.y + direction.y * distance,
            z: point.z + direction.z * distance
        )
    }

    private static func continuityColor(
        _ continuity: RupaCore.SurfaceContinuityResult.ContinuityLevel
    ) -> SIMD4<Float> {
        switch continuity {
        case .g0:
            SIMD4<Float>(0.95, 0.22, 0.18, 0.94)
        case .g1:
            SIMD4<Float>(0.26, 0.82, 0.47, 0.94)
        case .g2:
            SIMD4<Float>(0.27, 0.73, 1.0, 0.94)
        case .disconnected:
            SIMD4<Float>(0.98, 0.78, 0.18, 0.94)
        }
    }

    private static func continuityLabel(
        _ continuity: RupaCore.SurfaceContinuityResult.ContinuityLevel,
        requiresSolve: Bool
    ) -> String {
        let title: String
        switch continuity {
        case .disconnected:
            title = "DISCONNECTED"
        case .g0:
            title = "G0"
        case .g1:
            title = "G1"
        case .g2:
            title = "G2"
        }
        return requiresSolve ? "\(title) / G2 required" : title
    }

    private static func isObjectItem(
        _ item: ViewportSceneItem,
        selectedFeatures: Set<FeatureID>,
        selectedNodes: Set<SceneNodeID>
    ) -> Bool {
        if let sceneNodeID = item.sceneNodeID {
            return selectedNodes.contains(sceneNodeID)
        }
        return selectedFeatures.contains(item.featureID)
    }

    /// The world points the frame draws a sketch primitive's polyline through.
    ///
    /// A curved primitive is divided at the segment count it carries, which the scene resolved from
    /// the sketch object's declared subdivisions.
    ///
    /// It is internal because the native sketch entity query measures a pointer
    /// against these same points. A curve the frame samples and a curve a query
    /// idealises are different curves, and between two samples the difference
    /// is larger than the hit tolerance, so the query reads the producer that
    /// drew what is on screen rather than re-deriving a sampling of its own.
    static func sketchPrimitiveWorldPoints(
        _ primitive: ViewportSketchPrimitive
    ) throws -> [Point3D] {
        switch primitive {
        case .point(_, let point):
            return [Self.point(point)]
        case .line(_, let start, let end):
            return [Self.point(start), Self.point(end)]
        case .circle(_, let center, let radius, let segmentCount):
            guard radius.isFinite, radius > 0 else {
                throw RealityViewportSpatialBatch.invalid("Sketch circle radius is invalid.")
            }
            guard segmentCount >= 3 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Sketch circle segment count encloses no area."
                )
            }
            return (0 ... segmentCount).map { index in
                let angle = Double(index) / Double(segmentCount) * Double.pi * 2.0
                return Self.point(CGPoint(
                    x: center.x + CGFloat(cos(angle) * radius),
                    y: center.y + CGFloat(sin(angle) * radius)
                ))
            }
        case .arc(_, let center, let radius, let start, let end, let segmentCount):
            guard radius.isFinite, radius > 0,
                  start.isFinite, end.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Sketch arc parameters are invalid.")
            }
            guard segmentCount >= 2 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Sketch arc segment count draws a chord."
                )
            }
            let span = end - start
            return (0 ... segmentCount).map { index in
                let angle = start + span * Double(index) / Double(segmentCount)
                return Self.point(CGPoint(
                    x: center.x + CGFloat(cos(angle) * radius),
                    y: center.y + CGFloat(sin(angle) * radius)
                ))
            }
        case .spline(_, let points, _, _):
            guard points.count >= 2 else { return [] }
            return points.map { Self.point($0) }
        }
    }

    private static func primitiveIsClosed(_ primitive: ViewportSketchPrimitive) -> Bool {
        if case .circle = primitive { return true }
        return false
    }

    private static func fallbackBodyCorners(
        item: ViewportSceneItem,
        component: ViewportBodyComponent
    ) -> [Point3D] {
        let bounds = item.modelBounds
        let yMin = min(component.yMinMeters, component.yMaxMeters)
        let yMax = max(component.yMinMeters, component.yMaxMeters)
        let local = (0 ..< 8).map { index in
            Point3D(
                x: index & 1 == 0 ? Double(bounds.minX) : Double(bounds.maxX),
                y: index & 2 == 0 ? yMin : yMax,
                z: index & 4 == 0 ? Double(bounds.minY) : Double(bounds.maxY)
            )
        }
        return local.map { ViewportLayout.transformedPoint($0, by: item.modelTransform) }
    }

    private static func makeLines(
        _ points: [Point3D],
        color: SIMD4<Float>,
        depth: RealityViewportSpatialBatch.Depth = .scene
    ) throws -> RealityViewportSpatialBatch.Mesh {
        try line(points, color: color, depth: depth)
    }

    private static func counts(
        in input: ViewportSpatialOverlayInput
    ) -> [ViewportSpatialOverlayFamily: Int] {
        var result: [ViewportSpatialOverlayFamily: Int] = [:]
        if input.includesAxes { result[.axes] = 3 }
        for descriptor in input.meshes { result[descriptor.family, default: 0] += 1 }
        for descriptor in input.paths { result[descriptor.family, default: 0] += 1 }
        for descriptor in input.labels { result[descriptor.family, default: 0] += 1 }
        for descriptor in input.markers { result[descriptor.family, default: 0] += 1 }
        for descriptor in input.cameraLines { result[descriptor.family, default: 0] += 1 }
        for descriptor in input.cameraPaths { result[descriptor.family, default: 0] += 1 }
        if input.gridPlacement != nil {
            result[.placement, default: 0] += 1
        }
        if input.boundsRuler != nil {
            result[.measurement, default: 0] += 1
        }
        return result
    }
}

extension ViewportSpatialOverlayProducer {
    static func handleIndex(
        for target: ViewportSpatialPreparedInteractionTarget,
        occurrenceID: String? = nil,
        modelTransform: Transform3D = .identity,
        in table: inout [ViewportSpatialInteractionRecord]
    ) throws -> UInt32 {
        let record = try ViewportSpatialInteractionRecord(
            target: target, occurrenceID: occurrenceID, modelTransform: modelTransform
        )
        // ponytail: the admitted table has at most 640 entries; no second index is needed.
        for existing in table {
            try Task.checkCancellation()
            guard existing.identity != record.identity || existing.occurrenceID != record.occurrenceID else {
                throw RealityViewportSpatialBatch.invalid("A semantic handle was registered more than once in one frame.")
            }
        }
        let limits = MeshSourcePresentationPlanLimits.standard
        guard table.count < limits.maxItemCount else { throw RealityViewportSpatialBatch.exhausted() }
        let previousBytes = try ViewportSpatialInteractionRecord.retainedByteCount(for: table)
        let addedBytes = try ViewportSpatialInteractionRecord.retainedByteCount(for: [record])
        let projected = previousBytes.addingReportingOverflow(addedBytes)
        let growth = table.count == table.capacity
            ? max(table.capacity, 1) * MemoryLayout<ViewportSpatialInteractionRecord>.stride : 0
        let total = projected.partialValue.addingReportingOverflow(growth)
        guard !projected.overflow, !total.overflow,
              total.partialValue <= limits.maxRetainedByteCount else { throw RealityViewportSpatialBatch.exhausted() }
        let index = UInt32(table.count)
        table.append(record)
        return index
    }

    static func handleIndex(
        for identity: ViewportSpatialHandleIdentity,
        occurrenceID: String? = nil,
        in table: [ViewportSpatialInteractionRecord]
    ) throws -> UInt32 {
        for (index, record) in table.enumerated() {
            try Task.checkCancellation()
            if record.identity == identity && record.occurrenceID == occurrenceID { return UInt32(index) }
        }
        throw RealityViewportSpatialBatch.invalid("A native handle fragment has no registered semantic baseline.")
    }

    static let selectionColor = SIMD4<Float>(0.14, 0.66, 0.95, 1.0)
    static let hoverColor = SIMD4<Float>(0.24, 0.88, 0.82, 1.0)
    static let sketchColor = SIMD4<Float>(0.34, 0.62, 1.0, 0.92)
    static let curveColor = SIMD4<Float>(0.96, 0.72, 0.24, 1.0)
    static let bodyColor = SIMD4<Float>(0.62, 0.64, 0.62, 0.50)
    static let gridMinorColor = SIMD4<Float>(1.0, 1.0, 1.0, 0.055)
    static let gridMajorColor = SIMD4<Float>(1.0, 1.0, 1.0, 0.135)
    static let gridOriginColor = SIMD4<Float>(1.0, 1.0, 1.0, 0.22)
    static let sectionPlaneColor = SIMD4<Float>(0.18, 0.82, 0.94, 0.20)
    static let sectionColor = SIMD4<Float>(0.98, 0.84, 0.26, 0.95)
    static let sectionNormalColor = SIMD4<Float>(0.46, 0.74, 1.0, 0.90)
    static let analysisColor = SIMD4<Float>(0.28, 0.86, 0.64, 0.84)
    static let continuityColor = SIMD4<Float>(0.97, 0.60, 0.16, 0.94)
    static let referenceColor = SIMD4<Float>(0.25, 0.92, 1.0, 0.70)
    static let measurementColor = SIMD4<Float>(0.25, 0.92, 1.0, 1.0)
    static let editColor = SIMD4<Float>(1.0, 0.78, 0.28, 1.0)

    static func point(_ point: CGPoint, y: Double = 0.0) -> Point3D {
        Point3D(x: Double(point.x), y: y, z: Double(point.y))
    }

    static func line(
        _ points: [Point3D],
        color: SIMD4<Float>,
        depth: RealityViewportSpatialBatch.Depth = .scene
    ) throws -> RealityViewportSpatialBatch.Mesh {
        guard points.count >= 2 else {
            throw RealityViewportSpatialBatch.invalid("A spatial line requires at least two world points.")
        }
        var indices: [UInt32] = []
        indices.reserveCapacity((points.count - 1) * 2)
        for index in 0 ..< points.count - 1 {
            indices.append(UInt32(index))
            indices.append(UInt32(index + 1))
        }
        return RealityViewportSpatialBatch.Mesh(
            positions: points,
            indices: indices,
            topology: .lines,
            color: color,
            depth: depth
        )
    }

    static func closedLine(
        _ points: [Point3D],
        color: SIMD4<Float>,
        depth: RealityViewportSpatialBatch.Depth = .scene
    ) throws -> RealityViewportSpatialBatch.Mesh {
        guard points.count >= 3 else {
            throw RealityViewportSpatialBatch.invalid("A closed spatial line requires three world points.")
        }
        return try line(points + [points[0]], color: color, depth: depth)
    }

    static func diamondPath(radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -radius))
        path.addLine(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addLine(to: CGPoint(x: -radius, y: 0))
        path.closeSubpath()
        return path
    }

    static func squarePath(radius: CGFloat) -> Path {
        Path(CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
    }

    static func circlePath(radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
    }

    static func trianglePath(radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -radius))
        path.addLine(to: CGPoint(x: radius, y: radius))
        path.addLine(to: CGPoint(x: -radius, y: radius))
        path.closeSubpath()
        return path
    }

    static func triangles(
        _ points: [Point3D],
        color: SIMD4<Float>,
        depth: RealityViewportSpatialBatch.Depth = .scene
    ) throws -> RealityViewportSpatialBatch.Mesh {
        guard points.count >= 3, points.count.isMultiple(of: 3) else {
            throw RealityViewportSpatialBatch.invalid("A spatial triangle mesh has an incomplete primitive.")
        }
        return RealityViewportSpatialBatch.Mesh(
            positions: points,
            indices: points.indices.map(UInt32.init),
            topology: .triangles,
            color: color,
            depth: depth
        )
    }

    static func polygonFill(
        _ polygon: [Point3D],
        color: SIMD4<Float>,
        depth: RealityViewportSpatialBatch.Depth = .scene
    ) throws -> RealityViewportSpatialBatch.PlanarPath {
        try Task.checkCancellation()
        guard polygon.count >= 3 else {
            throw RealityViewportSpatialBatch.invalid("A polygon fill requires three world points.")
        }
        guard polygon.count <= MeshSourcePresentationPlanLimits.standard.maxPositionCount else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        let origin = polygon[0]
        let base = SIMD3<Double>(origin.x, origin.y, origin.z)
        var xAxis = SIMD3<Double>.zero
        var normal = SIMD3<Double>.zero
        for point in polygon {
            try Task.checkCancellation()
            guard isFinitePoint(point) else {
                throw RealityViewportSpatialBatch.invalid("A polygon fill contains a nonfinite point.")
            }
            let delta = SIMD3<Double>(point.x, point.y, point.z) - base
            if xAxis == .zero, simd_length_squared(delta) > 0 {
                xAxis = simd_normalize(delta)
            }
            let candidate = simd_cross(xAxis, delta)
            if simd_length_squared(candidate) > simd_length_squared(normal) {
                normal = candidate
            }
        }
        guard simd_length_squared(normal) > 0 else {
            throw RealityViewportSpatialBatch.invalid("A polygon fill has a degenerate plane.")
        }
        let yAxis = simd_cross(simd_normalize(normal), xAxis)
        var path = Path()
        for (index, point) in polygon.enumerated() {
            try Task.checkCancellation()
            let delta = SIMD3<Double>(point.x, point.y, point.z) - base
            let projected = CGPoint(x: simd_dot(delta, xAxis), y: simd_dot(delta, yAxis))
            if index == 0 { path.move(to: projected) } else { path.addLine(to: projected) }
        }
        path.closeSubpath()
        return .init(path: path, origin: origin, xAxis: xAxis, yAxis: yAxis,
                     color: color, depth: depth)
    }

    static func cameraLine(
        anchors: [Point3D],
        offsets: [CGPoint] = [],
        color: SIMD4<Float>,
        depth: RealityViewportSpatialBatch.Depth = .annotation
    ) throws -> RealityViewportSpatialBatch.CameraLine {
        guard anchors.count >= 2 else {
            throw RealityViewportSpatialBatch.invalid("A camera-relative line requires two world anchors.")
        }
        let resolvedOffsets = offsets.count == anchors.count
            ? offsets
            : Array(repeating: .zero, count: anchors.count)
        guard resolvedOffsets.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw RealityViewportSpatialBatch.invalid("Camera-relative line offset is not finite.")
        }
        return RealityViewportSpatialBatch.CameraLine(
            points: zip(anchors, resolvedOffsets).map {
                RealityViewportSpatialBatch.CameraPoint(
                    anchor: $0.0,
                    offset: .fixed($0.1)
                )
            },
            color: color,
            depth: depth
        )
    }

    static func label(
        _ text: String,
        anchor: Point3D,
        offset: CGPoint = .zero,
        color: SIMD4<Float>,
        alignment: RealityViewportSpatialBatch.Label.Alignment = .leading,
        depth: RealityViewportSpatialBatch.Depth = .annotation,
        heightPoints: Float = 10.0
    ) throws -> RealityViewportSpatialBatch.Label {
        guard !text.isEmpty else {
            throw RealityViewportSpatialBatch.invalid("A spatial label cannot be empty.")
        }
        return RealityViewportSpatialBatch.Label(
            text: text,
            anchor: anchor,
            offset: .fixed(offset),
            heightPoints: heightPoints,
            color: color,
            alignment: alignment,
            depth: depth
        )
    }

    static func marker(
        _ shape: RealityViewportSpatialBatch.Marker.Shape = .sphere,
        anchor: Point3D,
        diameterPoints: Float = 7.0,
        color: SIMD4<Float>,
        depth: RealityViewportSpatialBatch.Depth = .annotation
    ) -> RealityViewportSpatialBatch.Marker {
        RealityViewportSpatialBatch.Marker(
            shape: shape,
            anchor: anchor,
            diameterPoints: diameterPoints,
            color: color,
            depth: depth
        )
    }
}
