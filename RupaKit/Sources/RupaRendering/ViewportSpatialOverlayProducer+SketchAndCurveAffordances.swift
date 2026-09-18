import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI

extension ViewportSpatialOverlayProducer {
    /// Production draw routes owned by the sketch/curve affordance producer.
    /// These identifiers intentionally describe the source route rather than
    /// the coarse spatial-overlay family.
    enum SketchCurveAffordanceRoute: String, CaseIterable, Hashable, Sendable {
        case lineDimension
        case circleDimension
        case arcDimension
        case curvePointControl
        case splineControl
        case curvatureComb
        case regionOffset
        case edgeOffset
        case slotWidth
        case sketchVertexOffset
        case splineSlide
        case bridgeCurveEndpoint
    }

    enum SketchCurveAffordanceState: String, CaseIterable, Hashable, Sendable {
        case normal
        case hovered
        case pending
        case active
        case preview
    }

    /// Main-actor interaction values normalized to stable identities before
    /// they cross into the cancellable worker. The producer never retains a
    /// mutable interaction target or drag coordinator.
    struct SketchCurveInteractionCapture: Sendable {
        struct Highlight: Sendable {
            let identity: ViewportSpatialHandleIdentity
            let state: SketchCurveAffordanceState

            init(
                identity: ViewportSpatialHandleIdentity,
                state: SketchCurveAffordanceState
            ) {
                self.identity = identity
                self.state = state
            }
        }

        let active: [Highlight]
        let hovered: ViewportSpatialHandleIdentity?
        let pending: ViewportSpatialHandleIdentity?
        let preview: ViewportSpatialHandleIdentity?

        init(
            active: [Highlight] = [],
            hovered: ViewportSpatialHandleIdentity? = nil,
            pending: ViewportSpatialHandleIdentity? = nil,
            preview: ViewportSpatialHandleIdentity? = nil
        ) {
            self.active = active
            self.hovered = hovered
            self.pending = pending
            self.preview = preview
        }

        static let empty = Self()
    }

    enum SketchCurveAffordanceRole: String, CaseIterable, Hashable, Sendable {
        case lineLength
        case lineAngle
        case circleRadius
        case arcRadius
        case arcAngle
        case curvePoint
        case curveHandle
        case splineControlNet
        case splineControlPoint
        case curvatureNormal
        case curvatureSpine
        case offset
        case slide
        case bridgeEndpoint
    }

    /// One camera-independent point that can be resolved by the native camera
    /// into a constant-pixel offset.  It stores a world direction reference,
    /// never a screen coordinate.
    struct SketchCurveDirectedPoint: Sendable {
        let anchor: Point3D
        let toward: Point3D
        let parallel: Double
        let perpendicular: Double
        let minimumLength: Double?

        init(
            anchor: Point3D,
            toward: Point3D,
            parallel: Double = 0.0,
            perpendicular: Double = 0.0,
            minimumLength: Double? = nil
        ) {
            self.anchor = anchor
            self.toward = toward
            self.parallel = parallel
            self.perpendicular = perpendicular
            self.minimumLength = minimumLength
        }
    }

    struct SketchCurveCameraGuide: Sendable {
        let points: [SketchCurveDirectedPoint]
        let color: SIMD4<Float>?

        init(points: [SketchCurveDirectedPoint], color: SIMD4<Float>? = nil) {
            self.points = points
            self.color = color
        }
    }

    struct SketchCurveLabelSource: Sendable {
        let text: String
        let point: SketchCurveDirectedPoint
        let heightPoints: Float
        let alignment: RealityViewportSpatialBatch.Label.Alignment
        let color: SIMD4<Float>?
        let hitRectPoints: CGRect?

        init(
            text: String,
            point: SketchCurveDirectedPoint,
            heightPoints: Float = 10.0,
            alignment: RealityViewportSpatialBatch.Label.Alignment = .center,
            color: SIMD4<Float>? = nil,
            hitRectPoints: CGRect? = nil
        ) {
            self.text = text
            self.point = point
            self.heightPoints = heightPoints
            self.alignment = alignment
            self.color = color
            self.hitRectPoints = hitRectPoints
        }
    }

    struct SketchCurveMarkerSource: Sendable {
        let anchor: Point3D
        let diameterPoints: Float
        let shape: RealityViewportSpatialBatch.Marker.Shape
        let color: SIMD4<Float>?

        init(
            anchor: Point3D,
            diameterPoints: Float = 8.0,
            shape: RealityViewportSpatialBatch.Marker.Shape = .sphere,
            color: SIMD4<Float>? = nil
        ) {
            self.anchor = anchor
            self.diameterPoints = diameterPoints
            self.shape = shape
            self.color = color
        }
    }

    struct SketchCurveCameraPathSource: Sendable {
        let path: Path
        let placement: SketchCurveDirectedPoint
        let color: SIMD4<Float>?
        let hitTolerancePoints: Float?

        init(
            path: Path,
            placement: SketchCurveDirectedPoint,
            color: SIMD4<Float>? = nil,
            hitTolerancePoints: Float? = nil
        ) {
            self.path = path
            self.placement = placement
            self.color = color
            self.hitTolerancePoints = hitTolerancePoints
        }
    }

    struct SketchCurveCurvatureSample: Sendable {
        let point: Point3D
        let normal: Vector3D
        let curvature: Double

        init(point: Point3D, normal: Vector3D, curvature: Double) {
            self.point = point
            self.normal = normal
            self.curvature = curvature
        }
    }

    enum SketchCurveWorldGeometry: Sendable {
        case none
        case polyline([Point3D])
        case curvature(samples: [SketchCurveCurvatureSample], scaleFactor: Double)
    }

    /// A raw, immutable source value captured at the MainActor boundary.
    /// `document`, `scene`, and `selection` remain available to worker-side
    /// route builders (notably bridge endpoint resolution); camera,
    /// layout, and screen candidates are deliberately absent.
    struct SketchCurveAffordanceSource: Sendable {
        /// A value-only interaction override captured before the worker starts.
        /// Geometry is still resolved from the immutable scene on the worker;
        /// this type carries only the current numeric edit value and identity.
        struct ActiveOverride: Sendable {
            let identity: ViewportSpatialHandleIdentity
            let state: SketchCurveAffordanceState
            /// Optional raw world value for a drag that has not been committed
            /// to the document yet. These values are model-space, never
            /// projected screen coordinates.
            let anchor: Point3D?
            let toward: Point3D?
            let endpoint: Point3D?
            let tangent: Vector3D?
            let bridgeEndpoint: BridgeCurveEndpoint?
            let bridgeParameter: Double?
            let deltaX: Double?
            let deltaY: Double?
            let value: Double?
            let distanceMeters: Double?
            let widthMeters: Double?
            let radiusMeters: Double?
            let startAngleRadians: Double?
            let endAngleRadians: Double?
            let selectedControlPointIndexes: [Int]
            let slideDirection: SplineControlPointSlideDirection?

            init(
                identity: ViewportSpatialHandleIdentity,
                state: SketchCurveAffordanceState = .active,
                anchor: Point3D? = nil,
                toward: Point3D? = nil,
                endpoint: Point3D? = nil,
                tangent: Vector3D? = nil,
                bridgeEndpoint: BridgeCurveEndpoint? = nil,
                bridgeParameter: Double? = nil,
                deltaX: Double? = nil,
                deltaY: Double? = nil,
                value: Double? = nil,
                distanceMeters: Double? = nil,
                widthMeters: Double? = nil,
                radiusMeters: Double? = nil,
                startAngleRadians: Double? = nil,
                endAngleRadians: Double? = nil,
                selectedControlPointIndexes: [Int] = [],
                slideDirection: SplineControlPointSlideDirection? = nil
            ) {
                self.identity = identity
                self.state = state
                self.anchor = anchor
                self.toward = toward
                self.endpoint = endpoint
                self.tangent = tangent
                self.bridgeEndpoint = bridgeEndpoint
                self.bridgeParameter = bridgeParameter
                self.deltaX = deltaX
                self.deltaY = deltaY
                self.value = value
                self.distanceMeters = distanceMeters
                self.widthMeters = widthMeters
                self.radiusMeters = radiusMeters
                self.startAngleRadians = startAngleRadians
                self.endAngleRadians = endAngleRadians
                self.selectedControlPointIndexes = selectedControlPointIndexes
                self.slideDirection = slideDirection
            }
        }

        /// The complete raw input crossing the MainActor/worker boundary.
        /// Nothing in this value is projected, layout-dependent, or a native
        /// descriptor. Route geometry is materialized by the worker.
        struct RawInput: Sendable {
            let document: DesignDocument
            let scene: ViewportScene
            let selection: SelectionModel
            let interaction: SketchCurveInteractionCapture
            let overlayState: ViewportSceneOverlayState
            let ruler: RulerConfiguration
            let enabledRoutes: Set<SketchCurveAffordanceRoute>
            let activeOverrides: [ActiveOverride]
            let includeSelectedBridgeEndpoints: Bool
            let bridgeState: SketchCurveAffordanceState
            let bridgeGuideLengthMeters: Double
            let slotWidthMeters: Double
            let sketchVertexOffsetDistanceMeters: Double
            let edgeOffsetDistanceMeters: Double

            init(
                document: DesignDocument,
                scene: ViewportScene,
                selection: SelectionModel,
                interaction: SketchCurveInteractionCapture = .empty,
                overlayState: ViewportSceneOverlayState = .empty,
                ruler: RulerConfiguration,
                enabledRoutes: Set<SketchCurveAffordanceRoute> = Set(SketchCurveAffordanceRoute.allCases),
                activeOverrides: [ActiveOverride] = [],
                includeSelectedBridgeEndpoints: Bool = false,
                bridgeState: SketchCurveAffordanceState = .normal,
                bridgeGuideLengthMeters: Double = 0.034,
                slotWidthMeters: Double? = nil,
                sketchVertexOffsetDistanceMeters: Double? = nil,
                edgeOffsetDistanceMeters: Double? = nil
            ) {
                self.document = document
                self.scene = scene
                self.selection = selection
                self.interaction = interaction
                self.overlayState = overlayState
                self.ruler = ruler
                self.enabledRoutes = enabledRoutes
                self.activeOverrides = activeOverrides
                self.includeSelectedBridgeEndpoints = includeSelectedBridgeEndpoints
                self.bridgeState = bridgeState
                self.bridgeGuideLengthMeters = bridgeGuideLengthMeters
                let interactionDefaults = WorkspaceInteractionScaleDefaults(ruler: ruler)
                self.slotWidthMeters = slotWidthMeters ?? interactionDefaults.slotWidthMeters
                self.sketchVertexOffsetDistanceMeters = sketchVertexOffsetDistanceMeters
                    ?? interactionDefaults.operationStepMeters
                self.edgeOffsetDistanceMeters = edgeOffsetDistanceMeters
                    ?? interactionDefaults.operationStepMeters
            }
        }

        struct DimensionLabels: Sendable {
            let length: String?
            let radius: String?
            let angle: String?

            init(length: String? = nil, radius: String? = nil, angle: String? = nil) {
                self.length = length
                self.radius = radius
                self.angle = angle
            }
        }

        struct Primitive: Sendable {
            let featureID: FeatureID
            let primitive: ViewportSketchPrimitive
            let sourcePrimitive: ViewportSketchPrimitive?
            let sketchPlane: SketchPlane
            let modelTransform: Transform3D
            let selectionTarget: SelectionTarget?
            let state: SketchCurveAffordanceState
            let showsPointHandles: Bool
            let showsCurveHandles: Bool
            let showsDimensions: Bool
            let showsCurvature: Bool
            let curvatureScale: Double
            let labels: DimensionLabels

            init(
                featureID: FeatureID,
                primitive: ViewportSketchPrimitive,
                sketchPlane: SketchPlane,
                sourcePrimitive: ViewportSketchPrimitive? = nil,
                modelTransform: Transform3D = .identity,
                selectionTarget: SelectionTarget? = nil,
                state: SketchCurveAffordanceState = .normal,
                showsPointHandles: Bool = true,
                showsCurveHandles: Bool = true,
                showsDimensions: Bool = false,
                showsCurvature: Bool = false,
                curvatureScale: Double = CurveCurvatureDisplay.defaultCombScale,
                labels: DimensionLabels = .init()
            ) {
                self.featureID = featureID
                self.primitive = primitive
                self.sourcePrimitive = sourcePrimitive
                self.sketchPlane = sketchPlane
                self.modelTransform = modelTransform
                self.selectionTarget = selectionTarget
                self.state = state
                self.showsPointHandles = showsPointHandles
                self.showsCurveHandles = showsCurveHandles
                self.showsDimensions = showsDimensions
                self.showsCurvature = showsCurvature
                self.curvatureScale = curvatureScale
                self.labels = labels
            }
        }

        struct Entry: Sendable {
            let route: SketchCurveAffordanceRoute
            let role: SketchCurveAffordanceRole
            let state: SketchCurveAffordanceState
            let identity: ViewportSpatialHandleIdentity?
            let world: SketchCurveWorldGeometry
            let cameraGuides: [SketchCurveCameraGuide]
            let cameraPaths: [SketchCurveCameraPathSource]
            let labels: [SketchCurveLabelSource]
            let markers: [SketchCurveMarkerSource]
            let family: ViewportSpatialOverlayFamily
            let preparedTarget: ViewportSpatialPreparedInteractionTarget?
            var occurrenceID: String? = nil
            var modelTransform: Transform3D = .identity

            init(
                route: SketchCurveAffordanceRoute,
                role: SketchCurveAffordanceRole,
                state: SketchCurveAffordanceState,
                identity: ViewportSpatialHandleIdentity? = nil,
                world: SketchCurveWorldGeometry = .none,
                cameraGuides: [SketchCurveCameraGuide] = [],
                cameraPaths: [SketchCurveCameraPathSource] = [],
                labels: [SketchCurveLabelSource] = [],
                markers: [SketchCurveMarkerSource] = [],
                family: ViewportSpatialOverlayFamily? = nil,
                preparedTarget: ViewportSpatialPreparedInteractionTarget? = nil
            ) {
                self.route = route
                self.role = role
                self.state = state
                self.identity = identity
                self.world = world
                self.cameraGuides = cameraGuides
                self.cameraPaths = cameraPaths
                self.labels = labels
                self.markers = markers
                self.family = family ?? Self.defaultFamily(for: route)
                self.preparedTarget = preparedTarget
            }

            private static func defaultFamily(
                for route: SketchCurveAffordanceRoute
            ) -> ViewportSpatialOverlayFamily {
                switch route {
                case .edgeOffset:
                    .body
                case .bridgeCurveEndpoint, .curvePointControl, .curvatureComb:
                    .curve
                case .lineDimension, .circleDimension, .arcDimension,
                     .splineControl, .regionOffset, .slotWidth,
                     .sketchVertexOffset, .splineSlide:
                    .sketch
                }
            }
        }

        let input: RawInput

        init(raw input: RawInput) {
            self.input = input
        }

        var document: DesignDocument { input.document }
        var scene: ViewportScene { input.scene }
        var selection: SelectionModel { input.selection }
        var interaction: SketchCurveInteractionCapture { input.interaction }
        var overlayState: ViewportSceneOverlayState { input.overlayState }
        var ruler: RulerConfiguration { input.ruler }
        var enabledRoutes: Set<SketchCurveAffordanceRoute> { input.enabledRoutes }
        var activeOverrides: [ActiveOverride] { input.activeOverrides }
        var includeSelectedBridgeEndpoints: Bool { input.includeSelectedBridgeEndpoints }
        var bridgeState: SketchCurveAffordanceState { input.bridgeState }
        var bridgeGuideLengthMeters: Double { input.bridgeGuideLengthMeters }
        var slotWidthMeters: Double { input.slotWidthMeters }
        var sketchVertexOffsetDistanceMeters: Double { input.sketchVertexOffsetDistanceMeters }
        var edgeOffsetDistanceMeters: Double { input.edgeOffsetDistanceMeters }
    }

