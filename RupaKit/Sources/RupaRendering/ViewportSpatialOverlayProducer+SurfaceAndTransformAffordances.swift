import CoreGraphics
import Foundation
import RupaCore
import RupaGeometry
import RupaViewportScene
import SwiftCAD
import SwiftUI
import simd

extension ViewportSpatialOverlayProducer {
    /// The individual production routes represented by the surface/transform
    /// producer.  The route is retained in the immutable source so the
    /// worker cannot accidentally collapse a disabled callback into a broad
    /// "surface" or "transform" family.
    enum SurfaceTransformAffordanceRoute: String, CaseIterable, Hashable, Sendable {
        case polySplineSurfaceVertex
        case polySplineSurfaceVertexSlide
        case activePolySplineSurfaceVertexPreview
        case surfaceControlPoint
        case surfaceControlPointSlide
        case activeSurfaceControlPointPreview
        case surfaceTrimEndpoint
        case surfaceTrimControlPoint
        case surfaceKnot
        case surfaceSpan
        case surfaceTrimKnot
        case surfaceTrimSpan
        case surfaceFrame
        case constructionPlane
        case constructionFace
        case bodyTransform
        case profileCorner
        case profileFace
        case edgeFillet
        case profileEdgeChamfer
    }

    enum SurfaceTransformAffordanceState: String, CaseIterable, Hashable, Sendable {
        case normal
        case hovered
        case pending
        case active
        case preview
    }

    /// A drag value captured before the worker starts.  It intentionally does
    /// not carry a projected candidate, camera point, native descriptor, or
    /// derived transform geometry.  Those values are re-derived from the
    /// immutable document and scene below.
    struct SurfaceTransformActiveValue: Sendable {
        enum Kind: Sendable {
            case stateOnly
            case delta(Vector3D)
            case distance(Double)
            case plane(origin: Point3D, normal: Vector3D)
            case point(Point3D)
        }

        let identity: ViewportSpatialHandleIdentity
        let kind: Kind
        let showsOriginalComparison: Bool

        init(
            identity: ViewportSpatialHandleIdentity,
            kind: Kind,
            showsOriginalComparison: Bool = false
        ) {
            self.identity = identity
            self.kind = kind
            self.showsOriginalComparison = showsOriginalComparison
        }

        init(
            identity: ViewportSpatialHandleIdentity,
            showsOriginalComparison: Bool = false
        ) {
            self.init(identity: identity, kind: .stateOnly, showsOriginalComparison: showsOriginalComparison)
        }

        init(
            identity: ViewportSpatialHandleIdentity,
            delta: Vector3D,
            showsOriginalComparison: Bool = false
        ) {
            self.init(
                identity: identity,
                kind: .delta(delta),
                showsOriginalComparison: showsOriginalComparison
            )
        }

        init(
            identity: ViewportSpatialHandleIdentity,
            distance: Double,
            showsOriginalComparison: Bool = false
        ) {
            self.init(
                identity: identity,
                kind: .distance(distance),
                showsOriginalComparison: showsOriginalComparison
            )
        }

        init(
            identity: ViewportSpatialHandleIdentity,
            origin: Point3D,
            normal: Vector3D,
            showsOriginalComparison: Bool = false
        ) {
            self.init(
                identity: identity,
                kind: .plane(origin: origin, normal: normal),
                showsOriginalComparison: showsOriginalComparison
            )
        }

        init(
            identity: ViewportSpatialHandleIdentity,
            point: Point3D,
            showsOriginalComparison: Bool = false
        ) {
            self.init(
                identity: identity,
                kind: .point(point),
                showsOriginalComparison: showsOriginalComparison
            )
        }
    }

    /// The only value crossing the MainActor/worker boundary for this route.
    /// CAD authority remains `document`; geometry remains `scene`; selection
    /// ownership remains `selection`; active values contain only raw drag
    /// numerics and stable identities.
    struct SurfaceTransformAffordanceSource: Sendable {
        struct RawInput: Sendable {
            let document: DesignDocument
            let scene: ViewportScene
            let selection: SelectionModel
            let editedBodies: [FeatureID: ViewportObjectEditState]
            var bodyPreviewTransforms: [String: Transform3D] = [:]
            var allowsBodyResize = false
            var presentationScene: UniversalViewportScene?
            var presentationNodeIDs: [SceneOccurrenceID: SceneNodeID] = [:]
            let ruler: RulerConfiguration
            let enabledRoutes: Set<SurfaceTransformAffordanceRoute>
            let interactiveRoutes: Set<SurfaceTransformAffordanceRoute>
            let activeValues: [SurfaceTransformActiveValue]
            let hoveredHandleIdentities: [ViewportSpatialHandleIdentity]
            let pendingHandleIdentities: [ViewportSpatialHandleIdentity]
            let modifierControl: Bool
            let objectRegistry: ObjectTypeRegistry
            let constructionFaceTarget: SelectionTarget?

            init(
                document: DesignDocument,
                scene: ViewportScene,
                selection: SelectionModel,
                editedBodies: [FeatureID: ViewportObjectEditState] = [:],
                ruler: RulerConfiguration,
                enabledRoutes: Set<SurfaceTransformAffordanceRoute> = Set(SurfaceTransformAffordanceRoute.allCases),
                interactiveRoutes: Set<SurfaceTransformAffordanceRoute>? = nil,
                activeValues: [SurfaceTransformActiveValue] = [],
                hoveredHandleIdentities: [ViewportSpatialHandleIdentity] = [],
                pendingHandleIdentities: [ViewportSpatialHandleIdentity] = [],
                modifierControl: Bool = false,
                objectRegistry: ObjectTypeRegistry = .builtIn,
                constructionFaceTarget: SelectionTarget? = nil
            ) {
                self.document = document
                self.scene = scene
                self.selection = selection
                self.editedBodies = editedBodies
                self.ruler = ruler
                self.enabledRoutes = enabledRoutes
                self.interactiveRoutes = interactiveRoutes ?? enabledRoutes
                self.activeValues = activeValues
                self.hoveredHandleIdentities = hoveredHandleIdentities
                self.pendingHandleIdentities = pendingHandleIdentities
                self.modifierControl = modifierControl
                self.objectRegistry = objectRegistry
                self.constructionFaceTarget = constructionFaceTarget
            }
        }

        struct DirectedPoint: Sendable {
            let anchor: Point3D
            let toward: Point3D
            /// Set only by the world-directed form, where `parallel` carries the
            /// screen length and `toward` is unused.
            let worldDirection: Vector3D?
            let parallel: CGFloat
            let perpendicular: CGFloat
            let minimumLength: CGFloat?
            let usesFixedOffset: Bool

            init(
                anchor: Point3D,
                toward: Point3D,
                parallel: CGFloat = 0,
                perpendicular: CGFloat = 0,
                minimumLength: CGFloat? = nil,
                usesFixedOffset: Bool = false
            ) {
                self.anchor = anchor
                self.toward = toward
                self.worldDirection = nil
                self.parallel = parallel
                self.perpendicular = perpendicular
                self.minimumLength = minimumLength
                self.usesFixedOffset = usesFixedOffset
            }

            /// Advances from `anchor` along a source-owned world direction by a
            /// fixed screen length.
            ///
            /// Unlike the directed form, the direction is not normalized on
            /// screen, so the placement keeps the camera's foreshortening while
            /// its projected extent stays bounded by `lengthPoints`.
            init(anchor: Point3D, along direction: Vector3D, lengthPoints: CGFloat) {
                self.anchor = anchor
                self.toward = anchor
                self.worldDirection = direction
                self.parallel = lengthPoints
                self.perpendicular = 0
                self.minimumLength = nil
                self.usesFixedOffset = false
            }

            /// Whether resolving this placement needs a second world point, and
            /// therefore an extra admitted item and position.
            var carriesTowardPoint: Bool {
                worldDirection == nil && usesFixedOffset == false
            }
        }

        struct WorldLine: Sendable {
            let route: SurfaceTransformAffordanceRoute
            let points: [Point3D]
            let closed: Bool
            let color: SIMD4<Float>
            let family: ViewportSpatialOverlayFamily
            let identity: ViewportSpatialHandleIdentity?
            let state: SurfaceTransformAffordanceState
            var hitTolerancePoints: Float? = nil
            var occurrenceID: String? = nil
        }

        struct WorldFill: Sendable {
            let route: SurfaceTransformAffordanceRoute
            let points: [Point3D]
            let color: SIMD4<Float>
            let family: ViewportSpatialOverlayFamily
            let identity: ViewportSpatialHandleIdentity?
            let state: SurfaceTransformAffordanceState
            var hitTolerancePoints: Float? = nil
            var occurrenceID: String? = nil
        }

        struct CameraLine: Sendable {
            let route: SurfaceTransformAffordanceRoute
            let points: [DirectedPoint]
            let color: SIMD4<Float>
            let family: ViewportSpatialOverlayFamily
            let identity: ViewportSpatialHandleIdentity?
            let state: SurfaceTransformAffordanceState
            var hitTolerancePoints: Float? = nil
            var occurrenceID: String? = nil
            var objectPreviewOccurrenceID: String? = nil
        }

        struct CameraPath: Sendable {
            let route: SurfaceTransformAffordanceRoute
            let path: Path
            let placement: DirectedPoint
            let color: SIMD4<Float>
            let family: ViewportSpatialOverlayFamily
            let identity: ViewportSpatialHandleIdentity?
            let state: SurfaceTransformAffordanceState
            var hitTolerancePoints: Float? = nil
            var occurrenceID: String? = nil
        }

        struct Marker: Sendable {
            let route: SurfaceTransformAffordanceRoute
            let anchor: Point3D
            let shape: RealityViewportSpatialBatch.Marker.Shape
            let diameterPoints: Float
            let color: SIMD4<Float>
            let family: ViewportSpatialOverlayFamily
            let identity: ViewportSpatialHandleIdentity?
            let state: SurfaceTransformAffordanceState
            var hitTolerancePoints: Float? = nil
            var occurrenceID: String? = nil
            /// Placement relative to `anchor`. A marker that names a place on
            /// the body leaves this at zero; a marker that names a distance
            /// from it states that distance here, and the mounted camera
            /// resolves it on every update.
            var offset: RealityViewportSpatialBatch.Offset = .zero
            var objectPreviewOccurrenceID: String? = nil
        }

        struct Label: Sendable {
            let route: SurfaceTransformAffordanceRoute
            let text: String
            let placement: DirectedPoint
            let heightPoints: Float
            let alignment: RealityViewportSpatialBatch.Label.Alignment
            let color: SIMD4<Float>
            let family: ViewportSpatialOverlayFamily
            let identity: ViewportSpatialHandleIdentity?
            let state: SurfaceTransformAffordanceState
            var hitRectPoints: CGRect? = nil
            var occurrenceID: String? = nil
        }

        struct Mesh: Sendable {
            let route: SurfaceTransformAffordanceRoute
            let positions: [Point3D]
            let indices: [UInt32]
            let topology: RealityViewportSpatialBatch.Topology
            let color: SIMD4<Float>
            let family: ViewportSpatialOverlayFamily
            let identity: ViewportSpatialHandleIdentity?
            let state: SurfaceTransformAffordanceState
            var hitTolerancePoints: Float? = nil
            var occurrenceID: String? = nil
        }

        let raw: RawInput
        let worldLines: [WorldLine]
        let worldFills: [WorldFill]
        let meshes: [Mesh]
        let cameraLines: [CameraLine]
        let cameraPaths: [CameraPath]
        let labels: [Label]
        let markers: [Marker]

        init(
            raw: RawInput,
            worldLines: [WorldLine],
            worldFills: [WorldFill],
            meshes: [Mesh],
            cameraLines: [CameraLine],
            cameraPaths: [CameraPath],
            labels: [Label],
            markers: [Marker]
        ) {
            self.raw = raw
            self.worldLines = worldLines
            self.worldFills = worldFills
            self.meshes = meshes
            self.cameraLines = cameraLines
            self.cameraPaths = cameraPaths
            self.labels = labels
            self.markers = markers
        }

        var document: DesignDocument { raw.document }
        var scene: ViewportScene { raw.scene }
        var selection: SelectionModel { raw.selection }
        var editedBodies: [FeatureID: ViewportObjectEditState] { raw.editedBodies }
        var ruler: RulerConfiguration { raw.ruler }
        var enabledRoutes: Set<SurfaceTransformAffordanceRoute> { raw.enabledRoutes }
        var interactiveRoutes: Set<SurfaceTransformAffordanceRoute> { raw.interactiveRoutes }
        var activeValues: [SurfaceTransformActiveValue] { raw.activeValues }
        var hoveredHandleIdentities: [ViewportSpatialHandleIdentity] { raw.hoveredHandleIdentities }
        var pendingHandleIdentities: [ViewportSpatialHandleIdentity] { raw.pendingHandleIdentities }
        var modifierControl: Bool { raw.modifierControl }
    }