    /// Builds the immutable worker source from raw document state.  The
    /// closure is deliberately the only place where scene traversal occurs;
    /// callers capture values on the MainActor and never pass precomputed
    /// primitives or descriptors across the boundary.
    static func makeSketchCurveAffordanceSource(
        from input: SketchCurveAffordanceSource.RawInput,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> SketchCurveAffordanceSource? {
        try Task.checkCancellation()
        try input.ruler.validate()
        guard !input.enabledRoutes.isEmpty else { return nil }
        try checkpoint(0, 0, 1)
        return SketchCurveAffordanceSource(raw: input)
    }

    /// Appends every sketch/curve affordance descriptor represented by raw
    /// immutable source state. All geometry is world-space or world-directed;
    /// no camera or screen candidate is evaluated here.
    static func appendSketchCurveAffordances(
        from input: SketchCurveAffordanceSource.RawInput,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        paths: inout [ViewportSpatialOverlayInput.Path],
        labels: inout [ViewportSpatialOverlayInput.Label],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        cameraLines: inout [ViewportSpatialOverlayInput.CameraLine],
        cameraPaths: inout [ViewportSpatialOverlayInput.CameraPath],
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        guard let source = try makeSketchCurveAffordanceSource(
            from: input,
            checkpoint: checkpoint
        ) else {
            return
        }
        try appendSketchCurveAffordances(
            from: source,
            meshes: &meshes,
            paths: &paths,
            labels: &labels,
            markers: &markers,
            cameraLines: &cameraLines,
            cameraPaths: &cameraPaths,
            interactionRecords: &interactionRecords,
            activeFamilies: &activeFamilies,
            checkpoint: checkpoint
        )
    }

    /// Worker-only overload. The source contains raw values only; entries are
    /// generated immediately before append and never retained by the source.
    private static func appendSketchCurveAffordances(
        from source: SketchCurveAffordanceSource,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        paths: inout [ViewportSpatialOverlayInput.Path],
        labels: inout [ViewportSpatialOverlayInput.Label],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        cameraLines: inout [ViewportSpatialOverlayInput.CameraLine],
        cameraPaths: inout [ViewportSpatialOverlayInput.CameraPath],
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try Task.checkCancellation()
        do {
            try source.ruler.validate()
        } catch {
            throw RealityViewportSpatialBatch.invalid(
                "Sketch/curve affordance source has an invalid ruler configuration."
            )
        }
        var resolvedEntries: [SketchCurveAffordanceSource.Entry] = []
        let limits = MeshSourcePresentationPlanLimits.standard
        resolvedEntries = try entries(
            from: source,
            checkpoint: checkpoint
        )
        guard resolvedEntries.count <= limits.maxItemCount else {
            throw RealityViewportSpatialBatch.exhausted()
        }

        if source.enabledRoutes.contains(.bridgeCurveEndpoint) {
            guard source.bridgeGuideLengthMeters.isFinite,
                  source.bridgeGuideLengthMeters > 0.0 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Bridge endpoint guide length must be positive and finite."
                )
            }
            let handles = try BridgeCurveEndpointHandleService().handles(
                for: source.selection,
                in: source.document
            )
            let nextCount = resolvedEntries.count.addingReportingOverflow(handles.count)
            guard !nextCount.overflow,
                  nextCount.partialValue <= limits.maxItemCount else {
                throw RealityViewportSpatialBatch.exhausted()
            }
            for handle in handles {
                try Task.checkCancellation()
                var matchedOccurrence = false
                for item in source.scene.items where item.featureID == handle.featureID {
                    guard selectedSketchTarget(item: item, featureID: handle.featureID,
                                               entityID: handle.bridgeEntityID,
                                               selection: source.selection) != nil else { continue }
                    matchedOccurrence = true
                let identity = ViewportSpatialHandleIdentity.bridgeCurveEndpoint(.init(
                    sourceID: handle.sourceID,
                    role: handle.role
                ))
                let override = activeOverride(identity, in: source.activeOverrides)
                var resolvedHandle = handle
                if let endpoint = override?.bridgeEndpoint,
                   let parameter = override?.bridgeParameter {
                    guard parameter.isFinite,
                          parameter >= 0.0,
                          parameter <= 1.0 else {
                        throw RealityViewportSpatialBatch.invalid(
                            "Bridge endpoint preview parameter must be finite and within the unit interval."
                        )
                    }
                    let parameterizedEndpoint = BridgeCurveEndpoint(
                        reference: endpoint.reference,
                        parameter: .scalar(parameter),
                        reversesSense: endpoint.reversesSense,
                        trimSide: endpoint.trimSide,
                        tension: endpoint.tension
                    )
                    guard let sample = try bridgeEndpointSample(
                        for: parameterizedEndpoint,
                        parameter: parameter,
                        handle: handle,
                        item: item,
                        document: source.document
                    ) else {
                        throw RealityViewportSpatialBatch.invalid(
                            "Bridge endpoint preview could not resolve its source curve sample."
                        )
                    }
                    resolvedHandle.endpoint = parameterizedEndpoint
                    resolvedHandle.point = sample.point
                    resolvedHandle.outgoingTangent = sample.tangent
                }
                var entry = try bridgeEndpointEntry(
                        handle: resolvedHandle,
                        preparedHandle: handle,
                        modelTransform: item.modelTransform,
                        state: override?.state ?? source.bridgeState,
                        guideLengthMeters: source.bridgeGuideLengthMeters,
                        override: override
                    )
                entry.occurrenceID = item.id
                entry.modelTransform = item.modelTransform
                try append(entry, to: &resolvedEntries, limits: limits)
                }
                guard matchedOccurrence else {
                    throw RealityViewportSpatialBatch.invalid("Bridge endpoint source has no matching selected occurrence.")
                }
            }
        }

        for entry in resolvedEntries {
            try Task.checkCancellation()
            guard source.enabledRoutes.contains(entry.route) else { continue }
            try append(
                entry,
                interaction: source.interaction,
                activeOverrides: source.activeOverrides,
                meshes: &meshes,
                paths: &paths,
                labels: &labels,
                markers: &markers,
                cameraLines: &cameraLines,
                cameraPaths: &cameraPaths,
                interactionRecords: &interactionRecords,
                activeFamilies: &activeFamilies
            )
        }
    }

    private static func append(
        _ entry: SketchCurveAffordanceSource.Entry,
        interaction: SketchCurveInteractionCapture,
        activeOverrides: [SketchCurveAffordanceSource.ActiveOverride],
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        paths: inout [ViewportSpatialOverlayInput.Path],
        labels: inout [ViewportSpatialOverlayInput.Label],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        cameraLines: inout [ViewportSpatialOverlayInput.CameraLine],
        cameraPaths: inout [ViewportSpatialOverlayInput.CameraPath],
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        let handleIndex = try entry.preparedTarget.map {
            try Self.handleIndex(for: $0, occurrenceID: entry.occurrenceID,
                                 modelTransform: entry.modelTransform, in: &interactionRecords)
        }
        let state = state(
            for: entry,
            interaction: interaction,
            activeOverrides: activeOverrides
        )
        let color = color(for: state, role: entry.role)
        var descriptorCount = 0

        let isOffsetRoute: Bool = switch entry.route {
        case .regionOffset, .edgeOffset, .slotWidth, .sketchVertexOffset, .splineSlide:
            true
        case .lineDimension, .circleDimension, .arcDimension, .curvePointControl,
             .splineControl, .curvatureComb, .bridgeCurveEndpoint:
            false
        }
        let isDimensionRoute: Bool = switch entry.route {
        case .lineDimension, .circleDimension, .arcDimension: true
        case .curvePointControl, .splineControl, .curvatureComb, .regionOffset,
             .edgeOffset, .slotWidth, .sketchVertexOffset, .splineSlide,
             .bridgeCurveEndpoint: false
        }
        let markerTolerance: Float? = switch entry.route {
        case .curvePointControl, .splineControl, .bridgeCurveEndpoint:
            handleIndex == nil ? nil : 12.0
        case .regionOffset, .edgeOffset, .slotWidth, .sketchVertexOffset, .splineSlide:
            handleIndex == nil ? nil : 14.0
        case .lineDimension, .circleDimension, .arcDimension, .curvatureComb:
            nil
        }

        func appendMesh(_ mesh: RealityViewportSpatialBatch.Mesh) {
            var value = mesh
            value.handleIndex = nil
            value.hitTolerancePoints = nil
            meshes.append(.init(family: entry.family, value: value))
            descriptorCount += 1
        }
        func appendCameraLine(
            _ line: RealityViewportSpatialBatch.CameraLine,
            interactive: Bool = false
        ) {
            var value = line
            value.handleIndex = interactive ? handleIndex : nil
            value.hitTolerancePoints = interactive ? 10.0 : nil
            value.objectPreviewOccurrenceID = entry.occurrenceID
            cameraLines.append(.init(family: entry.family, value: value))
            descriptorCount += 1
        }
        func appendCameraPath(
            _ source: SketchCurveCameraPathSource
        ) throws {
            let point = source.placement
            guard point.parallel.isFinite,
                  point.perpendicular.isFinite,
                  point.anchor.isFinite,
                  point.toward.isFinite,
                  point.minimumLength?.isFinite ?? true,
                  point.minimumLength.map({ $0 >= 0.0 }) ?? true,
                  source.hitTolerancePoints.map({ $0.isFinite && $0 >= 0.0 }) ?? true else {
                throw RealityViewportSpatialBatch.invalid(
                    "Sketch/curve camera path placement is not finite."
                )
            }
            let offset: RealityViewportSpatialBatch.Offset
            if let minimumLength = point.minimumLength {
                offset = .projected(
                    toward: point.toward,
                    minimumLength: CGFloat(minimumLength),
                    parallel: CGFloat(point.parallel),
                    perpendicular: CGFloat(point.perpendicular)
                )
            } else {
                offset = .directed(
                    toward: point.toward,
                    parallel: CGFloat(point.parallel),
                    perpendicular: CGFloat(point.perpendicular)
                )
            }
            var value = RealityViewportSpatialBatch.CameraPath(
                path: source.path,
                anchor: point.anchor,
                offset: offset,
                color: source.color ?? color,
                depth: .annotation
            )
            value.handleIndex = source.hitTolerancePoints == nil ? nil : handleIndex
            value.hitTolerancePoints = source.hitTolerancePoints
            value.objectPreviewOccurrenceID = entry.occurrenceID
            cameraPaths.append(.init(family: entry.family, value: value))
            descriptorCount += 1
        }
        func appendLabel(
            _ label: RealityViewportSpatialBatch.Label,
            interactive: Bool = false
        ) {
            var value = label
            value.handleIndex = interactive ? handleIndex : nil
            value.hitRectPoints = interactive
                ? (label.hitRectPoints ?? Self.dimensionHitRectPoints(for: label.text))
                : nil
            labels.append(.init(family: entry.family, value: value))
            descriptorCount += 1
        }
        func appendMarker(
            _ marker: RealityViewportSpatialBatch.Marker,
            tolerance: Float? = nil
        ) {
            var value = marker
            value.handleIndex = tolerance == nil ? nil : handleIndex
            value.hitTolerancePoints = tolerance
            markers.append(.init(family: entry.family, value: value))
            descriptorCount += 1
        }

        switch entry.world {
        case .none:
            break
        case .polyline(let points):
            guard points.count >= 2,
                  points.allSatisfy(\.isFinite) else {
                throw RealityViewportSpatialBatch.invalid(
                    "Sketch/curve affordance requires a finite world guide."
                )
            }
            appendMesh(try line(points, color: color, depth: .annotation))
        case .curvature(let samples, let scaleFactor):
            let comb = try curvatureMeshes(
                samples: samples,
                scaleFactor: scaleFactor,
                color: color,
                handleIndex: nil,
                family: entry.family
            )
            for mesh in comb {
                meshes.append(mesh)
                descriptorCount += 1
            }
        }

        for guide in entry.cameraGuides {
            guard guide.points.count >= 2 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Sketch/curve affordance (entry.route.rawValue) has an incomplete camera guide."
                )
            }
            let points = try guide.points.map { point in
                guard point.parallel.isFinite,
                      point.perpendicular.isFinite,
                      point.anchor.isFinite,
                      point.toward.isFinite,
                      point.minimumLength?.isFinite ?? true,
                      point.minimumLength.map({ $0 >= 0.0 }) ?? true else {
                    throw RealityViewportSpatialBatch.invalid(
                        "Sketch/curve affordance camera guide is not finite."
                    )
                }
                let offset: RealityViewportSpatialBatch.Offset
                if let minimumLength = point.minimumLength {
                    offset = .projected(
                        toward: point.toward,
                        minimumLength: CGFloat(minimumLength),
                        parallel: CGFloat(point.parallel),
                        perpendicular: CGFloat(point.perpendicular)
                    )
                } else {
                    offset = .directed(
                        toward: point.toward,
                        parallel: CGFloat(point.parallel),
                        perpendicular: CGFloat(point.perpendicular)
                    )
                }
                return RealityViewportSpatialBatch.CameraPoint(anchor: point.anchor, offset: offset)
            }
            appendCameraLine(
                .init(points: points, color: guide.color ?? color, depth: .annotation),
                interactive: isOffsetRoute && handleIndex != nil
            )
        }

        for cameraPath in entry.cameraPaths {
            try appendCameraPath(cameraPath)
        }

        for label in entry.labels {
            guard !label.text.isEmpty,
                  label.heightPoints.isFinite,
                  label.heightPoints > 0.0 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Sketch/curve affordance label is empty or has invalid height."
                )
            }
            let point = label.point
            guard point.anchor.isFinite,
                  point.toward.isFinite,
                  point.parallel.isFinite,
                  point.perpendicular.isFinite,
                  point.minimumLength?.isFinite ?? true,
                  point.minimumLength.map({ $0 >= 0.0 }) ?? true else {
                throw RealityViewportSpatialBatch.invalid(
                    "Sketch/curve affordance label point is not finite."
                )
            }
            let offset: RealityViewportSpatialBatch.Offset
            if let minimumLength = point.minimumLength {
                offset = .projected(
                    toward: point.toward,
                    minimumLength: CGFloat(minimumLength),
                    parallel: CGFloat(point.parallel),
                    perpendicular: CGFloat(point.perpendicular)
                )
            } else {
                offset = .directed(
                    toward: point.toward,
                    parallel: CGFloat(point.parallel),
                    perpendicular: CGFloat(point.perpendicular)
                )
            }
            appendLabel(.init(
                text: label.text,
                anchor: point.anchor,
                offset: offset,
                heightPoints: label.heightPoints,
                color: label.color ?? color,
                alignment: label.alignment,
                depth: .annotation,
                hitRectPoints: label.hitRectPoints
            ), interactive: isDimensionRoute && handleIndex != nil)
        }

        for sourceMarker in entry.markers {
            guard sourceMarker.anchor.isFinite,
                  sourceMarker.diameterPoints.isFinite,
                  sourceMarker.diameterPoints > 0.0 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Sketch/curve affordance marker is not finite."
                )
            }
            if markerTolerance != nil,
               entry.role == .curvePoint || entry.role == .curveHandle || entry.role == .splineControlPoint {
                let diameter = CGFloat(sourceMarker.diameterPoints)
                let rect = CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter)
                let outline: Path
                switch sourceMarker.shape {
                case .box: outline = Path(rect)
                case .sphere, .cone: outline = Path(ellipseIn: rect)
                }
                var marker = RealityViewportSpatialBatch.CameraPath(
                    path: outline.strokedPath(StrokeStyle(lineWidth: 2)),
                    anchor: sourceMarker.anchor, offset: .fixed(.zero),
                    color: color, depth: .annotation
                )
                marker.handleIndex = handleIndex
                marker.hitTolerancePoints = markerTolerance
                marker.objectPreviewOccurrenceID = entry.occurrenceID
                cameraPaths.append(.init(family: entry.family, value: marker))
                descriptorCount += 1
            } else {
                appendMarker(Self.marker(
                    sourceMarker.shape,
                    anchor: sourceMarker.anchor,
                    diameterPoints: sourceMarker.diameterPoints,
                    color: sourceMarker.color ?? color
                ), tolerance: markerTolerance)
            }
        }

        guard descriptorCount > 0 else {
            throw RealityViewportSpatialBatch.invalid(
                "Sketch/curve affordance (entry.route.rawValue) produced no descriptor."
            )
        }
        activeFamilies.insert(entry.family)
    }

    private static func state(
        for entry: SketchCurveAffordanceSource.Entry,
        interaction: SketchCurveInteractionCapture,
        activeOverrides: [SketchCurveAffordanceSource.ActiveOverride]
    ) -> SketchCurveAffordanceState {
        guard let identity = entry.identity else { return entry.state }
        if let override = activeOverrides.first(where: { $0.identity == identity }) {
            return override.state
        }
        if let active = interaction.active.first(where: { $0.identity == identity }) {
            return active.state
        }
        if interaction.preview == identity { return .preview }
        if interaction.pending == identity { return .pending }
        if interaction.hovered == identity { return .hovered }
        return entry.state
    }

    /// Traverses the immutable scene and creates semantic route entries. This
    /// is intentionally worker-side: the MainActor supplies only CAD values,
    /// selection identities, and numeric drag overrides.
    private static func entries(
        from source: SketchCurveAffordanceSource,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> [SketchCurveAffordanceSource.Entry] {
        let limits = MeshSourcePresentationPlanLimits.standard
        var result: [SketchCurveAffordanceSource.Entry] = []
        result.reserveCapacity(min(source.scene.items.count * 4, limits.maxItemCount))

        for item in source.scene.items {
            try Task.checkCancellation()
            try checkpoint(0, 0, 1)
            let firstEntry = result.count
            switch item.kind {
            case .sketch(let primitives):
                let itemSelected = itemIsSelected(item, selection: source.selection, document: source.document)
                    let selectedEntities = selectedSketchEntities(
                    for: item,
                    selection: source.selection
                )
                let hoveredEntities = hoveredSketchEntities(
                    for: item,
                    selection: source.selection
                )
                let selectedControlPoints = selectedSplineControlPoints(
                    for: item,
                    selection: source.selection
                )

                for primitive in primitives {
                    try Task.checkCancellation()
                    let positionCount = primitivePositionCount(primitive)
                    try checkpoint(0, positionCount, 1)
                    let entitySelected = itemSelected || selectedEntities.contains(primitive.entityID)
                    let entityHovered = hoveredEntities.contains(primitive.entityID)
                    let hasActiveOverride = source.activeOverrides.contains { override in
                        switch override.identity {
                        case .sketchCurveHandle(let identity):
                            identity.featureID == item.featureID && identity.entityID == primitive.entityID
                        case .sketchDimension(let identity):
                            identity.featureID == item.featureID && identity.entityID == primitive.entityID
                        case .sketchPointHandle(let identity):
                            identity.featureID == item.featureID && identity.entityID == primitive.entityID
                        case .splineControlPoint(let identity):
                            identity.featureID == item.featureID && identity.entityID == primitive.entityID
                        case .splineControlPointSlide(let identity):
                            identity.featureID == item.featureID && identity.entityID == primitive.entityID
                        default:
                            false
                        }
                    }
                    let entityHighlighted = entitySelected || entityHovered || hasActiveOverride
                    let effectivePrimitive = try applying(
                        overrides: source.activeOverrides,
                        to: primitive,
                        featureID: item.featureID
                    )
                    let labels = dimensionLabels(
                        for: effectivePrimitive,
                        ruler: source.ruler,
                        overrides: source.activeOverrides,
                        featureID: item.featureID
                    )
                    let componentID = SelectionComponentID.sketchEntity(
                        featureID: item.featureID,
                        entityID: primitive.entityID
                    )
                    let pointDisplayVisible = source.overlayState.pointDisplays[componentID]?.isVisible == true
                    let curvatureDisplay = source.overlayState.curveCurvatureDisplays[componentID]
                    let sketchPlane: SketchPlane
                    if let feature = source.document.cadDocument.designGraph.nodes[item.featureID],
                       case .sketch(let sketch) = feature.operation {
                        sketchPlane = sketch.plane
                    } else {
                        // Standalone scene primitives carry their own plane convention.
                        sketchPlane = Self.sketchPlane(for: primitive)
                    }
                    let isSpline: Bool = switch effectivePrimitive {
                    case .spline:
                        true
                    case .point, .line, .circle, .arc:
                        false
                    }
                    let emitsPointHandles = isSpline
                        ? source.enabledRoutes.contains(.splineControl)
                        : source.enabledRoutes.contains(.curvePointControl)
                    let emitsCurveHandles = source.enabledRoutes.contains(.curvePointControl)
                    let emitsDimensions: Bool = switch effectivePrimitive {
                    case .line:
                        source.enabledRoutes.contains(.lineDimension)
                    case .circle:
                        source.enabledRoutes.contains(.circleDimension)
                    case .arc:
                        source.enabledRoutes.contains(.arcDimension)
                    case .point, .spline:
                        false
                    }
                    let emitsCurvature = source.enabledRoutes.contains(.curvatureComb)
                    let primitiveSource = SketchCurveAffordanceSource.Primitive(
                        featureID: item.featureID,
                        primitive: effectivePrimitive,
                        sketchPlane: sketchPlane,
                        sourcePrimitive: primitive,
                        modelTransform: item.modelTransform,
                        selectionTarget: selectedSketchTarget(
                            item: item,
                            featureID: item.featureID,
                            entityID: primitive.entityID,
                            selection: source.selection
                        ),
                        state: .normal,
                        showsPointHandles: emitsPointHandles && (pointDisplayVisible || entityHighlighted),
                        showsCurveHandles: emitsCurveHandles && entityHighlighted,
                        showsDimensions: emitsDimensions && (selectedEntities.contains(primitive.entityID) || entityHovered
                            || hasActiveDimensionOverride(
                                for: effectivePrimitive,
                                featureID: item.featureID,
                                overrides: source.activeOverrides
                            )),
                        showsCurvature: emitsCurvature && (entityHighlighted || curvatureDisplay != nil),
                        curvatureScale: curvatureDisplay?.combScale
                            ?? CurveCurvatureDisplay.defaultCombScale,
                        labels: labels
                    )
                    if emitsPointHandles || emitsDimensions || emitsCurvature {
                        let primitiveEntries = try entries(for: primitiveSource)
                        try append(
                            primitiveEntries,
                            to: &result,
                            limits: limits
                        )
                    }

                    if source.enabledRoutes.contains(.slotWidth),
                       entityHighlighted,
                       let slotEntry = try slotWidthEntry(
                           featureID: item.featureID,
                           primitive: effectivePrimitive,
                           preparedPrimitive: primitiveSource.sourcePrimitive,
                           modelTransform: item.modelTransform,
                           selectionTarget: primitiveSource.selectionTarget,
                           ruler: source.ruler,
                           defaultWidthMeters: source.slotWidthMeters,
                           overrides: source.activeOverrides,
                           state: entitySelected ? .pending : .hovered
                       ) {
                        try append(slotEntry, to: &result, limits: limits)
                    }

                    if source.enabledRoutes.contains(.sketchVertexOffset) {
                        let vertexEntries = try sketchVertexOffsetEntries(
                            featureID: item.featureID,
                            primitive: effectivePrimitive,
                            preparedPrimitive: primitiveSource.sourcePrimitive,
                            modelTransform: item.modelTransform,
                            selectedEntities: selectedEntities,
                            selectedControlPoints: selectedControlPoints,
                            itemSelected: itemSelected,
                            selectionTarget: primitiveSource.selectionTarget,
                            ruler: source.ruler,
                            defaultDistanceMeters: source.sketchVertexOffsetDistanceMeters,
                            overrides: source.activeOverrides,
                            state: entitySelected ? .pending : .normal
                        )
                        try append(vertexEntries, to: &result, limits: limits)
                    }

                    if source.enabledRoutes.contains(.splineSlide),
                       case .spline(let entityID, _, let controlPoints, _) = effectivePrimitive,
                       let indexes = slideControlPointIndexes(
                           featureID: item.featureID,
                           entityID: entityID,
                           selectedControlPoints: selectedControlPoints,
                           overrides: source.activeOverrides
                       ),
                       !indexes.isEmpty {
                        let directions = SplineControlPointSlideDirection.allCases.filter { direction in
                            source.activeOverrides.contains {
                                $0.identity == .splineControlPointSlide(.init(
                                    featureID: item.featureID,
                                    entityID: entityID,
                                    controlPointIndexes: indexes,
                                    direction: direction
                                ))
                            } || !hasActiveSlideOverride(
                                featureID: item.featureID,
                                entityID: entityID,
                                indexes: indexes,
                                overrides: source.activeOverrides
                            )
                        }
                        for direction in directions {
                            let identity = ViewportSpatialHandleIdentity.splineControlPointSlide(.init(
                                featureID: item.featureID,
                                entityID: entityID,
                                controlPointIndexes: indexes,
                                direction: direction
                            ))
                            let override = source.activeOverrides.first { $0.identity == identity }
                            let distance = override?.distanceMeters ?? source.ruler.minorTickMeters
                            let label = override.map { _ in
                                ViewportLengthLabelFormatter.string(
                                    fromMeters: abs(distance),
                                    preferredUnit: source.ruler.displayUnit
                                )
                            }
                            let entry = try makeSplineSlideEntries(
                                featureID: item.featureID,
                                entityID: entityID,
                                controlPoints: controlPoints.map { world($0, by: item.modelTransform) },
                                preparedControlPoints: preparedSplineControlPoints(
                                    from: primitiveSource.sourcePrimitive,
                                    transform: item.modelTransform
                                ),
                                selectedIndexes: indexes,
                                direction: direction,
                                distanceMeters: distance,
                                selectionTarget: primitiveSource.selectionTarget,
                                baseValue: source.ruler.minorTickMeters,
                                label: label,
                                state: override?.state ?? (entitySelected ? .pending : .normal),
                                modelTransform: item.modelTransform
                            )
                            try append(entry, to: &result, limits: limits)
                        }
                    }
                }

                if source.enabledRoutes.contains(.regionOffset) {
                    for region in item.sketchRegions {
                        let selected = selectedRegion(
                            featureID: item.featureID,
                            componentID: region.componentID,
                            selection: source.selection
                        )
                        let identity = ViewportSpatialHandleIdentity.regionOffset(.init(
                            featureID: item.featureID,
                            componentID: region.componentID
                        ))
                        let override = source.activeOverrides.first { $0.identity == identity }
                        guard selected || override != nil else { continue }
                        let vertices = region.points.map { world($0, by: item.modelTransform) }
                        let distance = override?.distanceMeters ?? source.ruler.minorTickMeters
                        let label = override.map { _ in
                            ViewportLengthLabelFormatter.string(
                                fromMeters: abs(distance),
                                preferredUnit: source.ruler.displayUnit
                            )
                        }
                        let entry = try makeRegionOffsetEntry(
                            featureID: item.featureID,
                            componentID: region.componentID,
                            sourceVertices: vertices,
                            distanceMeters: distance,
                            selectionTarget: selectedRegionTarget(
                                item: item,
                                featureID: item.featureID,
                                componentID: region.componentID,
                                selection: source.selection
                            ),
                            baseValue: source.ruler.minorTickMeters,
                            label: label,
                            state: override?.state ?? (selected ? .pending : .normal),
                            modelTransform: item.modelTransform
                        )
                        try append(entry, to: &result, limits: limits)
                    }
                }

            case .body(let component):
                guard source.enabledRoutes.contains(.edgeOffset) else { continue }
                let selectedEdges = selectedBodyEdges(
                    for: item,
                    selection: source.selection,
                    document: source.document
                )
                for edge in selectedEdges {
                    let identity = ViewportSpatialHandleIdentity.edgeOffset(.init(
                        featureID: item.featureID,
                        edge: edge
                    ))
                    let override = source.activeOverrides.first { $0.identity == identity }
                    let (start, end, inward) = bodyEdgeGeometry(
                        item: item,
                        component: component,
                        edge: edge
                    )
                    let distance = override?.distanceMeters ?? source.edgeOffsetDistanceMeters
                    let label = override.map { _ in
                        ViewportLengthLabelFormatter.string(
                            fromMeters: abs(distance),
                            preferredUnit: source.ruler.displayUnit
                        )
                    }
                    let entry = try makeEdgeOffsetEntry(
                        featureID: item.featureID,
                        edge: edge,
                        edgeStart: start,
                        edgeEnd: end,
                        inwardToward: override?.toward ?? inward,
                        preparedInwardToward: inward,
                        distanceMeters: distance,
                        selectionTarget: selectedEdgeTarget(
                            item: item,
                            document: source.document,
                            edge: edge,
                            selection: source.selection
                        ),
                        baseValue: source.edgeOffsetDistanceMeters,
                        label: label,
                        state: override?.state ?? .pending,
                        modelTransform: item.modelTransform
                    )
                    try append(entry, to: &result, limits: limits)
                }

            case .curve(let component):
                guard source.enabledRoutes.contains(.curvePointControl) else { continue }
                let selected = itemIsSelected(item, selection: source.selection, document: source.document)
                guard selected else { continue }
                for segment in component.segments {
                    try Task.checkCancellation()
                    guard segment.points.count >= 2 else { continue }
                    let points = segment.points.map { world($0, by: item.modelTransform) }
                    try checkpoint(0, points.count, 1)
                    let entry = SketchCurveAffordanceSource.Entry(
                        route: .curvePointControl,
                        role: .curvePoint,
                        state: .pending,
                        world: .polyline(points),
                        markers: [
                            .init(anchor: points[0], diameterPoints: 8),
                            .init(anchor: points[points.count - 1], diameterPoints: 8),
                        ],
                        family: .curve
                    )
                    try append(entry, to: &result, limits: limits)
                }
            }
            for index in firstEntry ..< result.count {
                result[index].occurrenceID = item.id
                result[index].modelTransform = item.modelTransform
            }
        }
        return result
    }

    private static func append(
        _ entries: [SketchCurveAffordanceSource.Entry],
        to result: inout [SketchCurveAffordanceSource.Entry],
        limits: MeshSourcePresentationPlanLimits
    ) throws {
        let nextCount = result.count.addingReportingOverflow(entries.count)
        guard !nextCount.overflow,
              nextCount.partialValue <= limits.maxItemCount else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        result.append(contentsOf: entries)
    }

    private static func append(
        _ entry: SketchCurveAffordanceSource.Entry,
        to result: inout [SketchCurveAffordanceSource.Entry],
        limits: MeshSourcePresentationPlanLimits
    ) throws {
        try append([entry], to: &result, limits: limits)
    }

    private static func world(_ point: CGPoint, by transform: Transform3D) -> Point3D {
        ViewportLayout.transformedPoint(
            Point3D(x: Double(point.x), y: 0.0, z: Double(point.y)),
            by: transform
        )
    }

    private static func world(_ point: Point3D, by transform: Transform3D) -> Point3D {
        ViewportLayout.transformedPoint(point, by: transform)
    }

    private static func sketchPlane(for primitive: ViewportSketchPrimitive) -> SketchPlane {
        if case .spline(_, _, _, let plane) = primitive {
            return plane
        }
        return .defaultWorkspacePlane
    }

    private static func primitivePositionCount(_ primitive: ViewportSketchPrimitive) -> Int {
        switch primitive {
        case .point:
            1
        case .line:
            2
        case .circle:
            49
        case .arc:
            25
        case .spline(_, let points, let controlPoints, _):
            points.count + controlPoints.count
        }
    }

    private static func itemIsSelected(
        _ item: ViewportSceneItem,
        selection: SelectionModel,
        document: DesignDocument
    ) -> Bool {
        for target in selection.selectedTargets {
            if targetBelongsToItem(target, item: item, document: document) { return true }
        }
        return false
    }

    private static func targetBelongsToItem(
        _ target: SelectionTarget, item: ViewportSceneItem, document: DesignDocument
    ) -> Bool {
        if let sceneNodeID = item.sceneNodeID { return sceneNodeID == target.sceneNodeID }
        if let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference {
            return reference.featureID == item.featureID
        }
        if case .sketchEntity(let componentID) = target.component,
           let reference = componentID.sketchEntityBaseReference {
            return reference.featureID == item.featureID
        }
        return false
    }

    private static func selectedSketchEntities(
        for item: ViewportSceneItem,
        selection: SelectionModel
    ) -> Set<SketchEntityID> {
        Set(selection.selectedTargets.compactMap { target in
            guard case .sketchEntity(let componentID) = target.component,
                  let reference = componentID.sketchEntityBaseReference,
                  reference.featureID == item.featureID else {
                return nil
            }
            return reference.entityID
        })
    }

    private static func selectedSketchTarget(
        item: ViewportSceneItem,
        featureID: FeatureID,
        entityID: SketchEntityID,
        selection: SelectionModel
    ) -> SelectionTarget? {
        func matches(_ target: SelectionTarget) -> Bool {
            guard item.sceneNodeID == nil || item.sceneNodeID == target.sceneNodeID,
                  case .sketchEntity(let componentID) = target.component,
                  let reference = componentID.sketchEntityBaseReference else {
                return false
            }
            return reference.featureID == featureID && reference.entityID == entityID
        }
        if let target = selection.selectedTargets.reversed().first(where: matches) {
            return target
        }
        if let target = selection.hoveredTarget, matches(target) {
            return target
        }
        return nil
    }

    private static func selectedRegionTarget(
        item: ViewportSceneItem,
        featureID: FeatureID,
        componentID: SelectionComponentID,
        selection: SelectionModel
    ) -> SelectionTarget? {
        func matches(_ target: SelectionTarget) -> Bool {
            guard item.sceneNodeID == nil || item.sceneNodeID == target.sceneNodeID,
                  case .region(let selectedComponentID) = target.component else {
                return false
            }
            if selectedComponentID == componentID { return true }
            guard let selectedReference = selectedComponentID.profileRegionReference,
                  let currentReference = componentID.profileRegionReference else {
                return false
            }
            return selectedReference.featureID == featureID
                && selectedReference.featureID == currentReference.featureID
                && selectedReference.profileIndex == currentReference.profileIndex
        }
        if let target = selection.selectedTargets.reversed().first(where: matches) {
            return target
        }
        if let target = selection.hoveredTarget, matches(target) {
            return target
        }
        return nil
    }

    private static func selectedEdgeTarget(
        item: ViewportSceneItem,
        document: DesignDocument,
        edge: ViewportBodyEdge,
        selection: SelectionModel
    ) -> SelectionTarget? {
        let componentID: SelectionComponentID = switch edge {
        case .leftBottom: .bodyEdgeLeftBottom
        case .rightBottom: .bodyEdgeRightBottom
        case .rightTop: .bodyEdgeRightTop
        case .leftTop: .bodyEdgeLeftTop
        }
        func matches(_ target: SelectionTarget) -> Bool {
            guard targetBelongsToItem(target, item: item, document: document),
                  case .edge(let selectedComponentID) = target.component else {
                return false
            }
            return selectedComponentID == componentID
        }
        if let target = selection.selectedTargets.reversed().first(where: matches) {
            return target
        }
        if let target = selection.hoveredTarget, matches(target) {
            return target
        }
        return nil
    }

    private static func hoveredSketchEntities(
        for item: ViewportSceneItem,
        selection: SelectionModel
    ) -> Set<SketchEntityID> {
        var targets = selection.selectedTargets
        if let target = selection.hoveredTarget {
            targets.append(target)
        }
        return Set(targets.compactMap { target in
            guard case .sketchEntity(let componentID) = target.component,
                  let reference = componentID.sketchEntityBaseReference,
                  reference.featureID == item.featureID else {
                return nil
            }
            return reference.entityID
        })
    }

    private static func selectedSplineControlPoints(
        for item: ViewportSceneItem,
        selection: SelectionModel
    ) -> [SketchEntityID: [Int]] {
        var result: [SketchEntityID: [Int]] = [:]
        for target in selection.selectedTargets {
            guard case .sketchEntity(let componentID) = target.component,
                  let reference = componentID.sketchControlPointReference,
                  reference.featureID == item.featureID else {
                continue
            }
            if result[reference.entityID, default: []].contains(reference.index) == false {
                result[reference.entityID, default: []].append(reference.index)
            }
        }
        return result
    }

    private static func selectedRegion(
        featureID: FeatureID,
        componentID: SelectionComponentID,
        selection: SelectionModel
    ) -> Bool {
        selection.selectedTargets.contains { target in
            guard case .region(let selectedID) = target.component else { return false }
            if selectedID == componentID { return true }
            guard let selected = selectedID.profileRegionReference,
                  let current = componentID.profileRegionReference else {
                return false
            }
            return selected.featureID == featureID
                && selected.profileIndex == current.profileIndex
        }
    }

    private static func selectedBodyEdges(
        for item: ViewportSceneItem,
        selection: SelectionModel,
        document: DesignDocument
    ) -> [ViewportBodyEdge] {
        guard itemIsSelected(item, selection: selection, document: document) else {
            return []
        }
        return selection.selectedTargets.compactMap { target -> ViewportBodyEdge? in
            guard targetBelongsToItem(target, item: item, document: document),
                  case .edge(let componentID) = target.component else { return nil }
            switch componentID {
            case .bodyEdgeLeftBottom: return .leftBottom
            case .bodyEdgeRightBottom: return .rightBottom
            case .bodyEdgeRightTop: return .rightTop
            case .bodyEdgeLeftTop: return .leftTop
            default: return nil
            }
        }
    }

    private static func bodyEdgeGeometry(
        item: ViewportSceneItem,
        component: ViewportBodyComponent,
        edge: ViewportBodyEdge
    ) -> (start: Point3D, end: Point3D, inward: Point3D) {
        let bounds = item.modelBounds
        let yMin = min(component.yMinMeters, component.yMaxMeters)
        let yMax = max(component.yMinMeters, component.yMaxMeters)
        let xMin = Double(bounds.minX)
        let xMax = Double(bounds.maxX)
        let zMin = Double(bounds.minY)
        let zMax = Double(bounds.maxY)
        let x: Double
        let z: Double
        switch edge {
        case .leftBottom:
            x = xMin; z = zMin
        case .rightBottom:
            x = xMax; z = zMin
        case .rightTop:
            x = xMax; z = zMax
        case .leftTop:
            x = xMin; z = zMax
        }
        let start = world(Point3D(x: x, y: yMin, z: z), by: item.modelTransform)
        let end = world(Point3D(x: x, y: yMax, z: z), by: item.modelTransform)
        let center = world(
            Point3D(
                x: (xMin + xMax) * 0.5,
                y: (yMin + yMax) * 0.5,
                z: (zMin + zMax) * 0.5
            ),
            by: item.modelTransform
        )
        return (start, end, center)
    }

    private static func activeOverride(
        _ identity: ViewportSpatialHandleIdentity,
        in overrides: [SketchCurveAffordanceSource.ActiveOverride]
    ) -> SketchCurveAffordanceSource.ActiveOverride? {
        overrides.first { $0.identity == identity }
    }

    private static func bridgeEndpointSample(
        for endpoint: BridgeCurveEndpoint,
        parameter: Double,
        handle: BridgeCurveEndpointHandle,
        item: ViewportSceneItem,
        document: DesignDocument
    ) throws -> (point: Point2D, tangent: Point2D)? {
        guard parameter.isFinite,
              parameter >= 0.0,
              parameter <= 1.0,
              let entityID = bridgeEntityID(for: endpoint.reference),
              let feature = document.cadDocument.designGraph.nodes[handle.featureID],
              case .sketch(let sketch) = feature.operation,
              sketch.entities[entityID] != nil,
              case .sketch(let primitives) = item.kind,
              let primitive = primitives.first(where: { $0.entityID == entityID }) else {
            return nil
        }

        let sampler = SketchCurveSampler()
        let sample: CurveEvaluationSample?
        switch primitive {
        case .line(_, let start, let end):
            sample = sampler.lineSample(
                start: Point2D(x: Double(start.x), y: Double(start.y)),
                end: Point2D(x: Double(end.x), y: Double(end.y)),
                parameter: parameter
            )
        case .arc(_, let center, let radius, let start, let end):
            sample = sampler.arcSample(
                center: Point2D(x: Double(center.x), y: Double(center.y)),
                radius: radius,
                startAngle: start,
                endAngle: end,
                parameter: parameter
            )
        case .spline(_, _, let controlPoints, _):
            sample = sampler.splineSample(
                for: controlPoints.map { Point2D(x: Double($0.x), y: Double($0.y)) },
                parameter: parameter
            )
        case .point, .circle:
            return nil
        }
        guard let sample,
              sample.point.x.isFinite,
              sample.point.y.isFinite,
              sample.tangent.x.isFinite,
              sample.tangent.y.isFinite else {
            return nil
        }

        let reverseReference: Bool
        switch endpoint.reference {
        case .lineStart, .arcStart:
            reverseReference = true
        case .splineControlPoint(_, let index):
            reverseReference = index == 0
        case .lineEnd, .arcEnd, .entity:
            reverseReference = false
        case .circleCenter, .circleRadius, .arcCenter, .arcRadius:
            return nil
        }
        var tangent = sample.tangent
        if reverseReference != endpoint.reversesSense {
            tangent = Point2D(x: -tangent.x, y: -tangent.y)
        }
        return (point: sample.point, tangent: tangent)
    }

    private static func bridgeEntityID(for reference: SketchReference) -> SketchEntityID? {
        switch reference {
        case .entity(let entityID),
             .lineStart(let entityID),
             .lineEnd(let entityID),
             .arcStart(let entityID),
             .arcEnd(let entityID),
             .splineControlPoint(let entityID, _):
            entityID
        case .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            nil
        }
    }

    private static func applying(
        overrides: [SketchCurveAffordanceSource.ActiveOverride],
        to primitive: ViewportSketchPrimitive,
        featureID: FeatureID
    ) throws -> ViewportSketchPrimitive {
        switch primitive {
        case .point(let entityID, let point):
            let identity = ViewportSpatialHandleIdentity.sketchPointHandle(.init(
                featureID: featureID,
                entityID: entityID,
                handle: .point
            ))
            guard let override = activeOverride(identity, in: overrides) else { return primitive }
            guard let deltaX = override.deltaX, let deltaY = override.deltaY,
                  deltaX.isFinite, deltaY.isFinite else { return primitive }
            return .point(
                entityID: entityID,
                point: CGPoint(x: point.x + deltaX, y: point.y + deltaY)
            )

        case .line(let entityID, let start, let end):
            var resolvedStart = start
            var resolvedEnd = end
            for handle in [SketchEntityPointHandle.lineStart, .lineEnd] {
                let identity = ViewportSpatialHandleIdentity.sketchPointHandle(.init(
                    featureID: featureID,
                    entityID: entityID,
                    handle: handle
                ))
                guard let override = activeOverride(identity, in: overrides),
                      let deltaX = override.deltaX, let deltaY = override.deltaY,
                      deltaX.isFinite, deltaY.isFinite else { continue }
                if handle == .lineStart {
                    resolvedStart.x += deltaX
                    resolvedStart.y += deltaY
                } else {
                    resolvedEnd.x += deltaX
                    resolvedEnd.y += deltaY
                }
            }
            if let dimension = activeOverride(
                .sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .length)),
                in: overrides
            ), let value = dimension.value, value.isFinite, value > 0.0 {
                let vector = CGPoint(x: resolvedEnd.x - resolvedStart.x, y: resolvedEnd.y - resolvedStart.y)
                let length = hypot(vector.x, vector.y)
                if length > 1.0e-12 {
                    let scale = value / Double(length)
                    resolvedEnd = CGPoint(
                        x: resolvedStart.x + vector.x * scale,
                        y: resolvedStart.y + vector.y * scale
                    )
                }
            }
            if let dimension = activeOverride(
                .sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .angle)),
                in: overrides
            ), let value = dimension.value, value.isFinite {
                let length = hypot(resolvedEnd.x - resolvedStart.x, resolvedEnd.y - resolvedStart.y)
                if length > 1.0e-12 {
                    resolvedEnd = CGPoint(
                        x: resolvedStart.x + CGFloat(cos(value) * Double(length)),
                        y: resolvedStart.y + CGFloat(sin(value) * Double(length))
                    )
                }
            }
            return .line(entityID: entityID, start: resolvedStart, end: resolvedEnd)

        case .circle(let entityID, let center, let radiusMeters):
            let curveIdentity = ViewportSpatialHandleIdentity.sketchCurveHandle(.init(
                featureID: featureID,
                entityID: entityID,
                handle: .circleRadius
            ))
            let dimensionIdentity = ViewportSpatialHandleIdentity.sketchDimension(.init(
                featureID: featureID,
                entityID: entityID,
                kind: .radius
            ))
            let value = activeOverride(curveIdentity, in: overrides)?.radiusMeters
                ?? activeOverride(dimensionIdentity, in: overrides)?.value
            return .circle(
                entityID: entityID,
                center: center,
                radiusMeters: value.flatMap { $0.isFinite && $0 > 0.0 ? $0 : nil } ?? radiusMeters
            )

        case .arc(let entityID, let center, let radiusMeters, let startAngle, let endAngle):
            let curveBase = { (handle: ViewportSketchCurveHandleKind) in
                ViewportSpatialHandleIdentity.sketchCurveHandle(.init(
                    featureID: featureID,
                    entityID: entityID,
                    handle: handle
                ))
            }
            let radius = activeOverride(curveBase(.arcRadius), in: overrides)?.radiusMeters
                ?? activeOverride(
                    .sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .radius)),
                    in: overrides
                )?.value
            let start = activeOverride(curveBase(.arcStartAngle), in: overrides)?.startAngleRadians
                ?? startAngle
            let end = activeOverride(curveBase(.arcEndAngle), in: overrides)?.endAngleRadians
                ?? activeOverride(
                    .sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .angle)),
                    in: overrides
                )?.value.map { startAngle + $0 }
                ?? endAngle
            return .arc(
                entityID: entityID,
                center: center,
                radiusMeters: radius.flatMap { $0.isFinite && $0 > 0.0 ? $0 : nil } ?? radiusMeters,
                startAngleRadians: start.isFinite ? start : startAngle,
                endAngleRadians: end.isFinite ? end : endAngle
            )

        case .spline(let entityID, let points, let controlPoints, let sketchPlane):
            var resolvedControlPoints = controlPoints
            var resolvedPoints = points
            for index in controlPoints.indices {
                let identity = ViewportSpatialHandleIdentity.splineControlPoint(.init(
                    featureID: featureID,
                    entityID: entityID,
                    controlPointIndex: index
                ))
                guard let override = activeOverride(identity, in: overrides),
                      let deltaX = override.deltaX, let deltaY = override.deltaY,
                      deltaX.isFinite, deltaY.isFinite else { continue }
                resolvedControlPoints[index].x += deltaX
                resolvedControlPoints[index].y += deltaY
                if resolvedPoints.count == controlPoints.count,
                   resolvedPoints.indices.contains(index) {
                    resolvedPoints[index].x += deltaX
                    resolvedPoints[index].y += deltaY
                }
            }
            return .spline(
                entityID: entityID,
                points: resolvedPoints,
                controlPoints: resolvedControlPoints,
                sketchPlane: sketchPlane
            )
        }
    }

    private static func dimensionLabels(
        for primitive: ViewportSketchPrimitive,
        ruler: RulerConfiguration,
        overrides: [SketchCurveAffordanceSource.ActiveOverride],
        featureID: FeatureID
    ) -> SketchCurveAffordanceSource.DimensionLabels {
        func length(_ value: Double) -> String? {
            guard value.isFinite, value >= 0.0 else { return nil }
            return ViewportLengthLabelFormatter.string(
                fromMeters: value,
                preferredUnit: ruler.displayUnit
            )
        }
        func angle(_ radians: Double) -> String? {
            guard radians.isFinite else { return nil }
            let degrees = radians * 180.0 / Double.pi
            return "\(degrees.formatted(.number.precision(.fractionLength(0...1)))) deg"
        }
        switch primitive {
        case .line(let entityID, let start, let end):
            let distance = hypot(Double(end.x - start.x), Double(end.y - start.y))
            let currentAngle = atan2(Double(end.y - start.y), Double(end.x - start.x))
            let lengthOverride = activeOverride(
                .sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .length)),
                in: overrides
            )?.value
            let angleOverride = activeOverride(
                .sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .angle)),
                in: overrides
            )?.value
            return .init(length: length(lengthOverride ?? distance), angle: angle(angleOverride ?? currentAngle))
        case .circle(let entityID, _, let radius):
            let value = activeOverride(
                .sketchCurveHandle(.init(featureID: featureID, entityID: entityID, handle: .circleRadius)),
                in: overrides
            )?.radiusMeters
                ?? activeOverride(
                    .sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .radius)),
                    in: overrides
                )?.value
                ?? radius
            return .init(radius: length(value))
        case .arc(let entityID, _, let radius, let start, let end):
            let resolvedRadius = activeOverride(
                .sketchCurveHandle(.init(featureID: featureID, entityID: entityID, handle: .arcRadius)),
                in: overrides
            )?.radiusMeters ?? radius
            let resolvedStart = activeOverride(
                .sketchCurveHandle(.init(featureID: featureID, entityID: entityID, handle: .arcStartAngle)),
                in: overrides
            )?.startAngleRadians ?? start
            let resolvedEnd = activeOverride(
                .sketchCurveHandle(.init(featureID: featureID, entityID: entityID, handle: .arcEndAngle)),
                in: overrides
            )?.endAngleRadians ?? end
            let dimensionAngle = activeOverride(
                .sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .angle)),
                in: overrides
            )?.value
            return .init(
                radius: length(resolvedRadius),
                angle: angle(dimensionAngle ?? normalizedArcSpan(
                    startAngle: resolvedStart,
                    endAngle: resolvedEnd
                ))
            )
        case .point, .spline:
            return .init()
        }
    }

    private static func hasActiveDimensionOverride(
        for primitive: ViewportSketchPrimitive,
        featureID: FeatureID,
        overrides: [SketchCurveAffordanceSource.ActiveOverride]
    ) -> Bool {
        let entityID = primitive.entityID
        switch primitive {
        case .line:
            return activeOverride(.sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .length)), in: overrides) != nil
                || activeOverride(.sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .angle)), in: overrides) != nil
        case .circle:
            return activeOverride(.sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .radius)), in: overrides) != nil
        case .arc:
            return activeOverride(.sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .radius)), in: overrides) != nil
                || activeOverride(.sketchDimension(.init(featureID: featureID, entityID: entityID, kind: .angle)), in: overrides) != nil
        case .point, .spline:
            return false
        }
    }

    private static func slotGeometry(
        for primitive: ViewportSketchPrimitive,
        modelTransform: Transform3D
    ) throws -> (base: Point3D, direction: Vector3D)? {
        switch primitive {
        case .line(_, let start, let end):
            let midpoint = CGPoint(
                x: (start.x + end.x) * 0.5,
                y: (start.y + end.y) * 0.5
            )
            let tangent = CGPoint(x: end.x - start.x, y: end.y - start.y)
            let length = hypot(tangent.x, tangent.y)
            guard length > 1.0e-12 else { return nil }
            let direction = try modelTransform
                .viewportTransformedVector(Vector3D(
                    x: -Double(tangent.y / length),
                    y: 0.0,
                    z: Double(tangent.x / length)
                ))
                .normalized(tolerance: 1.0e-12)
            return (world(midpoint, by: modelTransform), direction)
        case .arc(_, let center, let radius, let start, let end):
            let span = normalizedArcSpan(startAngle: start, endAngle: end)
            guard radius.isFinite, radius > 0.0, span > 1.0e-12 else { return nil }
            let angle = start + span * 0.5
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle) * radius),
                y: center.y + CGFloat(sin(angle) * radius)
            )
            let direction = try modelTransform
                .viewportTransformedVector(Vector3D(
                    x: cos(angle),
                    y: 0.0,
                    z: sin(angle)
                ))
                .normalized(tolerance: 1.0e-12)
            return (world(point, by: modelTransform), direction)
        case .spline(_, let points, let controlPoints, _):
            let samples = points.count >= 2 ? points : controlPoints
            guard samples.count >= 2 else { return nil }
            let midpointIndex = max((samples.count - 1) / 2, 0)
            let start = samples[midpointIndex]
            let end = samples[min(midpointIndex + 1, samples.count - 1)]
            let tangent = Vector3D(
                x: Double(end.x - start.x),
                y: 0.0,
                z: Double(end.y - start.y)
            )
            guard tangent.length > 1.0e-12 else { return nil }
            let direction = try modelTransform
                .viewportTransformedVector(tangent.cross(Vector3D.unitY))
                .normalized(tolerance: 1.0e-12)
            return (world(start, by: modelTransform), direction)
        case .point, .circle:
            return nil
        }
    }

    private static func sketchVertexGeometry(
        for primitive: ViewportSketchPrimitive,
        handle: SketchEntityPointHandle,
        modelTransform: Transform3D
    ) throws -> (point: CGPoint, direction: Vector3D)? {
        switch primitive {
        case .line(_, let start, let end):
            let direction = try modelTransform
                .viewportTransformedVector(Vector3D(
                    x: Double(end.x - start.x),
                    y: 0.0,
                    z: Double(end.y - start.y)
                ))
                .normalized(tolerance: 1.0e-12)
            switch handle {
            case .lineStart:
                return (start, direction)
            case .lineEnd:
                return (end, -direction)
            case .point, .circleCenter, .arcCenter, .arcStart, .arcEnd:
                return nil
            }
        case .arc(_, let center, let radius, let startAngle, let endAngle):
            guard radius.isFinite, radius > 0.0 else { return nil }
            switch handle {
            case .arcStart:
                let point = CGPoint(
                    x: center.x + CGFloat(cos(startAngle) * radius),
                    y: center.y + CGFloat(sin(startAngle) * radius)
                )
                let direction = try modelTransform
                    .viewportTransformedVector(Vector3D(
                        x: -sin(startAngle), y: 0.0, z: cos(startAngle)
                    ))
                    .normalized(tolerance: 1.0e-12)
                return (point, direction)
            case .arcEnd:
                let point = CGPoint(
                    x: center.x + CGFloat(cos(endAngle) * radius),
                    y: center.y + CGFloat(sin(endAngle) * radius)
                )
                let direction = try modelTransform
                    .viewportTransformedVector(Vector3D(
                        x: sin(endAngle), y: 0.0, z: -cos(endAngle)
                    ))
                    .normalized(tolerance: 1.0e-12)
                return (point, direction)
            case .point, .circleCenter, .arcCenter, .lineStart, .lineEnd:
                return nil
            }
        case .point, .circle, .spline:
            return nil
        }
    }

    private static func slotWidthEntry(
        featureID: FeatureID,
        primitive: ViewportSketchPrimitive,
        preparedPrimitive: ViewportSketchPrimitive? = nil,
        modelTransform: Transform3D,
        selectionTarget: SelectionTarget?,
        ruler: RulerConfiguration,
        defaultWidthMeters: Double,
        overrides: [SketchCurveAffordanceSource.ActiveOverride],
        state: SketchCurveAffordanceState
    ) throws -> SketchCurveAffordanceSource.Entry? {
        let entityID = primitive.entityID
        let widthIdentity = ViewportSpatialHandleIdentity.slotWidth(.init(
            featureID: featureID,
            entityID: entityID
        ))
        let override = activeOverride(widthIdentity, in: overrides)
        let width = override?.widthMeters ?? defaultWidthMeters
        guard width.isFinite, width > 0.0 else { return nil }
        guard let visualGeometry = try slotGeometry(
            for: primitive,
            modelTransform: modelTransform
        ) else { return nil }
        let preparedGeometry = try slotGeometry(
            for: preparedPrimitive ?? primitive,
            modelTransform: modelTransform
        )
        guard let preparedGeometry else { return nil }
        return try makeSlotWidthEntry(
            featureID: featureID,
            entityID: entityID,
            base: visualGeometry.base,
            direction: visualGeometry.direction,
            preparedBase: preparedGeometry.base,
            preparedDirection: preparedGeometry.direction,
            widthMeters: width,
            baseValue: defaultWidthMeters,
            selectionTarget: selectionTarget,
            label: override.map { _ in
                ViewportLengthLabelFormatter.string(
                    fromMeters: abs(width),
                    preferredUnit: ruler.displayUnit
                )
            },
            state: override?.state ?? state,
            modelTransform: modelTransform
        )
    }

    private static func sketchVertexOffsetEntries(
        featureID: FeatureID,
        primitive: ViewportSketchPrimitive,
        preparedPrimitive: ViewportSketchPrimitive? = nil,
        modelTransform: Transform3D,
        selectedEntities: Set<SketchEntityID>,
        selectedControlPoints: [SketchEntityID: [Int]],
        itemSelected: Bool,
        selectionTarget: SelectionTarget?,
        ruler: RulerConfiguration,
        defaultDistanceMeters: Double,
        overrides: [SketchCurveAffordanceSource.ActiveOverride],
        state: SketchCurveAffordanceState
    ) throws -> [SketchCurveAffordanceSource.Entry] {
        let entityID = primitive.entityID
        let shouldShow = itemSelected || selectedEntities.contains(entityID)
            || overrides.contains { identity in
                if case .sketchVertexOffset(let value) = identity.identity {
                    return value.featureID == featureID && value.entityID == entityID
                }
                return false
            }
        guard shouldShow else { return [] }
        var result: [SketchCurveAffordanceSource.Entry] = []
        func appendVertex(
            handle: SketchEntityPointHandle,
            point: CGPoint,
            direction: Vector3D
        ) throws {
            let baseline = try sketchVertexGeometry(
                for: preparedPrimitive ?? primitive,
                handle: handle,
                modelTransform: modelTransform
            )
            guard let baseline else { return }
            let identity = ViewportSpatialHandleIdentity.sketchVertexOffset(.init(
                featureID: featureID,
                entityID: entityID,
                handle: handle
            ))
            let override = activeOverride(identity, in: overrides)
            let distance = override?.distanceMeters ?? defaultDistanceMeters
            let label = override.map { _ in
                ViewportLengthLabelFormatter.string(
                    fromMeters: abs(distance),
                    preferredUnit: ruler.displayUnit
                )
            }
            result.append(try makeSketchVertexOffsetEntry(
                featureID: featureID,
                entityID: entityID,
                handle: handle,
                base: world(point, by: modelTransform),
                direction: direction,
                preparedBase: world(baseline.point, by: modelTransform),
                preparedDirection: baseline.direction,
                distanceMeters: distance,
                baseValue: defaultDistanceMeters,
                selectionTarget: selectionTarget,
                label: label,
                state: override?.state ?? state,
                modelTransform: modelTransform
            ))
        }
        switch primitive {
        case .line(_, let start, let end):
            let direction = try modelTransform
                .viewportTransformedVector(Vector3D(
                    x: Double(end.x - start.x),
                    y: 0.0,
                    z: Double(end.y - start.y)
                ))
                .normalized(tolerance: 1.0e-12)
            if itemSelected || selectedEntities.contains(entityID)
                || selectedControlPoints[entityID]?.isEmpty == false {
                try appendVertex(handle: .lineStart, point: start, direction: direction)
                try appendVertex(handle: .lineEnd, point: end, direction: -direction)
            }
        case .arc(_, let center, let radius, let startAngle, let endAngle):
            guard radius.isFinite, radius > 0.0 else { return [] }
            let start = CGPoint(x: center.x + CGFloat(cos(startAngle) * radius), y: center.y + CGFloat(sin(startAngle) * radius))
            let end = CGPoint(x: center.x + CGFloat(cos(endAngle) * radius), y: center.y + CGFloat(sin(endAngle) * radius))
            let startDirection = try modelTransform
                .viewportTransformedVector(Vector3D(x: -sin(startAngle), y: 0.0, z: cos(startAngle)))
                .normalized(tolerance: 1.0e-12)
            let endDirection = try modelTransform
                .viewportTransformedVector(Vector3D(x: sin(endAngle), y: 0.0, z: -cos(endAngle)))
                .normalized(tolerance: 1.0e-12)
            try appendVertex(handle: .arcStart, point: start, direction: startDirection)
            try appendVertex(handle: .arcEnd, point: end, direction: endDirection)
        case .point, .circle, .spline:
            break
        }
        return result
    }

    private static func slideControlPointIndexes(
        featureID: FeatureID,
        entityID: SketchEntityID,
        selectedControlPoints: [SketchEntityID: [Int]],
        overrides: [SketchCurveAffordanceSource.ActiveOverride]
    ) -> [Int]? {
        if let indexes = selectedControlPoints[entityID], !indexes.isEmpty {
            return indexes.sorted()
        }
        let indexes = overrides.compactMap { override -> [Int]? in
            guard case .splineControlPointSlide(let identity) = override.identity,
                  identity.featureID == featureID,
                  identity.entityID == entityID else { return nil }
            return identity.controlPointIndexes
        }.first
        return indexes?.sorted()
    }

    private static func hasActiveSlideOverride(
        featureID: FeatureID,
        entityID: SketchEntityID,
        indexes: [Int],
        overrides: [SketchCurveAffordanceSource.ActiveOverride]
    ) -> Bool {
        overrides.contains { override in
            guard case .splineControlPointSlide(let identity) = override.identity else { return false }
            return identity.featureID == featureID
                && identity.entityID == entityID
                && identity.controlPointIndexes == indexes
        }
    }

    private static func preparedSplineControlPoints(
        from primitive: ViewportSketchPrimitive?,
        transform: Transform3D
    ) -> [Point3D]? {
        guard let primitive,
              case .spline(_, _, let controlPoints, _) = primitive else {
            return nil
        }
        return controlPoints.map { world($0, by: transform) }
    }

    private static func splineSlideGeometry(
        controlPoints: [Point3D],
        selectedIndexes: [Int],
        direction: SplineControlPointSlideDirection
    ) throws -> (anchor: Point3D, direction: Vector3D) {
        guard controlPoints.count >= 2,
              !selectedIndexes.isEmpty,
              selectedIndexes.allSatisfy(controlPoints.indices.contains) else {
            throw RealityViewportSpatialBatch.invalid(
                "Spline slide requires a valid source tangent frame."
            )
        }
        var positiveU = Vector3D.zero
        for index in selectedIndexes {
            let tangent: Vector3D
            if index == controlPoints.startIndex {
                tangent = controlPoints[index + 1] - controlPoints[index]
            } else if index == controlPoints.index(before: controlPoints.endIndex) {
                tangent = controlPoints[index] - controlPoints[index - 1]
            } else {
                tangent = controlPoints[index + 1] - controlPoints[index - 1]
            }
            positiveU = positiveU + tangent
        }
        positiveU = try positiveU.normalized(tolerance: 1.0e-12)
        let resolvedDirection: Vector3D
        switch direction {
        case .positiveU:
            resolvedDirection = positiveU
        case .negativeU:
            resolvedDirection = -positiveU
        case .normal:
            guard let first = controlPoints.first,
                  let last = controlPoints.last else {
                throw RealityViewportSpatialBatch.invalid(
                    "Spline slide has no tangent frame."
                )
            }
            let tangent = try (last - first).normalized(tolerance: 1.0e-12)
            let xzNormal = tangent.cross(Vector3D.unitY)
            if xzNormal.length > 1.0e-12 {
                resolvedDirection = try xzNormal.normalized(tolerance: 1.0e-12)
            } else {
                resolvedDirection = try tangent.cross(Vector3D.unitX)
                    .normalized(tolerance: 1.0e-12)
            }
        }
        let anchorSum = selectedIndexes.reduce(Point3D.origin) { partial, index in
            let point = controlPoints[index]
            return Point3D(
                x: partial.x + point.x,
                y: partial.y + point.y,
                z: partial.z + point.z
            )
        }
        let divisor = Double(selectedIndexes.count)
        let anchor = Point3D(
            x: anchorSum.x / divisor,
            y: anchorSum.y / divisor,
            z: anchorSum.z / divisor
        )
        guard anchor.isFinite, resolvedDirection.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "Spline slide source geometry is not finite."
            )
        }
        return (anchor, resolvedDirection)
    }

    private static func entries(
        for primitive: SketchCurveAffordanceSource.Primitive
    ) throws -> [SketchCurveAffordanceSource.Entry] {
        let featureID = primitive.featureID
        let entityID = primitive.primitive.entityID
        let state = primitive.state
        let sourcePrimitive = primitive.sourcePrimitive ?? primitive.primitive
        func world(_ point: CGPoint) -> Point3D {
            ViewportLayout.transformedPoint(
                Point3D(x: Double(point.x), y: 0.0, z: Double(point.y)),
                by: primitive.modelTransform
            )
        }
        func identity(_ handle: SketchEntityPointHandle) -> ViewportSpatialHandleIdentity {
            .sketchPointHandle(.init(featureID: featureID, entityID: entityID, handle: handle))
        }
        func curveIdentity(_ handle: ViewportSketchCurveHandleKind) -> ViewportSpatialHandleIdentity {
            .sketchCurveHandle(.init(featureID: featureID, entityID: entityID, handle: handle))
        }
        func dimensionIdentity(_ kind: SketchEntityDimensionKind) -> ViewportSpatialHandleIdentity {
            .sketchDimension(.init(featureID: featureID, entityID: entityID, kind: kind))
        }
        func pointTarget(
            _ handle: SketchEntityPointHandle,
            at point: CGPoint
        ) -> ViewportSpatialPreparedInteractionTarget? {
            guard let target = primitive.selectionTarget else { return nil }
            return .sketchPointHandle(.init(
                featureID: featureID,
                entityID: entityID,
                target: target,
                handle: handle,
                sketchPlane: primitive.sketchPlane,
                point: point
            ))
        }
        func curveTarget(
            _ handle: ViewportSketchCurveHandleKind,
            at point: CGPoint
        ) -> ViewportSpatialPreparedInteractionTarget? {
            guard let target = primitive.selectionTarget else { return nil }
            switch sourcePrimitive {
            case .circle(_, let center, let radiusMeters):
                return .sketchCurveHandle(.init(
                    featureID: featureID,
                    entityID: entityID,
                    target: target,
                    handle: handle,
                    sketchPlane: primitive.sketchPlane,
                    point: point,
                    center: center,
                    radiusMeters: radiusMeters,
                    startAngleRadians: nil,
                    endAngleRadians: nil
                ))
            case .arc(_, let center, let radiusMeters, let startAngle, let endAngle):
                return .sketchCurveHandle(.init(
                    featureID: featureID,
                    entityID: entityID,
                    target: target,
                    handle: handle,
                    sketchPlane: primitive.sketchPlane,
                    point: point,
                    center: center,
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngle,
                    endAngleRadians: endAngle
                ))
            case .point, .line, .spline:
                return nil
            }
        }
        func dimensionTarget(
            _ kind: SketchEntityDimensionKind,
            at point: CGPoint,
            baselineValue: Double,
            start: CGPoint? = nil,
            end: CGPoint? = nil,
            center: CGPoint? = nil,
            radiusMeters: Double? = nil,
            startAngleRadians: Double? = nil,
            endAngleRadians: Double? = nil
        ) -> ViewportSpatialPreparedInteractionTarget? {
            guard let target = primitive.selectionTarget else { return nil }
            return .sketchDimension(.init(
                featureID: featureID,
                entityID: entityID,
                target: target,
                kind: kind,
                sketchPlane: primitive.sketchPlane,
                point: point,
                baselineValue: baselineValue,
                start: start,
                end: end,
                center: center,
                radiusMeters: radiusMeters,
                startAngleRadians: startAngleRadians,
                endAngleRadians: endAngleRadians
            ))
        }
        func splinePointTarget(
            _ controlPointIndex: Int,
            at point: CGPoint
        ) -> ViewportSpatialPreparedInteractionTarget? {
            guard let target = primitive.selectionTarget else { return nil }
            return .splineControlPoint(.init(
                featureID: featureID,
                entityID: entityID,
                target: target,
                controlPointIndex: controlPointIndex,
                sketchPlane: primitive.sketchPlane,
                point: point
            ))
        }
        func directed(
            anchor: Point3D,
            toward: Point3D,
            parallel: Double = 0.0,
            perpendicular: Double = 0.0
        ) -> SketchCurveDirectedPoint {
            .init(
                anchor: anchor,
                toward: toward,
                parallel: parallel,
                perpendicular: perpendicular
            )
        }
        func normalPoint(
            start: CGPoint,
            end: CGPoint,
            distance: Double = 1.0
        ) -> Point3D {
            let dx = Double(end.x - start.x)
            let dy = Double(end.y - start.y)
            let length = max(hypot(dx, dy), 1.0e-12)
            let midpoint = CGPoint(
                x: (start.x + end.x) * 0.5,
                y: (start.y + end.y) * 0.5
            )
            return world(CGPoint(
                x: midpoint.x + CGFloat(-dy / length * distance),
                y: midpoint.y + CGFloat(dx / length * distance)
            ))
        }

        var result: [SketchCurveAffordanceSource.Entry] = []
        switch primitive.primitive {
        case .point(_, let point):
            guard primitive.showsPointHandles else { return [] }
            let anchor = world(point)
            result.append(.init(
                route: .curvePointControl,
                role: .curvePoint,
                state: state,
                identity: identity(.point),
                markers: [.init(anchor: anchor, diameterPoints: 8)],
                preparedTarget: pointTarget(.point, at: point)
            ))

        case .line(_, let start, let end):
            let worldStart = world(start)
            let worldEnd = world(end)
            let sourceStart: CGPoint
            let sourceEnd: CGPoint
            if case .line(_, let originalStart, let originalEnd) = sourcePrimitive {
                sourceStart = originalStart
                sourceEnd = originalEnd
            } else {
                sourceStart = start
                sourceEnd = end
            }
            if primitive.showsPointHandles {
                result.append(contentsOf: [
                    .init(
                        route: .curvePointControl,
                        role: .curvePoint,
                        state: state,
                        identity: identity(.lineStart),
                        markers: [.init(anchor: worldStart, diameterPoints: 8)],
                        preparedTarget: pointTarget(.lineStart, at: start)
                    ),
                    .init(
                        route: .curvePointControl,
                        role: .curvePoint,
                        state: state,
                        identity: identity(.lineEnd),
                        markers: [.init(anchor: worldEnd, diameterPoints: 8)],
                        preparedTarget: pointTarget(.lineEnd, at: end)
                    ),
                ])
            }
            if primitive.showsDimensions {
                let midpoint = midpoint(worldStart, worldEnd)
                let displayedMidpoint = CGPoint(
                    x: (start.x + end.x) * 0.5,
                    y: (start.y + end.y) * 0.5
                )
                let toward = normalPoint(start: start, end: end)
                let guide = SketchCurveCameraGuide(points: [
                    directed(anchor: midpoint, toward: toward),
                    directed(anchor: midpoint, toward: toward, perpendicular: 26.0),
                ])
                let dimensionPairHitRects: (left: CGRect, right: CGRect)?
                if let lengthLabel = primitive.labels.length,
                   let angleLabel = primitive.labels.angle {
                    dimensionPairHitRects = Self.dimensionLabelPairHitRectPoints(
                        left: "L \(lengthLabel)",
                        right: "A \(angleLabel)"
                    )
                } else {
                    dimensionPairHitRects = nil
                }
                if let label = primitive.labels.length {
                    result.append(.init(
                        route: .lineDimension,
                        role: .lineLength,
                        state: state,
                        identity: dimensionIdentity(.length),
                        world: .polyline([worldStart, worldEnd]),
                        cameraGuides: [guide],
                        labels: [.init(
                            text: label,
                            point: directed(anchor: midpoint, toward: toward, perpendicular: 26.0),
                            alignment: dimensionPairHitRects == nil ? .center : .trailing,
                            hitRectPoints: dimensionPairHitRects?.left
                        )],
                        preparedTarget: dimensionTarget(
                            .length,
                            at: displayedMidpoint,
                            baselineValue: hypot(
                                Double(sourceEnd.x - sourceStart.x),
                                Double(sourceEnd.y - sourceStart.y)
                            ),
                            start: sourceStart,
                            end: sourceEnd
                        )
                    ))
                }
                if let label = primitive.labels.angle {
                    result.append(.init(
                        route: .lineDimension,
                        role: .lineAngle,
                        state: state,
                        identity: dimensionIdentity(.angle),
                        labels: [.init(
                            text: label,
                            point: directed(anchor: midpoint, toward: toward, perpendicular: 26.0),
                            alignment: dimensionPairHitRects == nil ? .center : .leading,
                            hitRectPoints: dimensionPairHitRects?.right
                        )],
                        preparedTarget: dimensionTarget(
                            .angle,
                            at: displayedMidpoint,
                            baselineValue: atan2(
                                Double(sourceEnd.y - sourceStart.y),
                                Double(sourceEnd.x - sourceStart.x)
                            ),
                            start: sourceStart,
                            end: sourceEnd
                        )
                    ))
                }
            }

        case .circle(_, let center, let radiusMeters):
            let worldCenter = world(center)
            let sourceCenter: CGPoint
            let sourceRadius: Double
            if case .circle(_, let originalCenter, let originalRadius) = sourcePrimitive {
                sourceCenter = originalCenter
                sourceRadius = originalRadius
            } else {
                sourceCenter = center
                sourceRadius = radiusMeters
            }
            let radiusPoint = CGPoint(
                x: center.x + CGFloat(max(radiusMeters, 1.0e-12)),
                y: center.y
            )
            let worldRadiusPoint = world(radiusPoint)
            if primitive.showsPointHandles {
                result.append(.init(
                    route: .curvePointControl,
                    role: .curvePoint,
                    state: state,
                    identity: identity(.circleCenter),
                    markers: [.init(anchor: worldCenter, diameterPoints: 8)],
                    preparedTarget: pointTarget(.circleCenter, at: center)
                ))
            }
            if primitive.showsCurveHandles {
                result.append(.init(
                    route: .curvePointControl,
                    role: .curveHandle,
                    state: state,
                    identity: curveIdentity(.circleRadius),
                    markers: [.init(anchor: worldRadiusPoint, diameterPoints: 8)],
                    preparedTarget: curveTarget(.circleRadius, at: radiusPoint)
                ))
            }
            if primitive.showsDimensions {
                if let label = primitive.labels.radius {
                    result.append(.init(
                        route: .circleDimension,
                        role: .circleRadius,
                        state: state,
                        identity: dimensionIdentity(.radius),
                        world: .polyline([worldCenter, worldRadiusPoint]),
                        labels: [.init(
                            text: label,
                            point: directed(
                                anchor: worldRadiusPoint,
                                toward: world(CGPoint(x: center.x + CGFloat(2.0 * max(radiusMeters, 1.0e-12)), y: center.y)),
                                parallel: 34.0,
                                perpendicular: -18.0
                            )
                        )],
                        preparedTarget: dimensionTarget(
                            .radius,
                            at: radiusPoint,
                            baselineValue: sourceRadius,
                            center: sourceCenter,
                            radiusMeters: sourceRadius
                        )
                    ))
                }
            }
            if primitive.showsCurvature {
                result.append(try curvatureEntry(
                    primitive: primitive.primitive,
                    featureID: featureID,
                    sketchPlane: primitive.sketchPlane,
                    modelTransform: primitive.modelTransform,
                    state: state,
                    scaleFactor: primitive.curvatureScale
                ))
            }

        case .arc(_, let center, let radiusMeters, let startAngle, let endAngle):
            let worldCenter = world(center)
            let sourceCenter: CGPoint
            let sourceRadius: Double
            let sourceStartAngle: Double
            let sourceEndAngle: Double
            if case .arc(_, let originalCenter, let originalRadius, let originalStart, let originalEnd) = sourcePrimitive {
                sourceCenter = originalCenter
                sourceRadius = originalRadius
                sourceStartAngle = originalStart
                sourceEndAngle = originalEnd
            } else {
                sourceCenter = center
                sourceRadius = radiusMeters
                sourceStartAngle = startAngle
                sourceEndAngle = endAngle
            }
            let midpointAngle = startAngle + normalizedArcSpan(
                startAngle: startAngle,
                endAngle: endAngle
            ) / 2.0
            let radiusPoint = CGPoint(
                x: center.x + CGFloat(cos(midpointAngle) * max(radiusMeters, 1.0e-12)),
                y: center.y + CGFloat(sin(midpointAngle) * max(radiusMeters, 1.0e-12))
            )
            let startPoint = CGPoint(
                x: center.x + CGFloat(cos(startAngle) * max(radiusMeters, 1.0e-12)),
                y: center.y + CGFloat(sin(startAngle) * max(radiusMeters, 1.0e-12))
            )
            let endPoint = CGPoint(
                x: center.x + CGFloat(cos(endAngle) * max(radiusMeters, 1.0e-12)),
                y: center.y + CGFloat(sin(endAngle) * max(radiusMeters, 1.0e-12))
            )
            let worldRadiusPoint = world(radiusPoint)
            if primitive.showsPointHandles {
                result.append(contentsOf: [
                    .init(
                        route: .curvePointControl,
                        role: .curvePoint,
                        state: state,
                        identity: identity(.arcCenter),
                        markers: [.init(anchor: worldCenter, diameterPoints: 8)],
                        preparedTarget: pointTarget(.arcCenter, at: center)
                    ),
                    .init(
                        route: .curvePointControl,
                        role: .curvePoint,
                        state: state,
                        identity: identity(.arcStart),
                        markers: [.init(anchor: world(startPoint), diameterPoints: 8)],
                        preparedTarget: pointTarget(.arcStart, at: startPoint)
                    ),
                    .init(
                        route: .curvePointControl,
                        role: .curvePoint,
                        state: state,
                        identity: identity(.arcEnd),
                        markers: [.init(anchor: world(endPoint), diameterPoints: 8)],
                        preparedTarget: pointTarget(.arcEnd, at: endPoint)
                    ),
                ])
            }
            if primitive.showsCurveHandles {
                result.append(contentsOf: [
                    .init(
                        route: .curvePointControl,
                        role: .curveHandle,
                        state: state,
                        identity: curveIdentity(.arcRadius),
                        markers: [.init(anchor: worldRadiusPoint, diameterPoints: 8)],
                        preparedTarget: curveTarget(.arcRadius, at: radiusPoint)
                    ),
                    .init(
                        route: .curvePointControl,
                        role: .curveHandle,
                        state: state,
                        identity: curveIdentity(.arcStartAngle),
                        markers: [.init(anchor: world(startPoint), diameterPoints: 8)],
                        preparedTarget: curveTarget(.arcStartAngle, at: startPoint)
                    ),
                    .init(
                        route: .curvePointControl,
                        role: .curveHandle,
                        state: state,
                        identity: curveIdentity(.arcEndAngle),
                        markers: [.init(anchor: world(endPoint), diameterPoints: 8)],
                        preparedTarget: curveTarget(.arcEndAngle, at: endPoint)
                    ),
                ])
            }
            if primitive.showsDimensions {
                let toward = world(CGPoint(
                    x: center.x + CGFloat(cos(midpointAngle) * max(2.0 * radiusMeters, 1.0e-12)),
                    y: center.y + CGFloat(sin(midpointAngle) * max(2.0 * radiusMeters, 1.0e-12))
                ))
                let labelPoint = directed(
                    anchor: worldRadiusPoint,
                    toward: toward,
                    parallel: 34.0
                )
                let dimensionPairHitRects: (left: CGRect, right: CGRect)?
                if let radiusLabel = primitive.labels.radius,
                   let angleLabel = primitive.labels.angle {
                    dimensionPairHitRects = Self.dimensionLabelPairHitRectPoints(
                        left: "R \(radiusLabel)",
                        right: "A \(angleLabel)"
                    )
                } else {
                    dimensionPairHitRects = nil
                }
                if let label = primitive.labels.radius {
                    result.append(.init(
                        route: .arcDimension,
                        role: .arcRadius,
                        state: state,
                        identity: dimensionIdentity(.radius),
                        world: .polyline([worldCenter, worldRadiusPoint]),
                        labels: [.init(
                            text: label,
                            point: labelPoint,
                            alignment: dimensionPairHitRects == nil ? .center : .trailing,
                            hitRectPoints: dimensionPairHitRects?.left
                        )],
                        preparedTarget: dimensionTarget(
                            .radius,
                            at: radiusPoint,
                            baselineValue: sourceRadius,
                            center: sourceCenter,
                            radiusMeters: sourceRadius,
                            startAngleRadians: sourceStartAngle,
                            endAngleRadians: sourceEndAngle
                        )
                    ))
                }
                if let label = primitive.labels.angle {
                    result.append(.init(
                        route: .arcDimension,
                        role: .arcAngle,
                        state: state,
                        identity: dimensionIdentity(.angle),
                        labels: [.init(
                            text: label,
                            point: labelPoint,
                            alignment: dimensionPairHitRects == nil ? .center : .leading,
                            hitRectPoints: dimensionPairHitRects?.right
                        )],
                        preparedTarget: dimensionTarget(
                            .angle,
                            at: radiusPoint,
                            baselineValue: normalizedArcSpan(
                                startAngle: sourceStartAngle,
                                endAngle: sourceEndAngle
                            ),
                            center: sourceCenter,
                            radiusMeters: sourceRadius,
                            startAngleRadians: sourceStartAngle,
                            endAngleRadians: sourceEndAngle
                        )
                    ))
                }
            }
            if primitive.showsCurvature {
                result.append(try curvatureEntry(
                    primitive: primitive.primitive,
                    featureID: featureID,
                    sketchPlane: primitive.sketchPlane,
                    modelTransform: primitive.modelTransform,
                    state: state,
                    scaleFactor: primitive.curvatureScale
                ))
            }

        case .spline(_, let points, let controlPoints, _):
            guard controlPoints.count >= 2 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Spline affordance source requires at least two control points."
                )
            }
            let worldControlPoints = controlPoints.map(world)
            if primitive.showsPointHandles {
                result.append(.init(
                    route: .splineControl,
                    role: .splineControlNet,
                    state: state,
                    world: .polyline(worldControlPoints)
                ))
                for (index, point) in worldControlPoints.enumerated() {
                    result.append(.init(
                        route: .splineControl,
                        role: .splineControlPoint,
                        state: state,
                        identity: .splineControlPoint(.init(
                            featureID: featureID,
                            entityID: entityID,
                            controlPointIndex: index
                        )),
                        markers: [.init(anchor: point, diameterPoints: 8,
                                        shape: index.isMultiple(of: 3) ? .box : .sphere)],
                        preparedTarget: splinePointTarget(index, at: controlPoints[index])
                    ))
                }
            }
            if primitive.showsCurvature {
                let points = points
                guard points.count >= 2 else {
                    throw RealityViewportSpatialBatch.invalid(
                        "Spline curvature source requires sampled points."
                    )
                }
                result.append(try curvatureEntry(
                    primitive: primitive.primitive,
                    featureID: featureID,
                    sketchPlane: primitive.sketchPlane,
                    modelTransform: primitive.modelTransform,
                    state: state,
                    scaleFactor: primitive.curvatureScale
                ))
            }
        }
        return result
    }

    private static func curvatureEntry(
        primitive: ViewportSketchPrimitive,
        featureID _: FeatureID,
        sketchPlane: SketchPlane,
        modelTransform: Transform3D,
        state: SketchCurveAffordanceState,
        scaleFactor: Double
    ) throws -> SketchCurveAffordanceSource.Entry {
        guard scaleFactor.isFinite, scaleFactor > 0.0 else {
            throw RealityViewportSpatialBatch.invalid(
                "Curvature comb scale must be positive and finite."
            )
        }
        guard let comb = ViewportCurveCurvatureComb(primitive: primitive) else {
            throw RealityViewportSpatialBatch.invalid(
                "Curvature comb source has no finite drawable samples."
            )
        }
        let displayScale = comb.displayScale(scaleFactor: scaleFactor)
        guard displayScale.isFinite, displayScale > 0.0, comb.samples.count >= 2 else {
            throw RealityViewportSpatialBatch.invalid(
                "Curvature comb source has no drawable span."
            )
        }
        let samples = try comb.samples.map { sample in
            let normal = try modelTransform
                .viewportTransformedVector(Vector3D(
                    x: sample.normal.x,
                    y: 0.0,
                    z: sample.normal.y
                ))
                .normalized(tolerance: 1.0e-12)
            return SketchCurveCurvatureSample(
                point: ViewportLayout.transformedPoint(
                    Point3D(x: Double(sample.point.x), y: 0.0, z: Double(sample.point.y)),
                    by: modelTransform
                ),
                normal: normal,
                curvature: sample.curvature
            )
        }
        return .init(
            route: .curvatureComb,
            role: .curvatureNormal,
            state: state,
            world: .curvature(samples: samples, scaleFactor: displayScale)
        )
    }

    static func makeRegionOffsetEntry(
        featureID: FeatureID,
        componentID: SelectionComponentID,
        sourceVertices: [Point3D],
        distanceMeters: Double,
        selectionTarget: SelectionTarget?,
        baseValue: Double,
        label: String?,
        state: SketchCurveAffordanceState,
        family: ViewportSpatialOverlayFamily = .sketch,
        modelTransform: Transform3D = .identity
    ) throws -> SketchCurveAffordanceSource.Entry {
        guard sourceVertices.count >= 3 else {
            throw RealityViewportSpatialBatch.invalid(
                "Region offset requires at least three source vertices."
            )
        }
        let centroid = try polygonCentroid(sourceVertices)
        var farthestIndex = sourceVertices.startIndex
        var farthestDistance = squaredDistance(sourceVertices[farthestIndex], centroid)
        for index in sourceVertices.dropFirst().indices {
            let distance = squaredDistance(sourceVertices[index], centroid)
            // Keep the first source vertex when distances are equivalent.
            if distance > farthestDistance + 1.0e-12 {
                farthestIndex = index
                farthestDistance = distance
            }
        }
        let anchor = sourceVertices[farthestIndex]
        let direction = try normalizedVector(from: centroid, to: anchor)
        let preparedTarget = selectionTarget.map {
            ViewportSpatialPreparedInteractionTarget.regionOffset(
                featureID: featureID,
                componentID: componentID,
                target: $0,
                axis: .init(origin: anchor, direction: direction, baseValue: baseValue)
            )
        }
        return try offsetEntry(
            route: .regionOffset,
            identity: .regionOffset(.init(featureID: featureID, componentID: componentID)),
            anchor: anchor,
            direction: direction,
            distanceMeters: distanceMeters,
            modelTransform: modelTransform,
            minimumLengthPoints: 64.0,
            label: label,
            state: state,
            family: family,
            preparedTarget: preparedTarget
        )
    }

    static func makeEdgeOffsetEntry(
        featureID: FeatureID,
        edge: ViewportBodyEdge,
        edgeStart: Point3D,
        edgeEnd: Point3D,
        inwardToward: Point3D,
        preparedInwardToward: Point3D? = nil,
        distanceMeters: Double,
        selectionTarget: SelectionTarget?,
        baseValue: Double,
        label: String?,
        state: SketchCurveAffordanceState,
        family: ViewportSpatialOverlayFamily = .body,
        modelTransform: Transform3D = .identity
    ) throws -> SketchCurveAffordanceSource.Entry {
        let anchor = midpoint(edgeStart, edgeEnd)
        let direction = try normalizedVector(from: anchor, to: inwardToward)
        let identity = ViewportSpatialHandleIdentity.edgeOffset(.init(featureID: featureID, edge: edge))
        let preparedDirection = try normalizedVector(
            from: anchor,
            to: preparedInwardToward ?? inwardToward
        )
        let preparedTarget = selectionTarget.map {
            ViewportSpatialPreparedInteractionTarget.edgeOffset(
                featureID: featureID,
                edge: edge,
                target: $0,
                edgeStart: edgeStart,
                edgeEnd: edgeEnd,
                axis: .init(origin: anchor, direction: preparedDirection, baseValue: baseValue)
            )
        }
        return try offsetEntry(
            route: .edgeOffset,
            identity: identity,
            anchor: anchor,
            direction: direction,
            distanceMeters: distanceMeters,
            modelTransform: modelTransform,
            minimumLengthPoints: 64.0,
            label: label,
            state: state,
            family: family,
            worldGuide: [edgeStart, edgeEnd],
            preparedTarget: preparedTarget
        )
    }

    static func makeSlotWidthEntry(
        featureID: FeatureID,
        entityID: SketchEntityID,
        base: Point3D,
        direction: Vector3D,
        preparedBase: Point3D? = nil,
        preparedDirection: Vector3D? = nil,
        widthMeters: Double,
        baseValue: Double,
        selectionTarget: SelectionTarget?,
        label: String?,
        state: SketchCurveAffordanceState,
        modelTransform: Transform3D = .identity
    ) throws -> SketchCurveAffordanceSource.Entry {
        guard widthMeters.isFinite, widthMeters > 0.0 else {
            throw RealityViewportSpatialBatch.invalid(
                "Slot width must be positive and finite."
            )
        }
        let normalized = try direction.normalized(tolerance: 1.0e-12)
        let preparedOrigin = preparedBase ?? base
        let preparedUnit = try (preparedDirection ?? direction).normalized(tolerance: 1.0e-12)
        let preparedTarget = selectionTarget.map {
            ViewportSpatialPreparedInteractionTarget.slotWidth(
                featureID: featureID,
                entityID: entityID,
                target: $0,
                axis: .init(origin: preparedOrigin, direction: preparedUnit, baseValue: baseValue)
            )
        }
        return try offsetEntry(
            route: .slotWidth,
            identity: .slotWidth(.init(featureID: featureID, entityID: entityID)),
            anchor: base,
            direction: normalized,
            distanceMeters: widthMeters * 0.5,
            modelTransform: modelTransform,
            minimumLengthPoints: 64.0,
            label: label,
            state: state,
            family: .sketch,
            preparedTarget: preparedTarget
        )
    }

    static func makeSketchVertexOffsetEntry(
        featureID: FeatureID,
        entityID: SketchEntityID,
        handle: SketchEntityPointHandle,
        base: Point3D,
        direction: Vector3D,
        preparedBase: Point3D? = nil,
        preparedDirection: Vector3D? = nil,
        distanceMeters: Double,
        baseValue: Double,
        selectionTarget: SelectionTarget?,
        label: String?,
        state: SketchCurveAffordanceState,
        modelTransform: Transform3D = .identity
    ) throws -> SketchCurveAffordanceSource.Entry {
        let normalized = try direction.normalized(tolerance: 1.0e-12)
        let preparedOrigin = preparedBase ?? base
        let preparedUnit = try (preparedDirection ?? direction).normalized(tolerance: 1.0e-12)
        let preparedTarget = selectionTarget.map {
            ViewportSpatialPreparedInteractionTarget.sketchVertexOffset(
                featureID: featureID,
                entityID: entityID,
                target: $0,
                handle: handle,
                axis: .init(origin: preparedOrigin, direction: preparedUnit, baseValue: baseValue)
            )
        }
        return try offsetEntry(
            route: .sketchVertexOffset,
            identity: .sketchVertexOffset(.init(featureID: featureID, entityID: entityID, handle: handle)),
            anchor: base,
            direction: normalized,
            distanceMeters: distanceMeters,
            modelTransform: modelTransform,
            minimumLengthPoints: 64.0,
            label: label,
            state: state,
            family: .sketch,
            preparedTarget: preparedTarget
        )
    }

    static func makeSplineSlideEntries(
        featureID: FeatureID,
        entityID: SketchEntityID,
        controlPoints: [Point3D],
        preparedControlPoints: [Point3D]? = nil,
        selectedIndexes: [Int],
        direction: SplineControlPointSlideDirection,
        distanceMeters: Double,
        selectionTarget: SelectionTarget?,
        baseValue: Double,
        label: String?,
        state: SketchCurveAffordanceState,
        modelTransform: Transform3D = .identity
    ) throws -> SketchCurveAffordanceSource.Entry {
        var indexes: [Int] = []
        var seenIndexes: Set<Int> = []
        indexes.reserveCapacity(selectedIndexes.count)
        for index in selectedIndexes where seenIndexes.insert(index).inserted {
            indexes.append(index)
        }
        guard !indexes.isEmpty,
              indexes.allSatisfy(controlPoints.indices.contains) else {
            throw RealityViewportSpatialBatch.invalid(
                "Spline slide requires valid selected control points."
            )
        }
        guard controlPoints.count >= 2 else {
            throw RealityViewportSpatialBatch.invalid(
                "Spline slide requires at least two control points."
            )
        }
        let visualGeometry = try splineSlideGeometry(
            controlPoints: controlPoints,
            selectedIndexes: indexes,
            direction: direction
        )
        let preparedGeometry = try splineSlideGeometry(
            controlPoints: preparedControlPoints ?? controlPoints,
            selectedIndexes: indexes,
            direction: direction
        )
        let preparedTarget = selectionTarget.map {
            ViewportSpatialPreparedInteractionTarget.splineControlPointSlide(
                featureID: featureID,
                entityID: entityID,
                target: $0,
                controlPointIndexes: indexes,
                direction: direction,
                axis: .init(
                    origin: preparedGeometry.anchor,
                    direction: preparedGeometry.direction,
                    baseValue: baseValue
                )
            )
        }
        return try offsetEntry(
            route: .splineSlide,
            identity: .splineControlPointSlide(.init(
                featureID: featureID,
                entityID: entityID,
                controlPointIndexes: indexes,
                direction: direction
            )),
            anchor: visualGeometry.anchor,
            direction: visualGeometry.direction,
            distanceMeters: distanceMeters,
            modelTransform: modelTransform,
            minimumLengthPoints: 62.0,
            label: label,
            state: state,
            family: .sketch,
            preparedTarget: preparedTarget
        )
    }

    static func makeBridgeEndpointEntry(
        handle: BridgeCurveEndpointHandle,
        modelTransform: Transform3D,
        guideLengthMeters: Double,
        state: SketchCurveAffordanceState,
        label: String? = nil
    ) throws -> SketchCurveAffordanceSource.Entry {
        try bridgeEndpointEntry(
            handle: handle,
            preparedHandle: handle,
            modelTransform: modelTransform,
            state: state,
            guideLengthMeters: guideLengthMeters,
            label: label
        )
    }

    private static func bridgeEndpointEntry(
        handle: BridgeCurveEndpointHandle,
        preparedHandle: BridgeCurveEndpointHandle? = nil,
        modelTransform: Transform3D,
        state: SketchCurveAffordanceState,
        guideLengthMeters: Double,
        label: String? = nil,
        override: SketchCurveAffordanceSource.ActiveOverride? = nil
    ) throws -> SketchCurveAffordanceSource.Entry {
        guard guideLengthMeters.isFinite, guideLengthMeters > 0.0 else {
            throw RealityViewportSpatialBatch.invalid(
                "Bridge endpoint guide length must be positive and finite."
            )
        }
        let localPoint = Point3D(x: handle.point.x, y: 0.0, z: handle.point.y)
        let localTangent = try Vector3D(
            x: handle.outgoingTangent.x,
            y: 0.0,
            z: handle.outgoingTangent.y
        ).normalized(tolerance: 1.0e-12)
        let worldPoint: Point3D
        let tangentTip: Point3D
        let rawAnchor = override?.anchor ?? override?.endpoint
        if let anchor = rawAnchor,
           let toward = override?.toward,
           anchor.isFinite,
           toward.isFinite {
            worldPoint = anchor
            tangentTip = toward
        } else if let anchor = rawAnchor,
                  let tangent = override?.tangent,
                  anchor.isFinite,
                  tangent.isFinite {
            let direction = try tangent.normalized(tolerance: 1.0e-12)
            worldPoint = anchor
            tangentTip = Point3D(
                x: anchor.x + direction.x * guideLengthMeters,
                y: anchor.y + direction.y * guideLengthMeters,
                z: anchor.z + direction.z * guideLengthMeters
            )
        } else {
            worldPoint = ViewportLayout.transformedPoint(localPoint, by: modelTransform)
            let worldTangent = try modelTransform
                .viewportTransformedVector(localTangent)
                .normalized(tolerance: 1.0e-12)
            tangentTip = Point3D(
                x: worldPoint.x + worldTangent.x * guideLengthMeters,
                y: worldPoint.y + worldTangent.y * guideLengthMeters,
                z: worldPoint.z + worldTangent.z * guideLengthMeters
            )
        }
        let identity = ViewportSpatialHandleIdentity.bridgeCurveEndpoint(.init(
            sourceID: handle.sourceID,
            role: handle.role
        ))
        let guide = SketchCurveCameraGuide(points: [
            .init(anchor: worldPoint, toward: tangentTip),
            .init(anchor: worldPoint, toward: tangentTip, parallel: 34.0),
        ])
        let labels = label.map {
            [SketchCurveLabelSource(
                text: $0,
                point: .init(anchor: tangentTip, toward: worldPoint, parallel: 10.0)
            )]
        } ?? []
        return .init(
            route: .bridgeCurveEndpoint,
            role: .bridgeEndpoint,
            state: state,
            identity: identity,
            world: .polyline([worldPoint, tangentTip]),
            cameraGuides: [guide],
            labels: labels,
            markers: [.init(anchor: worldPoint, diameterPoints: 8)],
            family: .curve,
            preparedTarget: .bridgeCurveEndpoint(
                handle: preparedHandle ?? handle,
                modelTransform: modelTransform
            )
        )
    }

    private static func offsetEntry(
        route: SketchCurveAffordanceRoute,
        identity: ViewportSpatialHandleIdentity,
        anchor: Point3D,
        direction: Vector3D,
        distanceMeters: Double,
        modelTransform: Transform3D,
        minimumLengthPoints: Double,
        label: String?,
        state: SketchCurveAffordanceState,
        family: ViewportSpatialOverlayFamily,
        worldGuide: [Point3D]? = nil,
        preparedTarget: ViewportSpatialPreparedInteractionTarget? = nil
    ) throws -> SketchCurveAffordanceSource.Entry {
        guard distanceMeters.isFinite,
              minimumLengthPoints.isFinite,
              minimumLengthPoints >= 0.0,
              anchor.isFinite,
              direction.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "Sketch/curve offset source is not finite."
            )
        }
        let unit = try direction.normalized(tolerance: 1.0e-12)
        let sourceUnitsPerWorldMetre = try ViewportNativeAxisInput.sourceUnitsPerWorldMetre(
            for: unit,
            in: modelTransform
        )
        let worldDistance = distanceMeters / sourceUnitsPerWorldMetre
        guard worldDistance.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "Sketch/curve world offset endpoint is not finite."
            )
        }
        let end = Point3D(
            x: anchor.x + unit.x * worldDistance,
            y: anchor.y + unit.y * worldDistance,
            z: anchor.z + unit.z * worldDistance
        )
        guard end.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "Sketch/curve offset endpoint is not finite."
            )
        }
        let unitToward = Point3D(
            x: anchor.x + unit.x,
            y: anchor.y + unit.y,
            z: anchor.z + unit.z
        )
        let endToward = Point3D(
            x: end.x + unit.x,
            y: end.y + unit.y,
            z: end.z + unit.z
        )
        guard endToward.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "Sketch/curve offset placement is not finite."
            )
        }
        let tip: SketchCurveDirectedPoint
        switch route {
        case .regionOffset:
            // Region offsets use the signed world distance first, then add
            // the legacy 64-point screen-space guide length.
            tip = .init(
                anchor: end,
                toward: endToward,
                parallel: minimumLengthPoints
            )
        case .splineSlide:
            // Spline slides preserve every nonzero signed distance.  The
            // 62-point guide is only the zero-distance idle affordance.
            if abs(distanceMeters) > 1.0e-12 {
                tip = .init(anchor: anchor, toward: end, minimumLength: 0.0)
            } else {
                tip = .init(
                    anchor: anchor,
                    toward: unitToward,
                    parallel: minimumLengthPoints
                )
            }
        case .edgeOffset, .slotWidth, .sketchVertexOffset:
            // These routes use the native projected minimum for a nonzero
            // world distance and a directed idle guide at exactly zero.
            if abs(distanceMeters) > 1.0e-12 {
                tip = .init(
                    anchor: anchor,
                    toward: end,
                    minimumLength: minimumLengthPoints
                )
            } else {
                tip = .init(
                    anchor: anchor,
                    toward: unitToward,
                    parallel: minimumLengthPoints
                )
            }
        case .lineDimension, .circleDimension, .arcDimension,
             .curvePointControl, .splineControl, .curvatureComb,
             .bridgeCurveEndpoint:
            throw RealityViewportSpatialBatch.invalid(
                "Sketch/curve offset route is not an offset affordance."
            )
        }
        let cameraGuide = SketchCurveCameraGuide(points: [
            .init(anchor: anchor, toward: unitToward),
            tip,
        ])
        let labels = label.map {
            [SketchCurveLabelSource(
                text: $0,
                point: .init(
                    anchor: tip.anchor,
                    toward: tip.toward,
                    parallel: tip.parallel + 10.0,
                    perpendicular: 20.0,
                    minimumLength: tip.minimumLength
                )
            )]
        } ?? []
        return .init(
            route: route,
            role: .offset,
            state: state,
            identity: identity,
            world: .polyline(worldGuide ?? [anchor, end]),
            cameraGuides: [cameraGuide],
            cameraPaths: [
                .init(
                    path: Self.diamondPath(radius: 4.0),
                    placement: tip,
                    hitTolerancePoints: 14.0
                )
            ],
            labels: labels,
            markers: [],
            family: family,
            preparedTarget: preparedTarget
        )
    }

    private static func curvatureMeshes(
        samples: [SketchCurveCurvatureSample],
        scaleFactor: Double,
        color: SIMD4<Float>,
        handleIndex: UInt32?,
        family: ViewportSpatialOverlayFamily
    ) throws -> [ViewportSpatialOverlayInput.Mesh] {
        guard samples.count >= 2,
              scaleFactor.isFinite,
              scaleFactor > 0.0 else {
            throw RealityViewportSpatialBatch.invalid(
                "Curvature comb requires at least two samples and a positive finite scale."
            )
        }
        let drawable = samples
        guard drawable.allSatisfy({
            $0.point.isFinite && $0.normal.isFinite && $0.curvature.isFinite
                && abs($0.curvature) > 1.0e-12
        }) else {
            throw RealityViewportSpatialBatch.invalid(
                "Curvature comb has a non-finite or zero-curvature sample."
            )
        }
        var result: [ViewportSpatialOverlayInput.Mesh] = []
        result.reserveCapacity(drawable.count + 1)
        var spine: [Point3D] = []
        spine.reserveCapacity(drawable.count)
        for sample in drawable {
            let end = Point3D(
                x: sample.point.x + sample.normal.x * sample.curvature * scaleFactor,
                y: sample.point.y + sample.normal.y * sample.curvature * scaleFactor,
                z: sample.point.z + sample.normal.z * sample.curvature * scaleFactor
            )
            guard end.isFinite else {
                throw RealityViewportSpatialBatch.invalid(
                    "Curvature comb endpoint is not finite."
                )
            }
            var normal = try line([sample.point, end], color: color, depth: .annotation)
            normal.handleIndex = handleIndex
            result.append(.init(family: family, value: normal))
            spine.append(end)
        }
        var spineMesh = try line(spine, color: color, depth: .annotation)
        spineMesh.handleIndex = handleIndex
        result.append(.init(family: family, value: spineMesh))
        return result
    }

    private static func polygonCentroid(_ points: [Point3D]) throws -> Point3D {
        guard points.count >= 3,
              points.allSatisfy(\.isFinite) else {
            throw RealityViewportSpatialBatch.invalid("Region vertices are not finite.")
        }
        let origin = points[0]
        let u = try (points[1] - origin).normalized(tolerance: 1.0e-12)
        var normal: Vector3D?
        for point in points.dropFirst(2) {
            let candidate = (points[1] - origin).cross(point - origin)
            if candidate.length > 1.0e-12 {
                normal = try candidate.normalized(tolerance: 1.0e-12)
                break
            }
        }
        guard let normal else {
            throw RealityViewportSpatialBatch.invalid("Region vertices are collinear.")
        }
        let v = try normal.cross(u).normalized(tolerance: 1.0e-12)
        var areaTwice = 0.0
        var centroidU = 0.0
        var centroidV = 0.0
        for index in points.indices {
            let current = points[index] - origin
            let next = points[(index + 1) % points.count] - origin
            let currentU = current.dot(u)
            let currentV = current.dot(v)
            let nextU = next.dot(u)
            let nextV = next.dot(v)
            let cross = currentU * nextV - nextU * currentV
            areaTwice += cross
            centroidU += (currentU + nextU) * cross
            centroidV += (currentV + nextV) * cross
        }
        guard abs(areaTwice) > 1.0e-12 else {
            throw RealityViewportSpatialBatch.invalid("Region vertices have zero area.")
        }
        let scale = 1.0 / (3.0 * areaTwice)
        return origin + u * (centroidU * scale) + v * (centroidV * scale)
    }

    private static func normalizedVector(from start: Point3D, to end: Point3D) throws -> Vector3D {
        let vector = end - start
        guard vector.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Affordance direction is not finite.")
        }
        do {
            return try vector.normalized(tolerance: 1.0e-12)
        } catch {
            throw RealityViewportSpatialBatch.invalid("Affordance direction is degenerate.")
        }
    }

    private static func squaredDistance(_ lhs: Point3D, _ rhs: Point3D) -> Double {
        let delta = lhs - rhs
        return delta.dot(delta)
    }

    private static func color(
        for state: SketchCurveAffordanceState,
        role: SketchCurveAffordanceRole
    ) -> SIMD4<Float> {
        if role == .splineControlNet {
            return SIMD4<Float>(0.65, 0.68, 0.70, 0.8)
        }
        if role == .curvePoint || role == .curveHandle || role == .splineControlPoint {
            return state == .normal
                ? SIMD4<Float>(0.96, 0.96, 0.96, 1)
                : SIMD4<Float>(1, 0.82, 0.12, 1)
        }
        return switch state {
        case .normal:
            editColor
        case .hovered:
            hoverColor
        case .pending:
            selectionColor
        case .active, .preview:
            SIMD4<Float>(1.0, 0.56, 0.18, 1.0)
        }
    }

    private static func dimensionHitRectPoints(for text: String) -> CGRect {
        let width = max(52.0, CGFloat(text.count) * 6.4 + 16.0)
        let height: CGFloat = 22.0
        return CGRect(
            x: -(width * 0.5 + 4.0),
            y: -(height * 0.5 + 4.0),
            width: width + 8.0,
            height: height + 8.0
        )
    }

    private static func dimensionLabelPairHitRectPoints(
        left: String,
        right: String
    ) -> (left: CGRect, right: CGRect) {
        let combinedLabel = "\(left) / \(right)"
        let width = max(52.0, CGFloat(combinedLabel.count) * 6.4 + 16.0)
        let height: CGFloat = 22.0
        let halfWidth = width * 0.5
        let hitWidth = halfWidth + 8.0
        let hitHeight = height + 8.0
        let y = -(height * 0.5 + 4.0)
        return (
            left: CGRect(
                x: -(halfWidth + 4.0),
                y: y,
                width: hitWidth,
                height: hitHeight
            ),
            right: CGRect(
                x: -4.0,
                y: y,
                width: hitWidth,
                height: hitHeight
            )
        )
    }
}

private extension Vector3D {
    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

private extension Point3D {
    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