    /// Builds all semantic surface/transform values from the immutable source.
    /// Geometry is intentionally not represented as native RealityKit values
    /// until `appendSurfaceTransformAffordances`.
    static func makeSurfaceTransformAffordanceSource(
        from input: SurfaceTransformAffordanceSource.RawInput,
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> SurfaceTransformAffordanceSource? {
        try Task.checkCancellation()
        try input.ruler.validate()
        guard !input.enabledRoutes.isEmpty else { return nil }
        // Admit cancellation before any source arrays or derived route values
        // are allocated.  Every route-specific checkpoint below remains
        // responsible for its own traversal and output admission.
        try checkpoint(0, 0, 1)

        var worldLines: [SurfaceTransformAffordanceSource.WorldLine] = []
        var worldFills: [SurfaceTransformAffordanceSource.WorldFill] = []
        var meshes: [SurfaceTransformAffordanceSource.Mesh] = []
        var cameraLines: [SurfaceTransformAffordanceSource.CameraLine] = []
        var cameraPaths: [SurfaceTransformAffordanceSource.CameraPath] = []
        var labels: [SurfaceTransformAffordanceSource.Label] = []
        var markers: [SurfaceTransformAffordanceSource.Marker] = []

        try emitSurfaceTransformSource(
            input: input,
            interactionRecords: &interactionRecords,
            checkpoint: checkpoint,
            worldLines: &worldLines,
            worldFills: &worldFills,
            meshes: &meshes,
            cameraLines: &cameraLines,
            cameraPaths: &cameraPaths,
            labels: &labels,
            markers: &markers
        )
        try Task.checkCancellation()
        let hasValues = !worldLines.isEmpty || !worldFills.isEmpty || !meshes.isEmpty
            || !cameraLines.isEmpty || !cameraPaths.isEmpty || !labels.isEmpty || !markers.isEmpty
        guard hasValues else { return nil }
        return SurfaceTransformAffordanceSource(
            raw: input,
            worldLines: worldLines,
            worldFills: worldFills,
            meshes: meshes,
            cameraLines: cameraLines,
            cameraPaths: cameraPaths,
            labels: labels,
            markers: markers
        )
    }

    /// Appends directly to the existing native descriptor arrays.  No
    /// descriptor registry or test-only emission table is introduced.
    static func appendSurfaceTransformAffordances(
        from source: SurfaceTransformAffordanceSource,
        checkpoint: (Int, Int, Int) throws -> Void,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        paths: inout [ViewportSpatialOverlayInput.Path],
        labels: inout [ViewportSpatialOverlayInput.Label],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        cameraLines: inout [ViewportSpatialOverlayInput.CameraLine],
        cameraPaths: inout [ViewportSpatialOverlayInput.CameraPath],
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        try Task.checkCancellation()

        func index(
            for identity: ViewportSpatialHandleIdentity?,
            route: SurfaceTransformAffordanceRoute,
            occurrenceID: String? = nil,
            hasFootprint: Bool
        ) throws -> UInt32? {
            guard hasFootprint, source.interactiveRoutes.contains(route), let identity else { return nil }
            return try handleIndex(for: identity, occurrenceID: occurrenceID, in: interactionRecords)
        }

        for value in source.worldLines {
            try checkpoint(1, value.points.count, value.points.count)
            guard value.points.allSatisfy(isFinitePoint) else {
                throw RealityViewportSpatialBatch.invalid("Surface/transform line contains a non-finite point.")
            }
            let index = try index(
                for: value.identity,
                route: value.route,
                occurrenceID: value.occurrenceID,
                hasFootprint: value.hitTolerancePoints != nil
            )
            let mesh = value.closed
                ? try closedLine(value.points, color: color(for: value.state, fallback: value.color), depth: .annotation)
                : try line(value.points, color: color(for: value.state, fallback: value.color), depth: .annotation)
            var native = mesh
            native.handleIndex = index
            native.hitTolerancePoints = value.hitTolerancePoints
            meshes.append(.init(family: value.family, value: native))
            activeFamilies.insert(value.family)
        }

        for value in source.worldFills {
            try checkpoint(1, value.points.count, value.points.count)
            guard value.points.allSatisfy(isFinitePoint) else {
                throw RealityViewportSpatialBatch.invalid("Surface/transform fill contains a non-finite point.")
            }
            let index = try index(
                for: value.identity,
                route: value.route,
                occurrenceID: value.occurrenceID,
                hasFootprint: value.hitTolerancePoints != nil
            )
            var path = try polygonFill(
                value.points,
                color: color(for: value.state, fallback: value.color),
                depth: .annotation
            )
            path.handleIndex = index
            path.hitTolerancePoints = value.hitTolerancePoints
            paths.append(.init(family: value.family, value: path))
            activeFamilies.insert(value.family)
        }

        for value in source.meshes {
            try checkpoint(1, value.positions.count, value.positions.count)
            guard value.positions.allSatisfy(isFinitePoint), !value.indices.isEmpty else {
                throw RealityViewportSpatialBatch.invalid("Surface/transform preview mesh is incomplete.")
            }
            let index = try index(
                for: value.identity,
                route: value.route,
                occurrenceID: value.occurrenceID,
                hasFootprint: value.hitTolerancePoints != nil
            )
            var mesh = RealityViewportSpatialBatch.Mesh(
                positions: value.positions,
                indices: value.indices,
                topology: value.topology,
                color: color(for: value.state, fallback: value.color),
                depth: .annotation
            )
            mesh.handleIndex = index
            mesh.hitTolerancePoints = value.hitTolerancePoints
            meshes.append(.init(family: value.family, value: mesh))
            activeFamilies.insert(value.family)
        }

        for value in source.cameraLines {
            try checkpoint(1, value.points.count, value.points.count)
            let index = try index(
                for: value.identity,
                route: value.route,
                occurrenceID: value.occurrenceID,
                hasFootprint: value.hitTolerancePoints != nil
            )
            let points = try value.points.map { point in
                RealityViewportSpatialBatch.CameraPoint(
                    anchor: point.anchor,
                    offset: try cameraOffset(point, describedAs: "camera point")
                )
            }
            guard points.count >= 2 else {
                throw RealityViewportSpatialBatch.invalid("Surface/transform camera line requires two points.")
            }
            var line = RealityViewportSpatialBatch.CameraLine(
                points: points,
                color: color(for: value.state, fallback: value.color),
                widthPoints: value.family == .transform && !(value.route == .bodyTransform && value.identity == nil) ? 2 : nil,
                depth: .annotation
            )
            line.handleIndex = index
            line.hitTolerancePoints = value.hitTolerancePoints
            line.objectPreviewOccurrenceID = value.objectPreviewOccurrenceID
            cameraLines.append(.init(family: value.family, value: line))
            activeFamilies.insert(value.family)
        }

        for value in source.cameraPaths {
            try checkpoint(1, 1, 1)
            let index = try index(
                for: value.identity,
                route: value.route,
                occurrenceID: value.occurrenceID,
                hasFootprint: value.hitTolerancePoints != nil
            )
            let point = value.placement
            let offset = try cameraOffset(point, describedAs: "camera path")
            var path = RealityViewportSpatialBatch.CameraPath(
                path: value.path,
                anchor: point.anchor,
                offset: offset,
                color: color(for: value.state, fallback: value.color),
                depth: .annotation
            )
            path.handleIndex = index
            path.hitTolerancePoints = value.hitTolerancePoints
            cameraPaths.append(.init(family: value.family, value: path))
            activeFamilies.insert(value.family)
        }

        for value in source.labels {
            try checkpoint(1, 1, 1)
            let index = try index(
                for: value.identity,
                route: value.route,
                occurrenceID: value.occurrenceID,
                hasFootprint: value.hitRectPoints != nil
            )
            let point = value.placement
            let offset = try cameraOffset(point, describedAs: "label")
            var label = RealityViewportSpatialBatch.Label(
                text: value.text,
                anchor: point.anchor,
                offset: offset,
                heightPoints: value.heightPoints,
                color: color(for: value.state, fallback: value.color),
                alignment: value.alignment,
                depth: .annotation
            )
            label.handleIndex = index
            label.hitRectPoints = value.hitRectPoints
            labels.append(.init(family: value.family, value: label))
            activeFamilies.insert(value.family)
        }

        for value in source.markers {
            try checkpoint(1, 1, 1)
            guard value.anchor.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Surface/transform marker is not finite.")
            }
            let index = try index(
                for: value.identity,
                route: value.route,
                occurrenceID: value.occurrenceID,
                hasFootprint: value.hitTolerancePoints != nil
            )
            var marker = Self.marker(
                value.shape,
                anchor: value.anchor,
                diameterPoints: value.diameterPoints,
                color: color(for: value.state, fallback: value.color)
            )
            marker.handleIndex = index
            marker.hitTolerancePoints = value.hitTolerancePoints
            marker.offset = value.offset
            marker.objectPreviewOccurrenceID = value.objectPreviewOccurrenceID
            markers.append(.init(family: value.family, value: marker))
            activeFamilies.insert(value.family)
        }
    }

    /// Raw-input convenience used by `Viewport` while the source is still at
    /// the worker boundary.
    static func appendSurfaceTransformAffordances(
        from input: SurfaceTransformAffordanceSource.RawInput,
        checkpoint: (Int, Int, Int) throws -> Void,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        paths: inout [ViewportSpatialOverlayInput.Path],
        labels: inout [ViewportSpatialOverlayInput.Label],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        cameraLines: inout [ViewportSpatialOverlayInput.CameraLine],
        cameraPaths: inout [ViewportSpatialOverlayInput.CameraPath],
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        guard let source = try makeSurfaceTransformAffordanceSource(from: input, interactionRecords: &interactionRecords, checkpoint: checkpoint) else {
            return
        }
        try appendSurfaceTransformAffordances(
            from: source,
            checkpoint: checkpoint,
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

    /// Screen-fixed extents of the four profile affordances.
    ///
    /// A profile handle is reachable at the same screen size whatever the body
    /// measures and however far the camera is, so its extent is a point length
    /// owned here rather than a fraction of the body's projected span. The two
    /// edge treatments share one anchor, so only the offsets along the inward
    /// ray separate them, and the values satisfy
    /// `chamferOffsetPoints - filletOffsetPoints >= 2 * hitTolerancePoints`
    /// together with `2 * markRadiusPoints < chamferOffsetPoints -
    /// filletOffsetPoints`: neither the reach nor the drawn mark of one crosses
    /// the other. Changing one offset re-derives the other from those rules.
    enum ProfileAffordanceMetrics {
        static let markRadiusPoints: CGFloat = 8
        static let hitTolerancePoints: CGFloat = 10
        static let filletOffsetPoints: CGFloat = 18
        static let chamferOffsetPoints: CGFloat = 38
    }

    /// Screen-fixed extents of the body transform affordance.
    ///
    /// A transform handle is reachable at the same screen size whatever the
    /// body measures and however far the camera is, so its extent is a point
    /// length owned here rather than a fraction of the body span. The values
    /// satisfy the separation rule that the footprints of adjacent handles on
    /// one axis cannot overlap: 95 - 72 >= 10 + 8 and 132 - 95 >= 10 + 10.
    /// Changing one length re-derives the others from that rule and from the
    /// tolerances the emit site passes; the ordering itself is the invariant.
    enum BodyTransformMetrics {
        static let rotationRadiusPoints: CGFloat = 72
        static let centerScalePoints: CGFloat = 95
        static let axisLengthPoints: CGFloat = 132
        /// Twelve segments bound the quarter-arc sagitta at
        /// `72 * (1 - cos 3.75 degrees)` = 0.154 pt, below the ring's own line
        /// width, so the count follows from the fixed radius.
        static let rotationSegmentCount = 12
    }
}

private extension ViewportSpatialOverlayProducer {
    static func emitSurfaceTransformSource(
        input: SurfaceTransformAffordanceSource.RawInput,
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        checkpoint: (Int, Int, Int) throws -> Void,
        worldLines: inout [SurfaceTransformAffordanceSource.WorldLine],
        worldFills: inout [SurfaceTransformAffordanceSource.WorldFill],
        meshes: inout [SurfaceTransformAffordanceSource.Mesh],
        cameraLines: inout [SurfaceTransformAffordanceSource.CameraLine],
        cameraPaths: inout [SurfaceTransformAffordanceSource.CameraPath],
        labels: inout [SurfaceTransformAffordanceSource.Label],
        markers: inout [SurfaceTransformAffordanceSource.Marker]
    ) throws {
        let routes = input.enabledRoutes

        // Display-only surface roles are emitted from the evaluated scene.
        // Interactive roles add a stable identity only when the corresponding
        // callback route is enabled and the reference is selected/hovered.
        for item in input.scene.items {
            try Task.checkCancellation()
            try checkpoint(0, 0, 1)
            guard case .body(let component) = item.kind else { continue }
            for display in component.surfaceControlPointDisplays {
                guard routes.contains(.surfaceControlPoint) else { continue }
                try checkpoint(0, 0, 1)
                let world = item.modelTransform.viewportTransformedPoint(display.point)
                let identity = selectedSurfaceControlIdentity(
                    display.selectionReference,
                    input: input,
                    role: .planar
                )
                let state = state(for: identity, input: input)
                if identity != nil {
                    _ = try handleIndex(for: .surfaceControlPoint(.init(
                        featureID: item.featureID, target: display.selectionReference,
                        point: display.point, modelTransform: item.modelTransform, dragMode: .planar
                    )), occurrenceID: item.id, modelTransform: item.modelTransform, in: &interactionRecords)
                }
                try appendMarker(
                    .init(
                        route: .surfaceControlPoint,
                        anchor: world,
                        shape: .sphere,
                        diameterPoints: 7,
                        color: editColor,
                        family: .transform,
                        identity: identity,
                        state: state,
                        hitTolerancePoints: identity == nil ? nil : 12.0,
                        occurrenceID: identity == nil ? nil : item.id
                    ),
                    to: &markers,
                    checkpoint: checkpoint
                )
                if identity != nil,
                   input.selection.selectedReferences.contains(display.selectionReference)
                    || input.selection.hoveredReference == display.selectionReference {
                    try emitSurfaceControlPointAxes(
                        display: display,
                        item: item,
                        identity: identity,
                        input: input,
                        interactionRecords: &interactionRecords,
                        checkpoint: checkpoint,
                        cameraLines: &cameraLines,
                        cameraPaths: &cameraPaths
                    )
                }
            }
            for display in component.surfaceTrimEndpointDisplays {
                guard routes.contains(.surfaceTrimEndpoint) else { continue }
                try checkpoint(0, 0, 1)
                let world = item.modelTransform.viewportTransformedPoint(display.point)
                let identity = selectedTrimEndpointIdentity(display.selectionReference, display.endpoint, input: input)
                if identity != nil {
                    _ = try handleIndex(for: .surfaceTrimEndpoint(.init(
                        featureID: item.featureID, target: display.selectionReference, endpoint: display.endpoint,
                        point: display.point, u: display.u, v: display.v, tangentU: display.tangentU,
                        tangentV: display.tangentV, modelTransform: item.modelTransform
                    )), occurrenceID: item.id, modelTransform: item.modelTransform, in: &interactionRecords)
                }
                try appendMarker(
                    .init(
                        route: .surfaceTrimEndpoint,
                        anchor: world,
                        shape: .box,
                        diameterPoints: 7,
                        color: editColor,
                        family: .transform,
                        identity: identity,
                        state: state(for: identity, input: input),
                        hitTolerancePoints: identity == nil ? nil : 12.0,
                        occurrenceID: identity == nil ? nil : item.id
                    ),
                    to: &markers,
                    checkpoint: checkpoint
                )
            }
            for display in component.surfaceTrimControlPointDisplays {
                guard routes.contains(.surfaceTrimControlPoint) else { continue }
                try checkpoint(0, 0, 1)
                let world = item.modelTransform.viewportTransformedPoint(display.point)
                let identity = selectedTrimControlIdentity(display.selectionReference, display.controlPointIndex, input: input)
                if identity != nil {
                    _ = try handleIndex(for: .surfaceTrimControlPoint(.init(
                        featureID: item.featureID, target: display.selectionReference, controlPointIndex: display.controlPointIndex,
                        point: display.point, u: display.u, v: display.v, tangentU: display.tangentU,
                        tangentV: display.tangentV, modelTransform: item.modelTransform
                    )), occurrenceID: item.id, modelTransform: item.modelTransform, in: &interactionRecords)
                }
                try appendMarker(
                    .init(
                        route: .surfaceTrimControlPoint,
                        anchor: world,
                        shape: .sphere,
                        diameterPoints: 7,
                        color: editColor,
                        family: .transform,
                        identity: identity,
                        state: state(for: identity, input: input),
                        hitTolerancePoints: identity == nil ? nil : 12.0,
                        occurrenceID: identity == nil ? nil : item.id
                    ),
                    to: &markers,
                    checkpoint: checkpoint
                )
            }
            for display in component.surfaceKnotDisplays {
                guard routes.contains(.surfaceKnot) else { continue }
                try checkpoint(0, 0, 1)
                try appendMarker(
                    .init(
                        route: .surfaceKnot,
                        anchor: item.modelTransform.viewportTransformedPoint(display.point),
                        shape: .box,
                        diameterPoints: 6,
                        color: editColor,
                        family: .transform,
                        identity: nil,
                        state: displayState(display.selectionReference, input: input)
                    ),
                    to: &markers,
                    checkpoint: checkpoint
                )
            }
            for display in component.surfaceSpanDisplays {
                guard routes.contains(.surfaceSpan) else { continue }
                try checkpoint(0, 0, 1)
                try appendMarker(
                    .init(
                        route: .surfaceSpan,
                        anchor: item.modelTransform.viewportTransformedPoint(display.point),
                        shape: .sphere,
                        diameterPoints: 6,
                        color: editColor,
                        family: .transform,
                        identity: nil,
                        state: displayState(display.selectionReference, input: input)
                    ),
                    to: &markers,
                    checkpoint: checkpoint
                )
            }
            for display in component.surfaceTrimKnotDisplays {
                guard routes.contains(.surfaceTrimKnot) else { continue }
                try checkpoint(0, 0, 1)
                try appendMarker(
                    .init(
                        route: .surfaceTrimKnot,
                        anchor: item.modelTransform.viewportTransformedPoint(display.point),
                        shape: .box,
                        diameterPoints: 6,
                        color: editColor,
                        family: .transform,
                        identity: nil,
                        state: displayState(display.selectionReference, input: input)
                    ),
                    to: &markers,
                    checkpoint: checkpoint
                )
            }
            for display in component.surfaceTrimSpanDisplays {
                guard routes.contains(.surfaceTrimSpan) else { continue }
                try checkpoint(0, 0, 1)
                try appendMarker(
                    .init(
                        route: .surfaceTrimSpan,
                        anchor: item.modelTransform.viewportTransformedPoint(display.point),
                        shape: .sphere,
                        diameterPoints: 6,
                        color: editColor,
                        family: .transform,
                        identity: nil,
                        state: displayState(display.selectionReference, input: input)
                    ),
                    to: &markers,
                    checkpoint: checkpoint
                )
            }
            for display in component.surfaceFrameDisplays {
                guard routes.contains(.surfaceFrame) else { continue }
                try checkpoint(0, 0, 1)
                try emitSurfaceFrame(
                    display: display,
                    item: item,
                    input: input,
                    interactionRecords: &interactionRecords,
                    checkpoint: checkpoint,
                    cameraLines: &cameraLines,
                    cameraPaths: &cameraPaths,
                    labels: &labels
                )
            }
        }

        try emitSelectedSurfaceHandles(
            input: input,
            interactionRecords: &interactionRecords,
            checkpoint: checkpoint,
            worldLines: &worldLines,
            cameraLines: &cameraLines,
            cameraPaths: &cameraPaths,
            labels: &labels,
            markers: &markers,
            meshes: &meshes
        )
        try emitConstruction(
            input: input,
            interactionRecords: &interactionRecords,
            checkpoint: checkpoint,
            worldLines: &worldLines,
            worldFills: &worldFills,
            markers: &markers,
            meshes: &meshes
        )
        try emitTransforms(
            input: input,
            interactionRecords: &interactionRecords,
            checkpoint: checkpoint,
            worldLines: &worldLines,
            cameraLines: &cameraLines,
            cameraPaths: &cameraPaths,
            markers: &markers,
            meshes: &meshes
        )
        try emitProfileAffordances(
            input: input,
            interactionRecords: &interactionRecords,
            checkpoint: checkpoint,
            cameraLines: &cameraLines,
            cameraPaths: &cameraPaths,
            markers: &markers
        )
    }

    /// The one conversion from a producer placement to the batch's camera
    /// offset value.
    ///
    /// Every descriptor kind that carries a placement resolves it here, so a
    /// placement form cannot be honoured by one kind and silently dropped by
    /// another. A form that cannot be expressed is refused rather than reduced
    /// to the nearest expressible one.
    static func cameraOffset(
        _ point: SurfaceTransformAffordanceSource.DirectedPoint,
        describedAs description: String
    ) throws -> RealityViewportSpatialBatch.Offset {
        guard point.anchor.isFinite, point.toward.isFinite,
              point.parallel.isFinite, point.perpendicular.isFinite,
              point.minimumLength?.isFinite ?? true else {
            throw RealityViewportSpatialBatch.invalid("Surface/transform \(description) is not finite.")
        }
        if let direction = point.worldDirection {
            guard point.usesFixedOffset == false, point.minimumLength == nil,
                  point.perpendicular == 0 else {
                throw RealityViewportSpatialBatch.invalid(
                    "A world-directed \(description) cannot also request a fixed, projected, or perpendicular offset."
                )
            }
            guard direction.isFinite, direction.length > 0 else {
                throw RealityViewportSpatialBatch.invalid(
                    "A world-directed \(description) has no usable direction."
                )
            }
            return .worldDirected(along: direction, lengthPoints: point.parallel)
        }
        if point.usesFixedOffset {
            guard point.minimumLength == nil else {
                throw RealityViewportSpatialBatch.invalid(
                    "A fixed \(description) cannot also request projected length."
                )
            }
            return .fixed(CGPoint(x: point.parallel, y: point.perpendicular))
        }
        if let minimumLength = point.minimumLength {
            return .projected(
                toward: point.toward,
                minimumLength: minimumLength,
                parallel: point.parallel,
                perpendicular: point.perpendicular
            )
        }
        return .directed(
            toward: point.toward,
            parallel: point.parallel,
            perpendicular: point.perpendicular
        )
    }

    static func appendMarker(
        _ value: SurfaceTransformAffordanceSource.Marker,
        to output: inout [SurfaceTransformAffordanceSource.Marker],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try checkpoint(1, 1, 1)
        guard value.anchor.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Surface/transform marker source is not finite.")
        }
        output.append(value)
    }

    static func appendWorldLine(
        _ value: SurfaceTransformAffordanceSource.WorldLine,
        to output: inout [SurfaceTransformAffordanceSource.WorldLine],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try checkpoint(1, value.points.count, value.points.count)
        guard value.points.count >= 2, value.points.allSatisfy(isFinitePoint) else {
            throw RealityViewportSpatialBatch.invalid("Surface/transform world guide is incomplete.")
        }
        output.append(value)
    }

    static func appendWorldFill(
        _ value: SurfaceTransformAffordanceSource.WorldFill,
        to output: inout [SurfaceTransformAffordanceSource.WorldFill],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try checkpoint(1, value.points.count, value.points.count)
        guard value.points.count >= 3, value.points.allSatisfy(isFinitePoint) else {
            throw RealityViewportSpatialBatch.invalid("Surface/transform world fill is incomplete.")
        }
        output.append(value)
    }

    static func appendCameraLine(
        _ value: SurfaceTransformAffordanceSource.CameraLine,
        to output: inout [SurfaceTransformAffordanceSource.CameraLine],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try checkpoint(1, value.points.count, value.points.count)
        guard value.points.count >= 2,
              value.points.allSatisfy({ $0.anchor.isFinite && $0.toward.isFinite }) else {
            throw RealityViewportSpatialBatch.invalid("Surface/transform directed guide is incomplete.")
        }
        output.append(value)
    }

    static func appendCameraPath(
        _ value: SurfaceTransformAffordanceSource.CameraPath,
        to output: inout [SurfaceTransformAffordanceSource.CameraPath],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try checkpoint(1, 1, 1)
        guard value.placement.anchor.isFinite, value.placement.toward.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Surface/transform camera path is not finite.")
        }
        output.append(value)
    }

    static func appendLabel(
        _ value: SurfaceTransformAffordanceSource.Label,
        to output: inout [SurfaceTransformAffordanceSource.Label],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try checkpoint(1, 1, 1)
        guard !value.text.isEmpty,
              value.placement.anchor.isFinite,
              value.placement.toward.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Surface/transform label source is invalid.")
        }
        output.append(value)
    }

    static func color(
        for state: SurfaceTransformAffordanceState,
        fallback: SIMD4<Float>
    ) -> SIMD4<Float> {
        switch state {
        case .normal, .preview:
            fallback
        case .hovered:
            hoverColor
        case .pending, .active:
            selectionColor
        }
    }

    static func state(
        for identity: ViewportSpatialHandleIdentity?,
        input: SurfaceTransformAffordanceSource.RawInput
    ) -> SurfaceTransformAffordanceState {
        guard let identity else { return .normal }
        if input.activeValues.contains(where: { $0.identity == identity }) { return .active }
        if input.pendingHandleIdentities.contains(where: { $0 == identity }) { return .pending }
        if input.hoveredHandleIdentities.contains(where: { $0 == identity }) { return .hovered }
        return .normal
    }

    static func displayState(
        _ reference: SelectionReference,
        input: SurfaceTransformAffordanceSource.RawInput
    ) -> SurfaceTransformAffordanceState {
        if input.selection.selectedReferences.contains(reference) { return .active }
        if input.selection.hoveredReference == reference { return .hovered }
        return .normal
    }

    static func selectedSurfaceControlIdentity(
        _ reference: SelectionReference,
        input: SurfaceTransformAffordanceSource.RawInput,
        role: ViewportSpatialHandleIdentity.Role
    ) -> ViewportSpatialHandleIdentity? {
        guard input.selection.selectedReferences.contains(reference)
                || input.selection.hoveredReference == reference,
              input.interactiveRoutes.contains(.surfaceControlPoint) else {
            return nil
        }
        return .surfaceControlPoint(.init(reference), role: role)
    }

    static func selectedTrimEndpointIdentity(
        _ reference: SelectionReference,
        _ endpoint: SurfaceTrimEndpoint,
        input: SurfaceTransformAffordanceSource.RawInput
    ) -> ViewportSpatialHandleIdentity? {
        guard input.selection.selectedReferences.contains(reference)
                || input.selection.hoveredReference == reference,
              input.interactiveRoutes.contains(.surfaceTrimEndpoint) else {
            return nil
        }
        return .surfaceTrimEndpoint(.init(reference), endpoint: endpoint)
    }

    static func selectedTrimControlIdentity(
        _ reference: SelectionReference,
        _ index: Int,
        input: SurfaceTransformAffordanceSource.RawInput
    ) -> ViewportSpatialHandleIdentity? {
        guard input.selection.selectedReferences.contains(reference)
                || input.selection.hoveredReference == reference,
              input.interactiveRoutes.contains(.surfaceTrimControlPoint) else {
            return nil
        }
        return .surfaceTrimControlPoint(.init(reference), index: index)
    }

    static func surfaceControlAxisIdentity(
        _ identity: ViewportSpatialHandleIdentity?,
        axis: ViewportCoordinateAxis
    ) -> ViewportSpatialHandleIdentity? {
        guard let identity else { return nil }
        switch identity {
        case .surfaceControlPoint(let address, _):
            return .surfaceControlPoint(address, role: .axis(axis))
        default:
            return identity
        }
    }

    static func emitSurfaceControlPointAxes(
        display: ViewportSurfaceControlPointDisplay,
        item: ViewportSceneItem,
        identity: ViewportSpatialHandleIdentity?,
        input: SurfaceTransformAffordanceSource.RawInput,
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        checkpoint: (Int, Int, Int) throws -> Void,
        cameraLines: inout [SurfaceTransformAffordanceSource.CameraLine],
        cameraPaths: inout [SurfaceTransformAffordanceSource.CameraPath]
    ) throws {
        guard let identity else { return }
        let origin = item.modelTransform.viewportTransformedPoint(display.point)
        let normal = normalized(item.modelTransform.viewportTransformedVector(.unitZ)) ?? .unitZ
        let axes: [(ViewportCoordinateAxis, Vector3D)] = ViewportCoordinateAxis.allCases.map { axis in
            (
                axis,
                normalized(item.modelTransform.viewportTransformedVector(axisVector(axis)))
                    ?? axisVector(axis)
            )
        }
        for (axis, direction) in axes {
            let tip = offset(origin, direction: direction, distance: 0.06)
            let color = axisColor(axis)
            let axisIdentity = surfaceControlAxisIdentity(identity, axis: axis)
            _ = try handleIndex(for: .surfaceControlPoint(.init(
                featureID: item.featureID, target: display.selectionReference, point: display.point,
                modelTransform: item.modelTransform, dragMode: .axis(axis)
            )), occurrenceID: item.id, modelTransform: item.modelTransform, in: &interactionRecords)
            let line = SurfaceTransformAffordanceSource.CameraLine(
                route: .surfaceControlPoint,
                points: [
                    .init(anchor: origin, toward: tip, parallel: 16),
                    .init(anchor: origin, toward: tip, minimumLength: 16),
                ],
                color: color,
                family: .transform,
                identity: axisIdentity,
                state: state(for: axisIdentity, input: input),
                hitTolerancePoints: 8.0,
                occurrenceID: item.id
            )
            try appendCameraLine(line, to: &cameraLines, checkpoint: checkpoint)
        }

        let frame = SurfaceTransformAffordanceSource.CameraPath(
            route: .surfaceControlPoint,
            path: diamondPath(radius: 6),
            placement: .init(anchor: origin, toward: origin + normal, parallel: 0, perpendicular: 0),
            color: editColor,
            family: .transform,
            identity: identity,
            state: state(for: identity, input: input),
            hitTolerancePoints: 12.0,
            occurrenceID: item.id
        )
        try appendCameraPath(frame, to: &cameraPaths, checkpoint: checkpoint)
    }

    static func emitSurfaceFrame(
        display: ViewportSurfaceFrameDisplay,
        item: ViewportSceneItem,
        input: SurfaceTransformAffordanceSource.RawInput,
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        checkpoint: (Int, Int, Int) throws -> Void,
        cameraLines: inout [SurfaceTransformAffordanceSource.CameraLine],
        cameraPaths: inout [SurfaceTransformAffordanceSource.CameraPath],
        labels: inout [SurfaceTransformAffordanceSource.Label]
    ) throws {
        let origin = item.modelTransform.viewportTransformedPoint(display.position)
        let modelAxes: [(ViewportSurfaceFrameAxis, Vector3D, SIMD4<Float>, String)] = [
            (
                .u,
                item.modelTransform.viewportTransformedVector(display.uAxis),
                SIMD4<Float>(0.28, 0.86, 0.64, 0.90),
                "U"
            ),
            (
                .v,
                item.modelTransform.viewportTransformedVector(display.vAxis),
                SIMD4<Float>(0.95, 0.46, 0.78, 0.90),
                "V"
            ),
            (
                .normal,
                item.modelTransform.viewportTransformedVector(display.normal),
                sectionNormalColor,
                "N"
            ),
        ]
        guard modelAxes.allSatisfy({ $0.1.isFinite && $0.1.length > 1.0e-10 }) else {
            throw RealityViewportSpatialBatch.invalid("Surface frame has a degenerate basis.")
        }
        let selected = selectedSurfaceFrameReferences(input.selection)
        let selectedModelTransforms = try selected.map { reference in
            let matches = input.scene.items.filter { sceneItem in
                guard case .body(let component) = sceneItem.kind else { return false }
                return component.surfaceControlPointDisplays.contains { $0.selectionReference == reference }
            }
            guard matches.count == 1, let match = matches.first else {
                throw RealityViewportSpatialBatch.invalid("Surface frame source occurrence is ambiguous or absent.")
            }
            return match.modelTransform
        }
        for (axis, modelDirection, color, title) in modelAxes {
            guard let direction = normalized(modelDirection) else {
                throw RealityViewportSpatialBatch.invalid("Surface frame has a degenerate axis.")
            }
            let identity: ViewportSpatialHandleIdentity?
            if input.interactiveRoutes.contains(.surfaceFrame), !selected.isEmpty {
                identity = .surfaceFrame(
                    selected.map(ViewportSpatialReferenceAddress.init),
                    displayID: display.id,
                    axis: axis
                )
            } else {
                identity = nil
            }
            if identity != nil {
                let localDirection: Vector3D = switch axis {
                case .u: display.uAxis
                case .v: display.vAxis
                case .normal: display.normal
                }
                let factors = try (selectedModelTransforms + [item.modelTransform]).map { transform in
                    try ViewportNativeAxisInput.sourceUnitsPerWorldMetre(
                        for: transform.viewportTransformedVector(localDirection), in: transform
                    )
                }
                let factor = try ViewportNativeAxisInput.commonSourceScale(factors)
                _ = try handleIndex(for: .surfaceFrame(
                    targets: selected, query: display.query, displayID: display.id, axis: axis,
                    geometry: .init(origin: origin, direction: modelDirection, baseValue: 0,
                                    sourceUnitsPerWorldMetre: factor)
                ), occurrenceID: item.id, modelTransform: item.modelTransform, in: &interactionRecords)
            }
            let activeDistance: Double? = if let identity,
                                              let active = activeValue(for: identity, input: input),
                                              case .distance(let distance) = active.kind,
                                              distance.isFinite {
                distance
            } else {
                nil
            }
            let tip: Point3D
            let point: SurfaceTransformAffordanceSource.DirectedPoint
            if let activeDistance {
                tip = origin + modelDirection * activeDistance
                point = activeDistance == 0
                    ? .init(anchor: origin, toward: origin, usesFixedOffset: true)
                    : .init(anchor: origin, toward: tip, minimumLength: 0)
            } else {
                tip = offset(origin, direction: direction, distance: 1.0)
                point = .init(
                    anchor: origin,
                    toward: tip,
                    parallel: 36
                )
            }
            let line = SurfaceTransformAffordanceSource.CameraLine(
                route: .surfaceFrame,
                points: [
                    activeDistance.flatMap { distance in
                        guard distance != 0 else { return nil }
                        return SurfaceTransformAffordanceSource.DirectedPoint(
                            anchor: origin,
                            toward: tip,
                            parallel: 10
                        )
                    } ?? .init(anchor: origin, toward: origin, usesFixedOffset: true),
                    point,
                ],
                color: color,
                family: .transform,
                identity: identity,
                state: state(for: identity, input: input),
                hitTolerancePoints: identity == nil ? nil : 10.0,
                occurrenceID: identity == nil ? nil : item.id
            )
            try appendCameraLine(line, to: &cameraLines, checkpoint: checkpoint)

            let tipGlyph = SurfaceTransformAffordanceSource.CameraPath(
                route: .surfaceFrame,
                path: diamondPath(radius: activeDistance == nil ? 2.4 : 3.6),
                placement: point,
                color: color,
                family: .transform,
                identity: identity,
                state: state(for: identity, input: input),
                hitTolerancePoints: identity == nil ? nil : 14.0,
                occurrenceID: identity == nil ? nil : item.id
            )
            try appendCameraPath(tipGlyph, to: &cameraPaths, checkpoint: checkpoint)

            if identity != nil, let activeDistance {
                let labelPlacement: SurfaceTransformAffordanceSource.DirectedPoint
                if activeDistance == 0 {
                    labelPlacement = .init(
                        anchor: tip,
                        toward: tip,
                        parallel: 8,
                        perpendicular: 18,
                        usesFixedOffset: true
                    )
                } else {
                    labelPlacement = .init(
                        anchor: origin,
                        toward: tip,
                        parallel: 8,
                        perpendicular: 18,
                        minimumLength: 0
                    )
                }
                let label = SurfaceTransformAffordanceSource.Label(
                    route: .surfaceFrame,
                    text: "\(title) \(ViewportLengthLabelFormatter.string(fromMeters: abs(activeDistance), preferredUnit: input.ruler.displayUnit))",
                    placement: labelPlacement,
                    heightPoints: 10,
                    alignment: .center,
                    color: color,
                    family: .transform,
                    identity: nil,
                    state: .active
                )
                try appendLabel(label, to: &labels, checkpoint: checkpoint)
            }
        }
    }

    static func selectedSurfaceFrameReferences(_ selection: SelectionModel) -> [SelectionReference] {
        selection.selectedReferences.reversed().filter {
            if case .surface(.controlPoint) = $0 { return true }
            return false
        }
    }

    static func axisColor(_ axis: ViewportCoordinateAxis) -> SIMD4<Float> {
        switch axis {
        case .x: SIMD4<Float>(0.96, 0.26, 0.26, 1)
        case .y: SIMD4<Float>(0.36, 0.92, 0.44, 1)
        case .z: SIMD4<Float>(0.32, 0.56, 1.0, 1)
        }
    }

    static func axisVector(_ axis: ViewportCoordinateAxis) -> Vector3D {
        axis.unitVector
    }

    static func modelAxis(_ axis: ViewportCoordinateAxis) -> Vector3D {
        axisVector(axis)
    }

    static func worldVector(_ vector: ViewportModelVector3D) -> Vector3D {
        Vector3D(x: Double(vector.x), y: Double(vector.y), z: Double(vector.z))
    }

    /// Unit directions sampling a quarter turn from `planeStart` to `planeEnd`.
    ///
    /// A ring whose radius is a screen length has no world radius to sample, so
    /// the sampling is expressed as directions and the radius is applied by
    /// whichever placement the caller uses.
    static func rotationArcDirections(
        planeStart: Vector3D,
        planeEnd: Vector3D,
        segmentCount: Int = 36
    ) -> [Vector3D] {
        guard let start = normalized(planeStart),
              let end = normalized(planeEnd) else {
            return []
        }
        let count = max(segmentCount, 1)
        return (0 ... count).map { index in
            let radians = Double(index) / Double(count) * .pi / 2.0
            return start * cos(radians) + end * sin(radians)
        }
    }

    static func rotationArcPoints(
        center: Point3D,
        planeStart: Vector3D,
        planeEnd: Vector3D,
        radius: Double,
        segmentCount: Int = 36
    ) -> [Point3D] {
        guard radius.isFinite, radius > 0 else { return [] }
        return rotationArcDirections(
            planeStart: planeStart,
            planeEnd: planeEnd,
            segmentCount: segmentCount
        ).map { center + $0 * radius }
    }

    static func normalized(_ vector: Vector3D) -> Vector3D? {
        guard vector.isFinite, vector.length > 1.0e-10 else { return nil }
        return vector * (1.0 / vector.length)
    }

    static func offset(_ point: Point3D, direction: Vector3D, distance: Double) -> Point3D {
        point + direction * distance
    }

    static func emitSelectedSurfaceHandles(
        input: SurfaceTransformAffordanceSource.RawInput,
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        checkpoint: (Int, Int, Int) throws -> Void,
        worldLines: inout [SurfaceTransformAffordanceSource.WorldLine],
        cameraLines: inout [SurfaceTransformAffordanceSource.CameraLine],
        cameraPaths: inout [SurfaceTransformAffordanceSource.CameraPath],
        labels: inout [SurfaceTransformAffordanceSource.Label],
        markers: inout [SurfaceTransformAffordanceSource.Marker],
        meshes: inout [SurfaceTransformAffordanceSource.Mesh]
    ) throws {
        let selectedTargets = input.selection.selectedTargets
            + (input.selection.hoveredTarget.flatMap { input.selection.selectedTargets.contains($0) ? nil : [$0] } ?? [])
        let topologyVertices = input.scene.items.compactMap { item -> [ViewportBodyTopology.Vertex]? in
            guard case .body(let component) = item.kind else { return nil }
            return component.topology?.vertices
        }.flatMap { $0 }
        let needsPatches = input.interactiveRoutes.contains(.polySplineSurfaceVertex)
            || input.interactiveRoutes.contains(.polySplineSurfaceVertexSlide)
            || input.interactiveRoutes.contains(.surfaceControlPointSlide)
        let patches = needsPatches
            ? try polySplinePatchDescriptors(document: input.document, checkpoint: checkpoint)
            : [:]

        if input.interactiveRoutes.contains(.polySplineSurfaceVertex) {
            for target in selectedTargets {
                guard case .vertex(let componentID) = target.component,
                      let parsed = PolySplineSurfaceVertexTarget.parse(componentID: componentID) else {
                    continue
                }
                guard let item = sceneItem(for: target, input: input),
                      case .body(let component) = item.kind,
                      let vertex = component.topology?.vertices.first(where: { $0.componentID == componentID }) else {
                    throw RealityViewportSpatialBatch.invalid("Selected PolySpline surface vertex is missing from the scene.")
                }
                guard parsed.featureID == item.featureID else {
                    throw RealityViewportSpatialBatch.invalid("PolySpline surface vertex identity does not match its scene item.")
                }
                let origin = item.modelTransform.viewportTransformedPoint(vertex.point)
                let centerIdentity = ViewportSpatialHandleIdentity.polySplineSurfaceVertex(
                    featureID: parsed.featureID,
                    componentID: componentID,
                    role: .planar
                )
                var prepared = ViewportPolySplineSurfaceVertexHandleTarget(
                    featureID: parsed.featureID, target: target, componentID: componentID,
                    point: vertex.point, modelTransform: item.modelTransform, dragMode: .planar)
                _ = try handleIndex(for: .polySplineSurfaceVertex(prepared), occurrenceID: item.id, modelTransform: item.modelTransform, in: &interactionRecords)
                try appendMarker(
                    .init(
                        route: .polySplineSurfaceVertex,
                        anchor: origin,
                        shape: .sphere,
                        diameterPoints: 8,
                        color: editColor,
                        family: .transform,
                        identity: centerIdentity,
                        state: state(for: centerIdentity, input: input),
                        hitTolerancePoints: 12.0,
                        occurrenceID: item.id
                    ),
                    to: &markers,
                    checkpoint: checkpoint
                )
                for axis in ViewportCoordinateAxis.allCases {
                    let identity = ViewportSpatialHandleIdentity.polySplineSurfaceVertex(
                        featureID: parsed.featureID,
                        componentID: componentID,
                        role: .axis(axis)
                    )
                    let direction = item.modelTransform.viewportTransformedVector(axisVector(axis))
                    prepared.dragMode = .axis(axis)
                    _ = try handleIndex(for: .polySplineSurfaceVertex(prepared), occurrenceID: item.id, modelTransform: item.modelTransform, in: &interactionRecords)
                    try emitDirectedArrow(
                        route: .polySplineSurfaceVertex,
                        origin: origin,
                        direction: direction,
                        length: 0.06,
                        identity: identity,
                        input: input,
                        startGap: 16,
                        hitTolerancePoints: 8.0,
                        occurrenceID: item.id,
                        checkpoint: checkpoint,
                        cameraLines: &cameraLines
                    )
                }
                for localAxis in ViewportPolySplineSurfaceVertexLocalAxis.allCases {
                    guard let local = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.localDirection(
                        for: parsed,
                        direction: localAxis.slideDirection,
                        topologyVertices: topologyVertices,
                        patches: patches
                    ) else {
                        continue
                    }
                    let direction = item.modelTransform.viewportTransformedVector(local)
                    prepared.dragMode = .localAxis(localAxis, direction: local)
                    _ = try handleIndex(for: .polySplineSurfaceVertex(prepared), occurrenceID: item.id, modelTransform: item.modelTransform, in: &interactionRecords)
                    let identity = ViewportSpatialHandleIdentity.polySplineSurfaceVertex(
                        featureID: parsed.featureID,
                        componentID: componentID,
                        role: .localAxis(localAxis)
                    )
                    try emitDirectedArrow(
                        route: .polySplineSurfaceVertex,
                        origin: origin,
                        direction: direction,
                        length: 0.07,
                        identity: identity,
                        input: input,
                        startGap: 16,
                        hitTolerancePoints: 8.0,
                        occurrenceID: item.id,
                        checkpoint: checkpoint,
                        cameraLines: &cameraLines
                    )
                }
                if let active = activeValue(for: centerIdentity, input: input),
                   case .delta(let delta) = active.kind {
                    let moved = origin + item.modelTransform.viewportTransformedVector(delta)
                    try appendWorldLine(
                        .init(
                            route: .polySplineSurfaceVertex,
                            points: [origin, moved],
                            closed: false,
                            color: editColor,
                            family: .transform,
                            identity: centerIdentity,
                            state: .active
                        ),
                        to: &worldLines,
                        checkpoint: checkpoint
                    )
                    try appendMarker(
                        .init(
                            route: .polySplineSurfaceVertex,
                            anchor: moved,
                            shape: .box,
                            diameterPoints: 8,
                            color: editColor,
                            family: .transform,
                            identity: centerIdentity,
                            state: .active,
                            hitTolerancePoints: 12.0,
                            occurrenceID: item.id
                        ),
                        to: &markers,
                        checkpoint: checkpoint
                    )
                }
            }
        }

        let slideTargets = input.selection.selectedTargets.compactMap { target -> (SelectionTarget, PolySplineSurfaceVertexTarget, ViewportSceneItem, Point3D)? in
            guard case .vertex(let componentID) = target.component,
                  let parsed = PolySplineSurfaceVertexTarget.parse(componentID: componentID),
                  let item = sceneItem(for: target, input: input),
                  case .body(let component) = item.kind,
                  let vertex = component.topology?.vertices.first(where: { $0.componentID == componentID }) else {
                return nil
            }
            return (target, parsed, item, vertex.point)
        }
        if input.interactiveRoutes.contains(.polySplineSurfaceVertexSlide), !slideTargets.isEmpty {
            let inputs = slideTargets.map {
                ViewportPolySplineSurfaceVertexSlideInput(
                    target: $0.1,
                    selectionTarget: $0.0,
                    point: $0.3,
                    modelTransform: $0.2.modelTransform
                )
            }
            for direction in PolySplineSurfaceVertexSlideDirection.allCases {
                let localDirections = inputs.compactMap {
                    ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.localDirection(
                            for: $0.target,
                            direction: direction,
                            topologyVertices: topologyVertices,
                            patches: patches
                    )
                }
                guard localDirections.count == inputs.count else {
                    throw RealityViewportSpatialBatch.invalid("A grouped poly-spline source direction is missing.")
                }
                let worldVectors = zip(inputs, localDirections).map {
                    $0.0.modelTransform.viewportTransformedVector($0.1)
                }
                let vectors = worldVectors.compactMap { normalized($0) }
                guard vectors.count == inputs.count else {
                    throw RealityViewportSpatialBatch.invalid("A grouped poly-spline world direction is degenerate.")
                }
                guard let worldDirection = average(vectors) else { continue }
                let origin = average(inputs.map { $0.modelTransform.viewportTransformedPoint($0.point) })
                let identity = ViewportSpatialHandleIdentity.polySplineSurfaceVertexSlide(
                    .init(targets: inputs.map(\.selectionTarget), direction: direction)
                )
                let factors = try zip(inputs, worldVectors).map {
                    try ViewportNativeAxisInput.sourceUnitsPerWorldMetre(for: $0.1, in: $0.0.modelTransform)
                }
                let factor = try ViewportNativeAxisInput.commonSourceScale(factors)
                _ = try handleIndex(for: .polySplineSurfaceVertexSlide(
                    targets: inputs.map(\.selectionTarget), direction: direction,
                    axis: .init(origin: origin, direction: worldDirection, baseValue: 0,
                                sourceUnitsPerWorldMetre: factor)
                ), in: &interactionRecords)
                let guideLength = max(input.ruler.majorTickMeters * 0.25, 0.05)
                let guideTip = offset(origin, direction: worldDirection, distance: guideLength)
                try emitDirectedArrow(
                    route: .polySplineSurfaceVertexSlide,
                    origin: origin,
                    direction: worldDirection,
                    length: guideLength,
                    identity: identity,
                    input: input,
                    minimumLength: 62,
                    startGap: 16,
                    hitTolerancePoints: 10.0,
                    checkpoint: checkpoint,
                    cameraLines: &cameraLines
                )
                try appendCameraPath(
                    .init(
                        route: .polySplineSurfaceVertexSlide,
                        path: diamondPath(radius: 6),
                        placement: .init(anchor: origin, toward: guideTip, minimumLength: 62),
                        color: axisColor(for: identity),
                        family: .transform,
                        identity: identity,
                        state: state(for: identity, input: input),
                        hitTolerancePoints: 14.0
                    ),
                    to: &cameraPaths,
                    checkpoint: checkpoint
                )
                if let active = activeValue(for: identity, input: input),
                   case .distance(let distance) = active.kind {
                    let previews = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.previewVertices(
                        selectedVertices: inputs,
                        topologyVertices: topologyVertices,
                        patches: patches,
                        direction: direction,
                        distanceMeters: distance
                    ) ?? []
                    try emitSlidePreview(
                        route: .activePolySplineSurfaceVertexPreview,
                        previews: previews.map { ($0.originalPoint, $0.movedPoint) },
                        identity: identity,
                        input: input,
                        checkpoint: checkpoint,
                        worldLines: &worldLines,
                        markers: &markers
                    )
                    if let surfaces = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.previewSurfaces(
                        selectedVertices: inputs,
                        topologyVertices: topologyVertices,
                        patches: patches,
                        direction: direction,
                        distanceMeters: distance,
                        tolerance: input.document.modelingSettings.tolerance
                    ) {
                        for surface in surfaces {
                            let mesh = input.modifierControl ? surface.originalMesh : surface.movedMesh
                            try appendPreviewMesh(
                                route: .activePolySplineSurfaceVertexPreview,
                                mesh: mesh,
                                identity: identity,
                                input: input,
                                checkpoint: checkpoint,
                                meshes: &meshes
                            )
                        }
                    }
                    if input.modifierControl || active.showsOriginalComparison {
                        for preview in previews {
                            try appendWorldLine(
                                .init(
                                    route: .activePolySplineSurfaceVertexPreview,
                                    points: [preview.originalPoint, preview.movedPoint],
                                    closed: false,
                                    color: editColor,
                                    family: .transform,
                                    identity: identity,
                                    state: .preview
                                ),
                                to: &worldLines,
                                checkpoint: checkpoint
                            )
                        }
                    }
                }
            }
        }

        try emitSelectedControlAndTrimHandles(
            input: input,
            interactionRecords: &interactionRecords,
            topologyVertices: topologyVertices,
            patches: patches,
            checkpoint: checkpoint,
            worldLines: &worldLines,
            cameraLines: &cameraLines,
            cameraPaths: &cameraPaths,
            labels: &labels,
            markers: &markers,
            meshes: &meshes
        )
    }

    static func activeValue(
        for identity: ViewportSpatialHandleIdentity,
        input: SurfaceTransformAffordanceSource.RawInput
    ) -> SurfaceTransformActiveValue? {
        input.activeValues.first { $0.identity == identity }
    }

    static func average(_ points: [Point3D]) -> Point3D {
        guard !points.isEmpty else { return .origin }
        let count = Double(points.count)
        return Point3D(
            x: points.reduce(0) { $0 + $1.x } / count,
            y: points.reduce(0) { $0 + $1.y } / count,
            z: points.reduce(0) { $0 + $1.z } / count
        )
    }

    static func average(_ vectors: [Vector3D]) -> Vector3D? {
        guard !vectors.isEmpty else { return nil }
        let result = vectors.reduce(.zero, +) * (1.0 / Double(vectors.count))
        return normalized(result)
    }

    static func emitDirectedArrow(
        route: SurfaceTransformAffordanceRoute,
        origin: Point3D,
        direction: Vector3D,
        length: Double,
        identity: ViewportSpatialHandleIdentity,
        input: SurfaceTransformAffordanceSource.RawInput,
        minimumLength: CGFloat? = nil,
        fixedLengthPoints: CGFloat? = nil,
        startGap: CGFloat? = nil,
        hitTolerancePoints: Float? = nil,
        occurrenceID: String? = nil,
        checkpoint: (Int, Int, Int) throws -> Void,
        cameraLines: inout [SurfaceTransformAffordanceSource.CameraLine]
    ) throws {
        guard let direction = normalized(direction), length.isFinite, length > 0 else {
            throw RealityViewportSpatialBatch.invalid("Surface/transform affordance has no usable direction.")
        }
        let tip = offset(origin, direction: direction, distance: length)
        let state = state(for: identity, input: input)
        if let startGap {
            guard startGap.isFinite, startGap >= 0 else {
                throw RealityViewportSpatialBatch.invalid("Surface/transform affordance has an invalid start gap.")
            }
        }
        // A minimum length lets the arrow grow with the value it draws; a fixed
        // length pins it on screen. Requesting both would leave the reader
        // unable to tell which of the two the drawn length means.
        let endPoint: SurfaceTransformAffordanceSource.DirectedPoint
        if let fixedLengthPoints {
            guard minimumLength == nil else {
                throw RealityViewportSpatialBatch.invalid(
                    "A fixed-length affordance arrow cannot also request a projected minimum length."
                )
            }
            guard fixedLengthPoints.isFinite, fixedLengthPoints >= (startGap ?? 0) else {
                throw RealityViewportSpatialBatch.invalid(
                    "A fixed-length affordance arrow is invalid or shorter than its start gap."
                )
            }
            endPoint = .init(anchor: origin, toward: tip, parallel: fixedLengthPoints)
        } else {
            endPoint = .init(
                anchor: origin,
                toward: tip,
                minimumLength: max(minimumLength ?? 0, startGap ?? 0)
            )
        }
        let startPoint = startGap.map {
            SurfaceTransformAffordanceSource.DirectedPoint(
                anchor: origin,
                toward: tip,
                parallel: $0
            )
        } ?? SurfaceTransformAffordanceSource.DirectedPoint(
            anchor: origin,
            toward: origin,
            usesFixedOffset: true
        )
        let guide = SurfaceTransformAffordanceSource.CameraLine(
            route: route,
            points: [startPoint, endPoint],
            color: axisColor(for: identity),
            family: .transform,
            identity: identity,
            state: state,
            hitTolerancePoints: hitTolerancePoints,
            occurrenceID: occurrenceID
        )
        try appendCameraLine(guide, to: &cameraLines, checkpoint: checkpoint)
    }

    /// The colour a handle is drawn in, which for a handle that moves along one
    /// world axis is that axis's own colour.
    ///
    /// The transform gizmo's translate arrows are the world axes, and their tip
    /// markers already carry the axis colour, so a shaft drawn in the neutral
    /// edit colour said less than the marker on its end. Naming the axis on the
    /// shaft as well is what lets a drag be aimed before it is released, rather
    /// than read back afterwards from where the body went.
    ///
    /// Only `translate` is named here. The other gizmo actions carry an axis
    /// too, but they scale and rotate about it rather than move along it, and
    /// this route does not claim to say what those mean.
    static func axisColor(for identity: ViewportSpatialHandleIdentity) -> SIMD4<Float> {
        switch identity {
        case .objectTransform(_, let action):
            if case .translate(let axis) = action { return axisColor(axis) }
            return editColor
        case .affordance(let target):
            switch target.action {
            case .translate(let axis): return axisColor(axis)
            default: return editColor
            }
        case .polySplineSurfaceVertex(_, _, let role), .surfaceControlPoint(_, let role):
            switch role {
            case .axis(let axis): return axisColor(axis)
            case .localAxis(let axis):
                switch axis {
                case .u: return SIMD4<Float>(0.28, 0.86, 0.64, 0.95)
                case .v: return SIMD4<Float>(0.95, 0.46, 0.78, 0.95)
                case .normal: return editColor
                }
            case .planar: return editColor
            }
        default:
            return editColor
        }
    }

    static func emitSlidePreview(
        route: SurfaceTransformAffordanceRoute,
        previews: [(Point3D, Point3D)],
        identity: ViewportSpatialHandleIdentity,
        input: SurfaceTransformAffordanceSource.RawInput,
        checkpoint: (Int, Int, Int) throws -> Void,
        worldLines: inout [SurfaceTransformAffordanceSource.WorldLine],
        markers: inout [SurfaceTransformAffordanceSource.Marker]
    ) throws {
        for (original, moved) in previews {
            try appendWorldLine(
                .init(
                    route: route,
                    points: [original, moved],
                    closed: false,
                    color: editColor,
                    family: .transform,
                    identity: identity,
                    state: .preview
                ),
                to: &worldLines,
                checkpoint: checkpoint
            )
            try appendMarker(
                .init(
                    route: route,
                    anchor: input.modifierControl ? original : moved,
                    shape: .box,
                    diameterPoints: 7,
                    color: editColor,
                    family: .transform,
                    identity: identity,
                    state: .preview
                ),
                to: &markers,
                checkpoint: checkpoint
            )
        }
    }

    static func appendPreviewMesh(
        route: SurfaceTransformAffordanceRoute,
        mesh: ViewportBodyMesh,
        identity: ViewportSpatialHandleIdentity,
        input: SurfaceTransformAffordanceSource.RawInput,
        checkpoint: (Int, Int, Int) throws -> Void,
        meshes: inout [SurfaceTransformAffordanceSource.Mesh]
    ) throws {
        guard !mesh.positions.isEmpty,
              !mesh.indices.isEmpty,
              mesh.indices.count.isMultiple(of: 3),
              mesh.positions.allSatisfy(isFinitePoint) else {
            throw RealityViewportSpatialBatch.invalid("Surface preview mesh has invalid topology.")
        }
        guard mesh.indices.allSatisfy({ Int($0) < mesh.positions.count }) else {
            throw RealityViewportSpatialBatch.invalid("Surface preview mesh references an absent vertex.")
        }
        try checkpoint(1, mesh.positions.count, mesh.indices.count)
        meshes.append(
            .init(
                route: route,
                positions: mesh.positions,
                indices: mesh.indices,
                topology: .triangles,
                color: editColor,
                family: .transform,
                identity: identity,
                state: .preview
            )
        )
    }

    static func emitSelectedControlAndTrimHandles(
        input: SurfaceTransformAffordanceSource.RawInput,
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        topologyVertices: [ViewportBodyTopology.Vertex],
        patches: [FeatureID: [ViewportPolySplinePatchDescriptor]],
        checkpoint: (Int, Int, Int) throws -> Void,
        worldLines: inout [SurfaceTransformAffordanceSource.WorldLine],
        cameraLines: inout [SurfaceTransformAffordanceSource.CameraLine],
        cameraPaths: inout [SurfaceTransformAffordanceSource.CameraPath],
        labels: inout [SurfaceTransformAffordanceSource.Label],
        markers: inout [SurfaceTransformAffordanceSource.Marker],
        meshes: inout [SurfaceTransformAffordanceSource.Mesh]
    ) throws {
        let selectedReferences = input.selection.selectedReferences
            + (input.selection.hoveredReference.map { [$0] } ?? [])
        guard !selectedReferences.isEmpty else { return }

        if input.interactiveRoutes.contains(.surfaceControlPoint) {
            for reference in selectedReferences {
                guard case .surface(.controlPoint) = reference else { continue }
                for item in input.scene.items {
                    guard case .body(let component) = item.kind,
                          let display = component.surfaceControlPointDisplays.first(where: {
                              $0.selectionReference == reference
                          }) else { continue }
                    let origin = item.modelTransform.viewportTransformedPoint(display.point)
                    let identity = ViewportSpatialHandleIdentity.surfaceControlPoint(
                        .init(reference),
                        role: .planar
                    )
                    if let active = activeValue(for: identity, input: input),
                       case .delta(let delta) = active.kind {
                        let moved = origin + item.modelTransform.viewportTransformedVector(delta)
                        try appendWorldLine(
                            .init(
                                route: .surfaceControlPoint,
                                points: [origin, moved],
                                closed: false,
                                color: editColor,
                                family: .transform,
                                identity: identity,
                                state: .active,
                                occurrenceID: item.id
                            ),
                            to: &worldLines,
                            checkpoint: checkpoint
                        )
                        try appendMarker(
                            .init(
                                route: .surfaceControlPoint,
                                anchor: moved,
                                shape: .box,
                                diameterPoints: 8,
                                color: editColor,
                                family: .transform,
                                identity: identity,
                                state: .active,
                                occurrenceID: item.id
                            ),
                            to: &markers,
                            checkpoint: checkpoint
                        )
                    }
                    break
                }
            }
        }

        var slideInputs: [ViewportSurfaceControlPointSlideInput] = []
        for reference in input.selection.selectedReferences {
            guard case .surface(.controlPoint) = reference,
                  let patch = surfaceControlPointPatch(for: reference, document: input.document) else {
                continue
            }
            for item in input.scene.items {
                guard item.featureID == patch.featureID,
                      case .body(let component) = item.kind,
                      let display = component.surfaceControlPointDisplays.first(where: {
                          $0.selectionReference == reference
                      }) else { continue }
                slideInputs.append(
                    .init(
                        target: reference,
                        featureID: patch.featureID,
                        patchID: patch.patchID,
                        point: display.point,
                        modelTransform: item.modelTransform
                    )
                )
                break
            }
        }
        if input.interactiveRoutes.contains(.surfaceControlPointSlide), !slideInputs.isEmpty {
            let patchValues = patches
            let addresses = slideInputs.map { ViewportSpatialReferenceAddress($0.target) }
            for direction in PolySplineSurfaceVertexSlideDirection.allCases {
                let worldVectors = slideInputs.compactMap { controlPoint in
                    ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.localDirection(
                        featureID: controlPoint.featureID,
                        patchID: controlPoint.patchID,
                        direction: direction,
                        topologyVertices: topologyVertices,
                        patches: patchValues
                    ).map { controlPoint.modelTransform.viewportTransformedVector($0) }
                }
                guard worldVectors.count == slideInputs.count else {
                    throw RealityViewportSpatialBatch.invalid("A grouped surface source direction is missing.")
                }
                let vectors = worldVectors.compactMap { normalized($0) }
                guard vectors.count == slideInputs.count else {
                    throw RealityViewportSpatialBatch.invalid("A grouped surface world direction is degenerate.")
                }
                guard let worldDirection = average(vectors) else { continue }
                let origin = average(slideInputs.map {
                    $0.modelTransform.viewportTransformedPoint($0.point)
                })
                let identity = ViewportSpatialHandleIdentity.surfaceControlPointSlide(
                    addresses,
                    direction: direction
                )
                let factors = try zip(slideInputs, worldVectors).map {
                    try ViewportNativeAxisInput.sourceUnitsPerWorldMetre(for: $0.1, in: $0.0.modelTransform)
                }
                let factor = try ViewportNativeAxisInput.commonSourceScale(factors)
                _ = try handleIndex(for: .surfaceControlPointSlide(
                    targets: slideInputs.map(\.target), direction: direction,
                    axis: .init(origin: origin, direction: worldDirection, baseValue: 0,
                                sourceUnitsPerWorldMetre: factor)
                ), in: &interactionRecords)
                let guideLength = max(input.ruler.majorTickMeters * 0.25, 0.05)
                let guideTip = offset(origin, direction: worldDirection, distance: guideLength)
                try emitDirectedArrow(
                    route: .surfaceControlPointSlide,
                    origin: origin,
                    direction: worldDirection,
                    length: guideLength,
                    identity: identity,
                    input: input,
                    minimumLength: 62,
                    startGap: 16,
                    hitTolerancePoints: 10.0,
                    checkpoint: checkpoint,
                    cameraLines: &cameraLines
                )
                try appendCameraPath(
                    .init(
                        route: .surfaceControlPointSlide,
                        path: diamondPath(radius: 6),
                        placement: .init(anchor: origin, toward: guideTip, minimumLength: 62),
                        color: axisColor(for: identity),
                        family: .transform,
                        identity: identity,
                        state: state(for: identity, input: input),
                        hitTolerancePoints: 14.0
                    ),
                    to: &cameraPaths,
                    checkpoint: checkpoint
                )
                if let active = activeValue(for: identity, input: input),
                   case .distance(let distance) = active.kind {
                    let previews = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.previewControlPoints(
                        selectedControlPoints: slideInputs,
                        topologyVertices: topologyVertices,
                        patches: patchValues,
                        direction: direction,
                        distanceMeters: distance
                    ) ?? []
                    try emitSlidePreview(
                        route: .activeSurfaceControlPointPreview,
                        previews: previews.map { ($0.originalPoint, $0.movedPoint) },
                        identity: identity,
                        input: input,
                        checkpoint: checkpoint,
                        worldLines: &worldLines,
                        markers: &markers
                    )
                }
                if input.modifierControl,
                   let active = activeValue(for: identity, input: input),
                   case .distance(let distance) = active.kind,
                   let previews = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.previewControlPoints(
                       selectedControlPoints: slideInputs,
                       topologyVertices: topologyVertices,
                       patches: patchValues,
                       direction: direction,
                       distanceMeters: distance
                   ) {
                    for preview in previews {
                        try appendWorldLine(
                            .init(
                                route: .activeSurfaceControlPointPreview,
                                points: [preview.originalPoint, preview.movedPoint],
                                closed: false,
                                color: editColor,
                                family: .transform,
                                identity: identity,
                                state: .preview
                            ),
                            to: &worldLines,
                            checkpoint: checkpoint
                        )
                    }
                }
            }
        }

        for reference in selectedReferences {
            for item in input.scene.items {
                guard case .body(let component) = item.kind else { continue }
                if input.interactiveRoutes.contains(.surfaceTrimEndpoint) {
                    for display in component.surfaceTrimEndpointDisplays
                    where display.selectionReference == reference {
                        let origin = item.modelTransform.viewportTransformedPoint(display.point)
                        let identity = ViewportSpatialHandleIdentity.surfaceTrimEndpoint(
                            .init(reference), endpoint: display.endpoint
                        )
                        if let active = activeValue(for: identity, input: input),
                           case .delta(let delta) = active.kind {
                            let moved = origin + item.modelTransform.viewportTransformedVector(delta)
                            try appendWorldLine(
                                .init(
                                    route: .surfaceTrimEndpoint,
                                    points: [origin, moved],
                                    closed: false,
                                    color: editColor,
                                    family: .transform,
                                    identity: identity,
                                    state: .active,
                                    occurrenceID: item.id
                                ),
                                to: &worldLines,
                                checkpoint: checkpoint
                            )
                            try appendMarker(
                                .init(
                                    route: .surfaceTrimEndpoint,
                                    anchor: moved,
                                    shape: .box,
                                    diameterPoints: 8,
                                    color: editColor,
                                    family: .transform,
                                    identity: identity,
                                    state: .active,
                                    occurrenceID: item.id
                                ),
                                to: &markers,
                                checkpoint: checkpoint
                            )
                        }
                    }
                }
                if input.interactiveRoutes.contains(.surfaceTrimControlPoint) {
                    for display in component.surfaceTrimControlPointDisplays
                    where display.selectionReference == reference {
                        let origin = item.modelTransform.viewportTransformedPoint(display.point)
                        let identity = ViewportSpatialHandleIdentity.surfaceTrimControlPoint(
                            .init(reference), index: display.controlPointIndex
                        )
                        if let active = activeValue(for: identity, input: input),
                           case .delta(let delta) = active.kind {
                            let moved = origin + item.modelTransform.viewportTransformedVector(delta)
                            try appendWorldLine(
                                .init(
                                    route: .surfaceTrimControlPoint,
                                    points: [origin, moved],
                                    closed: false,
                                    color: editColor,
                                    family: .transform,
                                    identity: identity,
                                    state: .active,
                                    occurrenceID: item.id
                                ),
                                to: &worldLines,
                                checkpoint: checkpoint
                            )
                            try appendMarker(
                                .init(
                                    route: .surfaceTrimControlPoint,
                                    anchor: moved,
                                    shape: .box,
                                    diameterPoints: 8,
                                    color: editColor,
                                    family: .transform,
                                    identity: identity,
                                    state: .active,
                                    occurrenceID: item.id
                                ),
                                to: &markers,
                                checkpoint: checkpoint
                            )
                        }
                    }
                }
            }
        }
    }

    static func surfaceControlPointPatch(
        for reference: SelectionReference,
        document: DesignDocument
    ) -> (featureID: FeatureID, patchID: Int)? {
        guard case .surface(.controlPoint(let controlPoint)) = reference else { return nil }
        let id = controlPoint.surface.subshape.subshapeID
        let parts = id.role.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "polySpline" else { return nil }
        let patch = parts[1].split(separator: ":").map(String.init)
        guard patch.count == 3, patch[0] == "patch", let patchID = Int(patch[1]), patch[2] == "face" else {
            return nil
        }
        _ = document
        return (id.featureID, patchID)
    }

    static func emitConstruction(
        input: SurfaceTransformAffordanceSource.RawInput,
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        checkpoint: (Int, Int, Int) throws -> Void,
        worldLines: inout [SurfaceTransformAffordanceSource.WorldLine],
        worldFills: inout [SurfaceTransformAffordanceSource.WorldFill],
        markers: inout [SurfaceTransformAffordanceSource.Marker],
        meshes: inout [SurfaceTransformAffordanceSource.Mesh]
    ) throws {
        if input.enabledRoutes.contains(.constructionPlane) {
            var registeredPlaneHandles: [(ViewportSpatialHandleIdentity, String?)] = []
            for target in input.selection.selectedTargets {
                guard case .constructionPlane(let planeID) = target.component else { continue }
                guard let source = input.document.productMetadata.constructionPlanes[planeID],
                      input.document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.constructionPlaneID == planeID else {
                    throw RealityViewportSpatialBatch.invalid("Construction-plane selection is not backed by document metadata.")
                }
                let model = try constructionPlaneModel(
                    planeID: planeID,
                    sceneNodeID: target.sceneNodeID,
                    source: source,
                    input: input
                )
                let occurrenceItem = input.scene.items.first {
                    $0.sceneNodeID == target.sceneNodeID
                }
                let occurrenceID = occurrenceItem?.id
                let occurrenceModelTransform = occurrenceItem?.modelTransform ?? .identity
                let originIdentity: ViewportSpatialHandleIdentity? = input.interactiveRoutes.contains(.constructionPlane)
                    ? .constructionPlane(.init(
                        constructionPlaneID: planeID,
                        sceneNodeID: target.sceneNodeID,
                        handle: .origin
                    )) : nil
                let normalIdentity: ViewportSpatialHandleIdentity? = input.interactiveRoutes.contains(.constructionPlane)
                    ? .constructionPlane(.init(
                        constructionPlaneID: planeID,
                        sceneNodeID: target.sceneNodeID,
                        handle: .normal
                    )) : nil
                if let originIdentity,
                   !registeredPlaneHandles.contains(where: { $0.0 == originIdentity && $0.1 == occurrenceID }) {
                    _ = try handleIndex(for: .constructionPlane(
                        identity: .init(
                            constructionPlaneID: planeID,
                            sceneNodeID: target.sceneNodeID,
                            handle: .origin
                        ),
                        origin: model.baselineOrigin,
                        normal: model.baselineNormal,
                        normalEnd: model.baselineNormalEnd,
                        corners: model.baselineCorners
                    ), occurrenceID: occurrenceID, modelTransform: occurrenceModelTransform, in: &interactionRecords)
                    registeredPlaneHandles.append((originIdentity, occurrenceID))
                }
                if let normalIdentity,
                   !registeredPlaneHandles.contains(where: { $0.0 == normalIdentity && $0.1 == occurrenceID }) {
                    _ = try handleIndex(for: .constructionPlane(
                        identity: .init(
                            constructionPlaneID: planeID,
                            sceneNodeID: target.sceneNodeID,
                            handle: .normal
                        ),
                        origin: model.baselineOrigin,
                        normal: model.baselineNormal,
                        normalEnd: model.baselineNormalEnd,
                        corners: model.baselineCorners
                    ), occurrenceID: occurrenceID, modelTransform: occurrenceModelTransform, in: &interactionRecords)
                    registeredPlaneHandles.append((normalIdentity, occurrenceID))
                }
                try appendWorldLine(
                    .init(
                        route: .constructionPlane,
                        points: model.corners,
                        closed: true,
                        color: referenceColor,
                        family: .construction,
                        identity: nil,
                        state: .normal
                    ),
                    to: &worldLines,
                    checkpoint: checkpoint
                )
                try appendWorldLine(
                    .init(
                        route: .constructionPlane,
                        points: [model.origin, model.normalEnd],
                        closed: false,
                        color: sectionNormalColor,
                        family: .construction,
                        identity: normalIdentity,
                        state: state(for: normalIdentity, input: input),
                        hitTolerancePoints: normalIdentity == nil ? nil : 14.0,
                        occurrenceID: normalIdentity == nil ? nil : occurrenceID
                    ),
                    to: &worldLines,
                    checkpoint: checkpoint
                )
                try appendMarker(
                    .init(
                        route: .constructionPlane,
                        anchor: model.origin,
                        shape: .box,
                        diameterPoints: 8,
                        color: referenceColor,
                        family: .construction,
                        identity: originIdentity,
                        state: state(for: originIdentity, input: input),
                        hitTolerancePoints: originIdentity == nil ? nil : 12.0,
                        occurrenceID: originIdentity == nil ? nil : occurrenceID
                    ),
                    to: &markers,
                    checkpoint: checkpoint
                )
                try appendMarker(
                    .init(
                        route: .constructionPlane,
                        anchor: model.normalEnd,
                        shape: .sphere,
                        diameterPoints: 8,
                        color: sectionNormalColor,
                        family: .construction,
                        identity: normalIdentity,
                        state: state(for: normalIdentity, input: input),
                        hitTolerancePoints: normalIdentity == nil ? nil : 14.0,
                        occurrenceID: normalIdentity == nil ? nil : occurrenceID
                    ),
                    to: &markers,
                    checkpoint: checkpoint
                )
            }
        }

        guard input.enabledRoutes.contains(.constructionFace),
              let target = input.constructionFaceTarget else { return }
        guard case .face(let componentID) = target.component,
              let item = sceneItem(for: target, input: input),
              case .body(let component) = item.kind else {
            throw RealityViewportSpatialBatch.invalid("Construction-face highlight has no matching body topology.")
        }
        if componentID.generatedTopologySubshapeID != nil {
            let mesh = try selectedFaceMesh(componentID, item: item, component: component,
                color: SIMD4<Float>(hoverColor.x, hoverColor.y, hoverColor.z, 0.16))
            try checkpoint(mesh.positions.count, mesh.indices.count, 1)
            meshes.append(.init(route: .constructionFace, positions: mesh.positions,
                indices: mesh.indices, topology: mesh.topology, color: mesh.color,
                family: .construction, identity: nil, state: .normal))
            return
        }
        guard let face = component.topology?.faces.first(where: { $0.componentID == componentID }) else {
            throw RealityViewportSpatialBatch.invalid("Construction-face highlight has no matching body topology.")
        }
        let points = face.points.map { item.modelTransform.viewportTransformedPoint($0) }
        guard points.count >= 3, points.allSatisfy(isFinitePoint) else {
            throw RealityViewportSpatialBatch.invalid("Construction-face highlight has invalid world points.")
        }
        let state: SurfaceTransformAffordanceState = input.selection.hoveredTarget == target ? .hovered : .normal
        try appendWorldFill(
            .init(
                route: .constructionFace,
                points: points,
                color: SIMD4<Float>(hoverColor.x, hoverColor.y, hoverColor.z, 0.16),
                family: .construction,
                identity: nil,
                state: state
            ),
            to: &worldFills,
            checkpoint: checkpoint
        )
        try appendWorldLine(
            .init(
                route: .constructionFace,
                points: points,
                closed: true,
                color: hoverColor,
                family: .construction,
                identity: nil,
                state: state
            ),
            to: &worldLines,
            checkpoint: checkpoint
        )
    }

    struct ConstructionPlaneModel {
        let origin: Point3D
        let normal: Vector3D
        let normalEnd: Point3D
        let corners: [Point3D]
        let baselineOrigin: Point3D
        let baselineNormal: Vector3D
        let baselineNormalEnd: Point3D
        let baselineCorners: [Point3D]
    }

    static func constructionPlaneModel(
        planeID: ConstructionPlaneSourceID,
        sceneNodeID: SceneNodeID,
        source: ConstructionPlaneSource,
        input: SurfaceTransformAffordanceSource.RawInput
    ) throws -> ConstructionPlaneModel {
        var activePlane = source.plane
        let originIdentity = ViewportSpatialHandleIdentity.constructionPlane(
            .init(constructionPlaneID: planeID, sceneNodeID: sceneNodeID, handle: .origin)
        )
        let normalIdentity = ViewportSpatialHandleIdentity.constructionPlane(
            .init(constructionPlaneID: planeID, sceneNodeID: sceneNodeID, handle: .normal)
        )
        let activeOrigin = activeValue(for: originIdentity, input: input)
        let activeNormal = activeValue(for: normalIdentity, input: input)
        if case .plane(let origin, let normal) = activeOrigin?.kind {
            activePlane = .plane(.init(origin: origin, normal: normal))
        } else if case .plane(let origin, let normal) = activeNormal?.kind {
            activePlane = .plane(.init(origin: origin, normal: normal))
        }
        let coordinateSystem: SketchPlaneCoordinateSystem
        let baselineCoordinateSystem: SketchPlaneCoordinateSystem
        do {
            coordinateSystem = try SketchPlaneCoordinateSystem(plane: activePlane)
            baselineCoordinateSystem = try SketchPlaneCoordinateSystem(plane: source.plane)
        } catch {
            throw RealityViewportSpatialBatch.invalid("Construction-plane source has an invalid basis.")
        }
        let modelSpan = max(
            input.scene.modelBounds.map { Double(max($0.width, $0.height)) } ?? 0,
            input.ruler.visibleSpanMeters
        )
        let guideLength = max(
            input.ruler.majorTickMeters,
            min(input.ruler.visibleSpanMeters * 0.12, modelSpan * 0.20)
        )
        let halfExtent = max(guideLength * 1.7, max(modelSpan, guideLength) * 0.14)
        func geometry(for coordinateSystem: SketchPlaneCoordinateSystem) throws -> (
            origin: Point3D,
            normal: Vector3D,
            normalEnd: Point3D,
            corners: [Point3D]
        ) {
            let origin = coordinateSystem.origin
            let normalEnd = offset(origin, direction: coordinateSystem.normal, distance: guideLength)
            let negativeU = coordinateSystem.u * (-halfExtent)
            let positiveU = coordinateSystem.u * halfExtent
            let negativeV = coordinateSystem.v * (-halfExtent)
            let positiveV = coordinateSystem.v * halfExtent
            let corners = [
                origin + negativeU + negativeV,
                origin + positiveU + negativeV,
                origin + positiveU + positiveV,
                origin + negativeU + positiveV,
            ]
            guard origin.isFinite, normalEnd.isFinite, corners.allSatisfy(isFinitePoint) else {
                throw RealityViewportSpatialBatch.invalid("Construction-plane geometry is not finite.")
            }
            return (origin, coordinateSystem.normal, normalEnd, corners)
        }
        let activeGeometry = try geometry(for: coordinateSystem)
        let baselineGeometry = try geometry(for: baselineCoordinateSystem)
        return ConstructionPlaneModel(
            origin: activeGeometry.origin,
            normal: activeGeometry.normal,
            normalEnd: activeGeometry.normalEnd,
            corners: activeGeometry.corners,
            baselineOrigin: baselineGeometry.origin,
            baselineNormal: baselineGeometry.normal,
            baselineNormalEnd: baselineGeometry.normalEnd,
            baselineCorners: baselineGeometry.corners
        )
    }

    static func emitTransforms(
        input: SurfaceTransformAffordanceSource.RawInput,
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        checkpoint: (Int, Int, Int) throws -> Void,
        worldLines: inout [SurfaceTransformAffordanceSource.WorldLine],
        cameraLines: inout [SurfaceTransformAffordanceSource.CameraLine],
        cameraPaths: inout [SurfaceTransformAffordanceSource.CameraPath],
        markers: inout [SurfaceTransformAffordanceSource.Marker],
        meshes: inout [SurfaceTransformAffordanceSource.Mesh]
    ) throws {
        guard input.enabledRoutes.contains(.bodyTransform) else { return }
        if input.enabledRoutes.contains(.bodyTransform), input.presentationScene != nil,
           let members = try presentationTransformMembers(input: input), !members.isEmpty {
            let bounds = ViewportObjectEditState(
                xMin: members.map { $0.bounds.xMin }.min()!, xMax: members.map { $0.bounds.xMax }.max()!,
                yMin: members.map { $0.bounds.yMin }.min()!, yMax: members.map { $0.bounds.yMax }.max()!,
                zMin: members.map { $0.bounds.zMin }.min()!, zMax: members.map { $0.bounds.zMax }.max()!,
                preservesZeroExtents: true)
            try emitBodyTransform(featureID: nil, selectionTarget: nil,
                occurrenceID: members.count == 1 ? members[0].occurrenceID : nil,
                modelTransform: .identity, edit: bounds, bodyMembers: [], groupEdit: nil,
                placement: nil, objectMembers: members, input: input,
                interactionRecords: &interactionRecords, checkpoint: checkpoint,
                worldLines: &worldLines, cameraLines: &cameraLines, cameraPaths: &cameraPaths, markers: &markers)
        }
        let bodyItems = input.scene.items.filter { item in
            guard case .body = item.kind else { return false }
            return input.selection.selectedTargets.contains { target in
                target.component == .object && target.sceneNodeID == item.sceneNodeID
            }
        }
        let sketchItems = input.selection.selectedTargets.compactMap { target -> ViewportSceneItem? in
            guard target.component == .object,
                  let item = input.scene.items.first(where: { $0.sceneNodeID == target.sceneNodeID }),
                  case .sketch = item.kind else { return nil }
            return item
        }
        let drawsBodyGizmo = input.presentationScene == nil && input.enabledRoutes.contains(.bodyTransform) && !bodyItems.isEmpty
        let drawsSketchGizmo = input.enabledRoutes.contains(.bodyTransform) && !sketchItems.isEmpty
        guard drawsBodyGizmo || drawsSketchGizmo else { return }
        // One walk of the scene tree answers every transform gizmo in this
        // frame, and it is taken only when the frame draws at least one. Body
        // and sketch items alike commit a scene node's local frame within its
        // parent's world frame, so a second walk would be a chance to disagree about
        // the frame a released gesture measured from.
        let parentFrames = try ViewportSceneNodeParentFrames(document: input.document)
        if drawsBodyGizmo {
            let isGroup = bodyItems.count > 1
            let featureID = bodyItems.last?.featureID ?? bodyItems[0].featureID
            let bodyMembers = try bodyItems.map { item in
                let frames = try sceneNodeCommitFrames(item: item, parentFrames: parentFrames, input: input)
                let placement = frames.map { ViewportBodyPlacementBaseline(featureID: item.featureID,
                    sceneNodeID: $0.sceneNodeID, baseLocalTransform: $0.baseLocalTransform,
                    parentWorldTransform: $0.parentWorldTransform) }
                return ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember(
                    occurrenceID: item.id,
                    featureID: item.featureID,
                    sceneNodeID: item.sceneNodeID,
                    modelTransform: item.modelTransform,
                    edit: try bodyTransformPreviewBounds(item: item, input: input),
                    placement: placement
                )
            }
            let edit: ViewportObjectEditState
            if isGroup {
                let edits = bodyMembers.map(\.edit)
                guard let first = edits.first else { return }
                edit = ViewportObjectEditState(
                    xMin: edits.map(\.xMin).min() ?? first.xMin,
                    xMax: edits.map(\.xMax).max() ?? first.xMax,
                    yMin: edits.map(\.yMin).min() ?? first.yMin,
                    yMax: edits.map(\.yMax).max() ?? first.yMax,
                    zMin: edits.map(\.zMin).min() ?? first.zMin,
                    zMax: edits.map(\.zMax).max() ?? first.zMax
                )
            } else {
                edit = bodyMembers[0].edit
            }
            let target = bodyItems.count == 1
                ? input.selection.selectedTargets.first(where: { $0.sceneNodeID == bodyItems[0].sceneNodeID && $0.component == .object })
                : nil
            let placement = bodyMembers.count == 1 ? bodyMembers[0].placement : nil
            try emitBodyTransform(
                featureID: featureID,
                selectionTarget: target,
                occurrenceID: bodyItems.count == 1 ? bodyItems[0].id : nil,
                modelTransform: bodyItems.count == 1 ? bodyItems[0].modelTransform : .identity,
                edit: edit,
                bodyMembers: bodyMembers,
                groupEdit: isGroup ? edit : nil,
                placement: placement,
                input: input,
                interactionRecords: &interactionRecords,
                checkpoint: checkpoint,
                worldLines: &worldLines,
                cameraLines: &cameraLines,
                cameraPaths: &cameraPaths,
                markers: &markers
            )
        }

        guard drawsSketchGizmo else { return }
        for item in sketchItems {
            // A sketch the common placement command cannot address draws
            // nothing, exactly as an unaddressable body item does.
            guard let frame = try sceneNodeCommitFrames(item: item, parentFrames: parentFrames, input: input),
                  let reference = input.document.productMetadata.sceneNodes[frame.sceneNodeID]?.reference else { continue }
            let rect = item.modelBounds
            let points = [Point3D(x: rect.minX, y: 0, z: rect.minY),
                          Point3D(x: rect.maxX, y: 0, z: rect.minY),
                          Point3D(x: rect.minX, y: 0, z: rect.maxY),
                          Point3D(x: rect.maxX, y: 0, z: rect.maxY)]
                .map { item.modelTransform.viewportTransformedPoint($0) }
            guard points.allSatisfy(isFinitePoint) else {
                throw RealityViewportSpatialBatch.invalid("Object bounds are not finite.")
            }
            let bounds = ViewportObjectEditState(
                xMin: points.map(\.x).min()!, xMax: points.map(\.x).max()!,
                yMin: points.map(\.y).min()!, yMax: points.map(\.y).max()!,
                zMin: points.map(\.z).min()!, zMax: points.map(\.z).max()!, preservesZeroExtents: true)
            let member = ViewportObjectTransformMember(occurrenceID: item.id, reference: reference,
                sceneNodeID: frame.sceneNodeID, baseLocalTransform: frame.baseLocalTransform,
                parentWorldTransform: frame.parentWorldTransform, bounds: bounds,
                placementResize: .placement(bounds: bounds, document: input.document))
            try emitBodyTransform(featureID: nil, selectionTarget: nil, occurrenceID: item.id,
                modelTransform: item.modelTransform, edit: bounds, bodyMembers: [], groupEdit: nil,
                placement: nil, objectMembers: [member], input: input, interactionRecords: &interactionRecords,
                checkpoint: checkpoint, worldLines: &worldLines, cameraLines: &cameraLines,
                cameraPaths: &cameraPaths, markers: &markers)
        }
    }
    static func emitBodyTransform(
        featureID: FeatureID?,
        selectionTarget: SelectionTarget?,
        occurrenceID: String?,
        modelTransform: Transform3D,
        edit: ViewportObjectEditState,
        bodyMembers: [ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember],
        groupEdit: ViewportObjectEditState?,
        placement: ViewportBodyPlacementBaseline?,
        objectMembers: [ViewportObjectTransformMember]? = nil,
        input: SurfaceTransformAffordanceSource.RawInput,
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        checkpoint: (Int, Int, Int) throws -> Void,
        worldLines: inout [SurfaceTransformAffordanceSource.WorldLine],
        cameraLines: inout [SurfaceTransformAffordanceSource.CameraLine],
        cameraPaths: inout [SurfaceTransformAffordanceSource.CameraPath],
        markers: inout [SurfaceTransformAffordanceSource.Marker]
    ) throws {
        let firstCameraLine = cameraLines.count
        let firstMarker = markers.count
        var corners = edit.worldBoxCorners
        if let member = objectMembers?.first,
           objectMembers?.count == 1, let resize = member.handleResize {
            let vertices: [ViewportBodyVertex] = [.frontBottomLeft, .frontBottomRight,
                .backBottomLeft, .backBottomRight, .frontTopLeft, .frontTopRight, .backTopLeft, .backTopRight]
            corners = try vertices.map { vertex in
                try resize.point(for: .vertexMove(vertex))
            }
        }
        guard corners.count == 8, corners.allSatisfy(isFinitePoint) else {
            throw RealityViewportSpatialBatch.invalid("Body transform bounds do not contain eight finite corners.")
        }
        func affordance(_ action: ViewportAffordanceAction) throws -> ViewportSpatialHandleIdentity {
            if let objectMembers {
                let prepared = ViewportSpatialPreparedInteractionTarget.objectTransform(
                    action: action, members: objectMembers, bounds: edit)
                if input.interactiveRoutes.contains(.bodyTransform) {
                    _ = try handleIndex(for: prepared, occurrenceID: occurrenceID,
                                        modelTransform: modelTransform, in: &interactionRecords)
                }
                return try prepared.spatialIdentity
            }
            guard let featureID else {
                throw RealityViewportSpatialBatch.invalid("A CAD affordance has no source feature.")
            }
            let target = ViewportAffordanceTarget(featureID: featureID, selectionTarget: selectionTarget, action: action)
            if input.interactiveRoutes.contains(.bodyTransform) {
                let prepared = ViewportSpatialPreparedInteractionTarget.affordance(
                    target: target,
                    members: bodyMembers,
                    groupEdit: groupEdit,
                    placement: placement
                )
                _ = try handleIndex(
                    for: prepared,
                    occurrenceID: occurrenceID,
                    modelTransform: modelTransform,
                    in: &interactionRecords
                )
            }
            return .affordance(target)
        }
        let edges: [(Int, Int)] = [
            (0, 1), (0, 2), (0, 4), (1, 3), (1, 5), (2, 3),
            (2, 6), (3, 7), (4, 5), (4, 6), (5, 7), (6, 7),
        ]
        for (start, end) in edges {
            if objectMembers != nil {
                try appendCameraLine(.init(route: .bodyTransform,
                    points: [corners[start], corners[end]].map {
                        .init(anchor: $0, toward: $0, usesFixedOffset: true)
                    }, color: selectionColor, family: .transform, identity: nil, state: .normal),
                    to: &cameraLines, checkpoint: checkpoint)
                continue
            }
            try appendWorldLine(
                .init(
                    route: .bodyTransform,
                    points: [corners[start], corners[end]],
                    closed: false,
                    color: selectionColor,
                    family: .transform,
                    identity: nil,
                    state: .normal
                ),
                to: &worldLines,
                checkpoint: checkpoint
            )
        }

        guard bodyMembers.allSatisfy({ $0.placement != nil }) else { return }
        let center = edit.worldPoint(edit.centerPoint)
        let maxSpan = max(
            Double(edit.xMax - edit.xMin),
            max(Double(edit.yMax - edit.yMin), Double(edit.zMax - edit.zMin))
        )
        guard maxSpan.isFinite, maxSpan > 0 else {
            throw RealityViewportSpatialBatch.invalid("Body transform bounds have no finite span.")
        }
        // A world length is still needed to name each axis direction to the
        // camera, but it no longer decides how long anything is drawn: every
        // extent below is a point length from `BodyTransformMetrics`.
        let axisLength = max(maxSpan * 0.32, input.ruler.majorTickMeters * 0.5)
        for axis in ViewportCoordinateAxis.allCases {
            let modelDirection: ViewportModelVector3D
            switch axis {
            case .x: modelDirection = edit.orientation.xAxis
            case .y: modelDirection = edit.orientation.yAxis
            case .z: modelDirection = edit.orientation.zAxis
            }
            let direction = normalized(worldVector(modelDirection)) ?? modelAxis(axis)
            // The two axis markers sit on the arrow this loop draws, so they
            // resolve the way the arrow does: along the projected axis, at the
            // point distance each one owns. Advancing them in scene space
            // instead would foreshorten them off the arrow, putting the
            // "arrow tip" marker mid-shaft on any axis tilted out of the camera
            // plane and collapsing the separation between the two markers.
            let tip = offset(center, direction: direction, distance: axisLength)
            let translateIdentity = try affordance(.translate(axis))
            try emitDirectedArrow(
                route: .bodyTransform,
                origin: center,
                direction: direction,
                length: axisLength,
                identity: translateIdentity,
                input: input,
                fixedLengthPoints: BodyTransformMetrics.axisLengthPoints,
                hitTolerancePoints: 7.0,
                occurrenceID: occurrenceID,
                checkpoint: checkpoint,
                cameraLines: &cameraLines
            )
            let endIdentity = translateIdentity
            try appendMarker(
                .init(
                    route: .bodyTransform,
                    anchor: center,
                    shape: .cone,
                    diameterPoints: 16,
                    color: axisColor(axis),
                    family: .transform,
                    identity: endIdentity,
                    state: state(for: endIdentity, input: input),
                    hitTolerancePoints: 10.0,
                    occurrenceID: occurrenceID,
                    offset: .directed(
                        toward: tip,
                        parallel: BodyTransformMetrics.axisLengthPoints,
                        perpendicular: 0
                    )
                ),
                to: &markers,
                checkpoint: checkpoint
            )
            let extent: CGFloat
            switch axis {
            case .x: extent = edit.xMax - edit.xMin
            case .y: extent = edit.yMax - edit.yMin
            case .z: extent = edit.zMax - edit.zMin
            }
            guard extent > 0 else { continue }
            let centerIdentity = try affordance(.centerScale(axis))
            try appendMarker(
                .init(
                    route: .bodyTransform,
                    anchor: center,
                    shape: .sphere,
                    diameterPoints: 9,
                    color: axisColor(axis),
                    family: .transform,
                    identity: centerIdentity,
                    state: state(for: centerIdentity, input: input),
                    hitTolerancePoints: 10.0,
                    occurrenceID: occurrenceID,
                    offset: .directed(
                        toward: tip,
                        parallel: BodyTransformMetrics.centerScalePoints,
                        perpendicular: 0
                    )
                ),
                to: &markers,
                checkpoint: checkpoint
            )
        }

        if let member = objectMembers?.first,
           objectMembers?.count == 1, let resize = member.handleResize {
            for action in resize.handleActions {
                let identity = try affordance(action)
                let anchor = try resize.point(for: action)
                let color: SIMD4<Float>
                if case .faceMove = action { color = SIMD4(0.24, 0.24, 0.24, 1) }
                else { color = SIMD4(0.60, 0.63, 0.65, 1) }
                try appendMarker(.init(route: .bodyTransform, anchor: anchor, shape: .box,
                                       diameterPoints: 10, color: color, family: .transform,
                                       identity: identity, state: state(for: identity, input: input),
                                       hitTolerancePoints: 8, occurrenceID: occurrenceID),
                                 to: &markers, checkpoint: checkpoint)
            }
        }

        try appendMarker(
            .init(
                route: .bodyTransform,
                anchor: center,
                shape: .box,
                diameterPoints: 10,
                color: selectionColor,
                family: .transform,
                identity: nil,
                state: .normal
            ),
            to: &markers,
            checkpoint: checkpoint
        )
        let orientedAxes = [
            normalized(worldVector(edit.orientation.xAxis)) ?? Vector3D.unitX,
            normalized(worldVector(edit.orientation.yAxis)) ?? Vector3D.unitY,
            normalized(worldVector(edit.orientation.zAxis)) ?? Vector3D.unitZ,
        ]
        let rotationPlanes: [(ViewportCoordinateAxis, Vector3D, Vector3D)] = [
            (.x, orientedAxes[1], orientedAxes[2]),
            (.y, orientedAxes[2], orientedAxes[0]),
            (.z, orientedAxes[0], orientedAxes[1]),
        ]
        for (axis, planeStart, planeEnd) in rotationPlanes {
            let identity = try affordance(.rotate(axis))
            // Each sample is placed by its own world direction, so the ring
            // keeps a fixed screen radius and still foreshortens into the plane
            // it rotates about. A camera-plane offset would normalize every
            // projected direction and draw three identical circles.
            let arc = rotationArcDirections(
                planeStart: planeStart,
                planeEnd: planeEnd,
                segmentCount: BodyTransformMetrics.rotationSegmentCount
            ).map {
                SurfaceTransformAffordanceSource.DirectedPoint(
                    anchor: center,
                    along: $0,
                    lengthPoints: BodyTransformMetrics.rotationRadiusPoints
                )
            }
            try appendCameraLine(
                .init(
                    route: .bodyTransform,
                    points: arc,
                    color: axisColor(axis),
                    family: .transform,
                    identity: identity,
                    state: state(for: identity, input: input),
                    hitTolerancePoints: 8.0,
                    occurrenceID: occurrenceID
                ),
                to: &cameraLines,
                checkpoint: checkpoint
            )
        }
        if let occurrence = objectMembers?.first?.occurrenceID {
            for index in firstCameraLine..<cameraLines.count { cameraLines[index].objectPreviewOccurrenceID = occurrence }
            for index in firstMarker..<markers.count { markers[index].objectPreviewOccurrenceID = occurrence }
        }
    }

    /// World-aligned handle bounds follow this occurrence's preview mutation.
    static func bodyTransformPreviewBounds(
        item: ViewportSceneItem, input: SurfaceTransformAffordanceSource.RawInput
    ) throws -> ViewportObjectEditState {
        let base = ViewportObjectEditState(item: item)
        guard let mutation = input.bodyPreviewTransforms[item.id] else { return base }
        let points = try base.worldBoxCorners.map { try ViewportWorldTransformAlgebra.transformedPoint($0, by: mutation) }
        return ViewportObjectEditState(
            xMin: CGFloat(points.map(\.x).min()!), xMax: CGFloat(points.map(\.x).max()!),
            yMin: CGFloat(points.map(\.y).min()!), yMax: CGFloat(points.map(\.y).max()!),
            zMin: CGFloat(points.map(\.z).min()!), zMax: CGFloat(points.map(\.z).max()!))
    }

    /// Addressable, unlocked node frames shared by every transform gizmo.
    /// Instance-owned placements need their own command and expose no handles here.
    static func sceneNodeCommitFrames(
        item: ViewportSceneItem,
        parentFrames: ViewportSceneNodeParentFrames,
        input: SurfaceTransformAffordanceSource.RawInput
    ) throws -> (
        sceneNodeID: SceneNodeID,
        baseLocalTransform: Transform3D,
        parentWorldTransform: Transform3D
    )? {
        guard let sceneNodeID = item.sceneNodeID, item.componentInstanceID == nil else { return nil }
        guard let node = input.document.productMetadata.sceneNodes[sceneNodeID], !node.isLocked else { return nil }
        guard let parentWorldTransform = try parentFrames.parentWorldTransform(of: sceneNodeID) else {
            return nil
        }
        return (sceneNodeID, node.localTransform, parentWorldTransform)
    }

    static func emitProfileAffordances(
        input: SurfaceTransformAffordanceSource.RawInput,
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        checkpoint: (Int, Int, Int) throws -> Void,
        cameraLines: inout [SurfaceTransformAffordanceSource.CameraLine],
        cameraPaths: inout [SurfaceTransformAffordanceSource.CameraPath],
        markers: inout [SurfaceTransformAffordanceSource.Marker]
    ) throws {
        for target in input.selection.selectedTargets {
            switch target.component {
            case .vertex(let componentID):
                guard input.interactiveRoutes.contains(.profileCorner) else { continue }
                // A corner handle exists only where the document authority can
                // name the selected vertex as a box corner.
                guard let vertex = viewportBodyVertex(
                    for: componentID,
                    target: target,
                    document: input.document,
                    objectRegistry: input.objectRegistry
                ) else { continue }
                guard let item = sceneItem(for: target, input: input),
                      case .body = item.kind else { continue }
                let edit = input.editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
                try emitProfileHandle(
                    route: .profileCorner,
                    action: .profileCornerMove(target, vertex),
                    target: target,
                    item: item,
                    edit: edit,
                    anchor: edit.worldPoint(edit.position(for: vertex)),
                    offsetPoints: nil,
                    path: squarePath(radius: ProfileAffordanceMetrics.markRadiusPoints),
                    input: input,
                    interactionRecords: &interactionRecords,
                    checkpoint: checkpoint,
                    cameraLines: &cameraLines,
                    cameraPaths: &cameraPaths,
                    markers: &markers
                )
            case .face(let componentID):
                guard input.interactiveRoutes.contains(.profileFace) else { continue }
                guard let face = viewportBodyFace(
                    for: componentID,
                    target: target,
                    document: input.document,
                    objectRegistry: input.objectRegistry
                ) else { continue }
                guard ViewportProfileFaceDragMapping.supports(face) else { continue }
                guard let item = sceneItem(for: target, input: input),
                      case .body = item.kind else { continue }
                let edit = input.editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
                let frame = componentID.generatedTopologySubshapeID == nil ? nil
                    : try ViewportProfileFaceFrame.resolve(item: item, face: face,
                        componentID: componentID, document: input.document)
                try emitProfileHandle(
                    route: .profileFace,
                    action: .profileFaceMove(target, face),
                    target: target,
                    item: item,
                    edit: edit,
                    anchor: frame?.anchor ?? edit.worldPoint(edit.position(for: face)),
                    profileFaceFrame: frame,
                    offsetPoints: nil,
                    path: circlePath(radius: ProfileAffordanceMetrics.markRadiusPoints),
                    input: input,
                    interactionRecords: &interactionRecords,
                    checkpoint: checkpoint,
                    cameraLines: &cameraLines,
                    cameraPaths: &cameraPaths,
                    markers: &markers
                )
            case .edge(let componentID):
                let wantsFillet = input.interactiveRoutes.contains(.edgeFillet)
                let wantsChamfer = input.interactiveRoutes.contains(.profileEdgeChamfer)
                guard wantsFillet || wantsChamfer else { continue }
                // The legacy interaction route omits generated or otherwise
                // non-corner edges that cannot carry an edge treatment.
                // Preserve that disabled-result semantics while resolving
                // generated corner edges through the same document authority
                // when possible.
                guard let edge = viewportBodyEdge(
                    for: componentID,
                    target: target,
                    document: input.document,
                    objectRegistry: input.objectRegistry
                ) else { continue }
                guard
                      let item = sceneItem(for: target, input: input),
                      case .body(let component) = item.kind,
                      let topology = component.topology,
                      let sourceEdge = topology.edges.first(where: { $0.componentID == componentID }) else {
                    throw RealityViewportSpatialBatch.invalid(
                        "Edge treatment selection is not backed by body topology."
                    )
                }
                let start = item.modelTransform.viewportTransformedPoint(sourceEdge.start)
                let end = item.modelTransform.viewportTransformedPoint(sourceEdge.end)
                let anchor = midpoint(start, end)
                let edit = input.editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
                if wantsFillet {
                    try emitProfileHandle(
                        route: .edgeFillet,
                        action: .profileEdgeFillet(target, edge),
                        target: target,
                        item: item,
                        edit: edit,
                        anchor: anchor,
                        offsetPoints: ProfileAffordanceMetrics.filletOffsetPoints,
                        path: diamondPath(radius: ProfileAffordanceMetrics.markRadiusPoints),
                        input: input,
                        interactionRecords: &interactionRecords,
                        checkpoint: checkpoint,
                        cameraLines: &cameraLines,
                        cameraPaths: &cameraPaths,
                        markers: &markers
                    )
                }
                if wantsChamfer {
                    try emitProfileHandle(
                        route: .profileEdgeChamfer,
                        action: .profileEdgeChamfer(target, edge),
                        target: target,
                        item: item,
                        edit: edit,
                        anchor: anchor,
                        offsetPoints: ProfileAffordanceMetrics.chamferOffsetPoints,
                        path: trianglePath(radius: ProfileAffordanceMetrics.markRadiusPoints),
                        input: input,
                        interactionRecords: &interactionRecords,
                        checkpoint: checkpoint,
                        cameraLines: &cameraLines,
                        cameraPaths: &cameraPaths,
                        markers: &markers
                    )
                }
            case .object, .sketchEntity, .region, .constructionPlane:
                continue
            }
        }
    }

    /// Registers one profile handle and draws the mark that reaches it.
    ///
    /// A prepared record is reachable only through the collision geometry its
    /// drawing builds, so the record and the mark are emitted together. A nil
    /// `offsetPoints` draws the mark on the anchor itself; a non-nil one moves
    /// it along the ray toward the body centre and draws the leader line that
    /// ties it back.
    private static func emitProfileHandle(
        route: SurfaceTransformAffordanceRoute,
        action: ViewportAffordanceAction,
        target: SelectionTarget,
        item: ViewportSceneItem,
        edit: ViewportObjectEditState,
        anchor: Point3D,
        profileFaceFrame: ViewportProfileFaceFrame? = nil,
        offsetPoints: CGFloat?,
        path: Path,
        input: SurfaceTransformAffordanceSource.RawInput,
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        checkpoint: (Int, Int, Int) throws -> Void,
        cameraLines: inout [SurfaceTransformAffordanceSource.CameraLine],
        cameraPaths: inout [SurfaceTransformAffordanceSource.CameraPath],
        markers: inout [SurfaceTransformAffordanceSource.Marker]
    ) throws {
        var affordanceTarget = ViewportAffordanceTarget(
            featureID: item.featureID,
            selectionTarget: target,
            action: action
        )
        affordanceTarget.profileFaceFrame = profileFaceFrame
        let member = ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember(
            occurrenceID: item.id,
            featureID: item.featureID,
            sceneNodeID: item.sceneNodeID,
            modelTransform: item.modelTransform,
            edit: edit
        )
        let prepared = ViewportSpatialPreparedInteractionTarget.affordance(
            target: affordanceTarget,
            members: [member],
            groupEdit: nil,
            placement: nil
        )
        _ = try handleIndex(
            for: prepared,
            occurrenceID: item.id,
            modelTransform: item.modelTransform,
            in: &interactionRecords
        )
        let identity = ViewportSpatialHandleIdentity.affordance(affordanceTarget)
        let state = state(for: identity, input: input)
        let placement: SurfaceTransformAffordanceSource.DirectedPoint
        if let offsetPoints {
            let toward = edit.worldPoint(edit.centerPoint)
            placement = .init(
                anchor: anchor,
                toward: toward == anchor ? anchor + .unitY : toward,
                parallel: offsetPoints,
                perpendicular: 0
            )
            try appendCameraLine(
                .init(
                    route: route,
                    points: [
                        .init(anchor: anchor, toward: anchor, usesFixedOffset: true),
                        placement,
                    ],
                    color: editColor,
                    family: .transform,
                    identity: nil,
                    state: state,
                    hitTolerancePoints: nil
                ),
                to: &cameraLines,
                checkpoint: checkpoint
            )
        } else {
            placement = .init(anchor: anchor, toward: anchor, usesFixedOffset: true)
        }
        try appendCameraPath(
            .init(
                route: route,
                path: path,
                placement: placement,
                color: editColor,
                family: .transform,
                identity: identity,
                state: state,
                hitTolerancePoints: Float(ProfileAffordanceMetrics.hitTolerancePoints),
                occurrenceID: item.id
            ),
            to: &cameraPaths,
            checkpoint: checkpoint
        )
        if activeValue(for: identity, input: input) != nil {
            try appendMarker(
                .init(
                    route: route,
                    anchor: anchor,
                    shape: .sphere,
                    diameterPoints: Float(ProfileAffordanceMetrics.markRadiusPoints),
                    color: editColor,
                    family: .transform,
                    identity: nil,
                    state: .active
                ),
                to: &markers,
                checkpoint: checkpoint
            )
        }
    }

    static func viewportBodyEdge(for componentID: SelectionComponentID) -> ViewportBodyEdge? {
        switch componentID {
        case .bodyEdgeLeftBottom: .leftBottom
        case .bodyEdgeRightBottom: .rightBottom
        case .bodyEdgeRightTop: .rightTop
        case .bodyEdgeLeftTop: .leftTop
        default: nil
        }
    }

    static func viewportBodyEdge(
        for componentID: SelectionComponentID,
        target: SelectionTarget,
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) -> ViewportBodyEdge? {
        if let direct = viewportBodyEdge(for: componentID) {
            return direct
        }
        guard componentID.generatedTopologySubshapeID != nil else { return nil }
        do {
            let resolved = try GeneratedTopologySelectionResolver().cornerEdge(
                for: target,
                in: document,
                objectRegistry: objectRegistry,
                operationName: "Viewport generated topology selection"
            )
            switch resolved {
            case .leftBottom: return .leftBottom
            case .rightBottom: return .rightBottom
            case .rightTop: return .rightTop
            case .leftTop: return .leftTop
            }
        } catch {
            return nil
        }
    }

    static func viewportBodyFace(for componentID: SelectionComponentID) -> ViewportBodyFace? {
        switch componentID {
        case .bodyFaceFront: .front
        case .bodyFaceBack: .back
        case .bodyFaceTop: .top
        case .bodyFaceBottom: .bottom
        case .bodyFaceLeft: .left
        case .bodyFaceRight: .right
        case .bodyFaceSide: .side
        default: nil
        }
    }

    static func viewportBodyFace(
        for componentID: SelectionComponentID,
        target: SelectionTarget,
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) -> ViewportBodyFace? {
        if let direct = viewportBodyFace(for: componentID) {
            return direct
        }
        guard componentID.generatedTopologySubshapeID != nil else { return nil }
        do {
            let resolved = try GeneratedTopologySelectionResolver().bodyFace(
                for: target,
                in: document,
                objectRegistry: objectRegistry,
                operationName: "Viewport generated topology selection"
            )
            switch resolved {
            case .front: return .front
            case .back: return .back
            case .top: return .top
            case .bottom: return .bottom
            case .left: return .left
            case .right: return .right
            case .side: return .side
            }
        } catch {
            return nil
        }
    }

    static func viewportBodyVertex(
        for componentID: SelectionComponentID,
        target: SelectionTarget,
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) -> ViewportBodyVertex? {
        guard componentID.generatedTopologySubshapeID != nil else { return nil }
        do {
            let resolved = try GeneratedTopologySelectionResolver().cornerVertex(
                for: target,
                in: document,
                objectRegistry: objectRegistry,
                operationName: "Viewport generated topology selection"
            )
            switch resolved {
            case .frontBottomLeft: return .frontBottomLeft
            case .frontBottomRight: return .frontBottomRight
            case .frontTopRight: return .frontTopRight
            case .frontTopLeft: return .frontTopLeft
            case .backBottomLeft: return .backBottomLeft
            case .backBottomRight: return .backBottomRight
            case .backTopRight: return .backTopRight
            case .backTopLeft: return .backTopLeft
            }
        } catch {
            return nil
        }
    }

    static func sceneItem(
        for target: SelectionTarget,
        input: SurfaceTransformAffordanceSource.RawInput
    ) -> ViewportSceneItem? {
        if let item = input.scene.items.first(where: { $0.sceneNodeID == target.sceneNodeID }) {
            return item
        }
        guard let featureID = input.document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID else {
            return nil
        }
        return input.scene.items.first { $0.featureID == featureID }
    }

    static func polySplinePatchDescriptors(
        document: DesignDocument,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> [FeatureID: [ViewportPolySplinePatchDescriptor]] {
        var result: [FeatureID: [ViewportPolySplinePatchDescriptor]] = [:]
        for featureID in document.cadDocument.designGraph.order {
            try Task.checkCancellation()
            try checkpoint(0, 0, 1)
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  case let .polySpline(polySpline) = feature.operation else { continue }
            let analysis = PolySplineMeshAnalyzer().analyze(
                mesh: polySpline.sourceMesh,
                options: polySpline.options,
                tolerance: document.modelingSettings.tolerance
            )
            guard analysis.result.isSupported else { continue }
            var patches: [ViewportPolySplinePatchDescriptor] = []
            for patch in analysis.supportedPatches {
                try checkpoint(0, patch.boundaryVertexIndices.count, 1)
                patches.append(
                    .init(
                        candidateID: patch.candidateID,
                        cornerSourceVertexIndices: patch.boundaryVertexIndices
                    )
                )
            }
            result[featureID] = patches
        }
        return result
    }
}
