import AppKit
import CoreGraphics
import Foundation
import RealityKit
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

/// The replacement rectangle answer, differenced against the native hit it
/// replaces, on a real mounted frame.
///
/// Every assertion here reads one mounted `RealityView`: the region visibility
/// raster answers a device pixel, the native collision query answers the same
/// point, and the two must name the same drawn triangle at the same depth. A
/// stub frame can show the raster is self-consistent; only a mounted frame can
/// show it agrees with what RealityKit actually drew, which is what the two
/// retired sampling resolvers could not do.
///
/// The fixture is authored in layout points and mapped to world positions
/// through the layout's own projection, so each body's projected rectangle is
/// the rectangle it was written as under both cameras. That is what lets the
/// conditions be stated as geometry instead of tuned constants: a sliver 2.5
/// layout points wide is five device pixels at the mounted display scale of
/// two, a body inset four points inside its occluder is fully hidden, and the
/// notch of an L is backdrop.
///
/// Depth agreement stands in for the frame's private interpolation. The raster
/// interpolates at the pixel centre, the native query intersects the same ray,
/// and the bodies sit at six distinct depths away from the camera's calibration
/// sample depth, so a projection that agreed only at that one plane would
/// separate here.
@Suite(.serialized)
@MainActor
struct RealityViewportRegionDifferentialTests {

    // MARK: - Fixture vocabulary

    enum Role: String, CaseIterable {
        case backdrop
        case occluder
        case hidden
        case slab
        case nonconvex
        case backface
        /// Crosses the mounted camera's near plane. It has no entry in
        /// `bodies` because its shape is measured from the camera it mounts
        /// on and differs between the two cameras.
        case straddle
    }

    enum Tessellation: String {
        case baseline
        case alternate
    }

    struct FixtureFailure: Error, CustomStringConvertible {
        var description: String
    }

    /// A corner in layout points.
    struct Corner: Hashable {
        var x: Double
        var y: Double
    }

    /// An axis-aligned rectangle in layout points.
    struct Cell {
        var minimumX: Double
        var minimumY: Double
        var maximumX: Double
        var maximumY: Double

        var topLeft: Corner { Corner(x: minimumX, y: minimumY) }
        var bottomLeft: Corner { Corner(x: minimumX, y: maximumY) }
        var bottomRight: Corner { Corner(x: maximumX, y: maximumY) }
        var topRight: Corner { Corner(x: maximumX, y: minimumY) }

        func subdivided() -> [Cell] {
            let midX = (minimumX + maximumX) / 2
            let midY = (minimumY + maximumY) / 2
            return [
                Cell(minimumX: minimumX, minimumY: minimumY, maximumX: midX, maximumY: midY),
                Cell(minimumX: midX, minimumY: minimumY, maximumX: maximumX, maximumY: midY),
                Cell(minimumX: minimumX, minimumY: midY, maximumX: midX, maximumY: maximumY),
                Cell(minimumX: midX, minimumY: midY, maximumX: maximumX, maximumY: maximumY)
            ]
        }

        /// The face loops this cell contributes, wound so that the loop is
        /// counter-clockwise seen from the camera when `isBackFacing` is false.
        ///
        /// Under `.axisFront(.z)` the screen y axis runs against world y, so the
        /// layout order top-left, bottom-left, bottom-right, top-right is
        /// counter-clockwise in world space and therefore front-facing.
        func loops(tessellation: Tessellation, isBackFacing: Bool) -> [[Corner]] {
            let loops: [[Corner]]
            switch tessellation {
            case .baseline:
                loops = [[topLeft, bottomLeft, bottomRight, topRight]]
            case .alternate:
                loops = [
                    [bottomLeft, bottomRight, topRight],
                    [bottomLeft, topRight, topLeft]
                ]
            }
            guard isBackFacing else { return loops }
            return loops.map { Array($0.reversed()) }
        }
    }

    struct Body {
        var role: Role
        /// World z. The axis-front camera sits on +z, so a larger z is nearer.
        var elevation: Double
        var isBackFacing: Bool
        var cells: [Cell]
        var subdividesWhenRetessellated: Bool
    }

    /// The affine, axis-aligned map from world `(x, y)` at one world `z` to
    /// layout points. It is affine under both cameras because every point on
    /// that plane shares one camera depth, so the perspective divide is
    /// constant across it.
    struct PlaneMap {
        let originX: Double
        let originY: Double
        let unitX: Double
        let unitY: Double

        init?(layout: ViewportLayout, elevation: Double) {
            guard let origin = layout.projectedPoint(Point3D(x: 0, y: 0, z: elevation)),
                  let alongX = layout.projectedPoint(Point3D(x: 1, y: 0, z: elevation)),
                  let alongY = layout.projectedPoint(Point3D(x: 0, y: 1, z: elevation)) else {
                return nil
            }
            originX = Double(origin.point.x)
            originY = Double(origin.point.y)
            unitX = Double(alongX.point.x) - originX
            unitY = Double(alongY.point.y) - originY
            guard unitX.isFinite, unitY.isFinite, unitX != 0, unitY != 0 else { return nil }
        }

        func world(_ corner: Corner, elevation: Double) -> GeometryPoint3D {
            GeometryPoint3D(
                x: (corner.x - originX) / unitX,
                y: (corner.y - originY) / unitY,
                z: elevation
            )
        }
    }

    struct MountedFrame {
        let viewport: RealityViewport
        let window: NSWindow
    }

    struct Sweep {
        var pixelCount = 0
        var drawn = 0
        var agreements = 0
        var boundarySkips = 0
        /// Why each excused pixel was excused, so a run reports the shared
        /// side it sat on rather than only how many it excused.
        var skips: [String] = []
        var unprojectable = 0
        var failures: [String] = []
        var maximumDepthDeviation = 0.0
        var maximumSlabRun = 0
        var counts: [SceneOccurrenceID: Int] = [:]
        var occurrences: Set<SceneOccurrenceID> = []
        var triangles: [MeshSourcePresentationTriangle] = []
        var regionOccurrences: Set<SceneOccurrenceID> = []
        var regionTriangles: [MeshSourcePresentationTriangle] = []
        var notchOccurrence: SceneOccurrenceID?
        /// The device pixels the straddle body answered for. They stay
        /// inverted in the scenes that hold no straddle body.
        var straddleMinimumColumn = Int.max
        var straddleMaximumColumn = Int.min
        var straddleMinimumRow = Int.max
        var straddleMaximumRow = Int.min
    }

    /// What the mounted camera reports about its own near plane.
    ///
    /// `RealityViewport.applyCamera` derives the camera from the layout and,
    /// when the spatial batch carries a grid, from the grid's canvas plane.
    /// The batch these fixtures mount carries none, so the camera is a
    /// function of the layout alone. That is what lets a body be placed
    /// against a near plane measured on an earlier frame of the same layout,
    /// and `straddleMeasurement` measures again afterwards rather than
    /// leaving the property assumed.
    struct CameraProbe: Equatable {
        /// The camera's own near depth, as `cameraDepthInterval` reports it.
        var near: Double
        /// The depth of world z = 0. Under the axis-front basis depth is the
        /// elevation below the eye, so this is the eye's own elevation.
        var eyeElevation: Double
        /// The world z the near plane sits at.
        var nearElevation: Double { eyeElevation - near }

        func agrees(with other: CameraProbe, tolerance: Double) -> Bool {
            abs(near - other.near) <= tolerance
                && abs(eyeElevation - other.eyeElevation) <= tolerance
        }
    }

    struct StraddleMeasurement {
        /// The camera read before the straddle body entered the scene, which
        /// is the camera the body's own corners were derived from.
        var probe: CameraProbe
        /// The same camera read on the frame that draws the body.
        var mountedProbe: CameraProbe
        var sweep: Sweep
        /// The depths the frame reports for the body's own corners. They
        /// bracket the near plane whenever the body really crosses it.
        var minimumCornerDepth: Double
        var maximumCornerDepth: Double
    }

    // MARK: - Fixture constants

    static let viewportSize = CGSize(width: 512, height: 384)
    static let displayScale: CGFloat = 2
    /// The rectangle every query is asked about, in layout points. At the
    /// mounted display scale it is 96 by 80 device pixels.
    static let rectangle = CGRect(x: 200, y: 160, width: 48, height: 40)
    /// A point inside the missing quadrant of the L, where the backdrop shows.
    static let notchProbe = CGPoint(x: 243.5, y: 167)
    /// Layout points. A fifth of a device pixel at the mounted display scale.
    static let boundaryTolerance = 0.1
    /// A pixel is excused only when both queries name triangles of one
    /// occurrence that share a side and the pixel centre lies on that side's
    /// projection, so this ceiling bounds how often the two rasterisers may
    /// break such a tie differently rather than how often they may disagree
    /// at all. The ten mounted variants excuse at most three of 7,680 pixels
    /// and each run prints the side every excused pixel sat on. Measured:
    /// an interior tessellation diagonal in every excused pixel but one, and
    /// in the dense tessellation one side carrying a boundary identity that
    /// two faces of that occurrence both cover. This ceiling leaves an order
    /// of magnitude over that peak and still rejects a systematic
    /// disagreement.
    static let maximumBoundarySkipFraction = 0.005
    /// The native query reports depth through a `Float` camera conversion,
    /// while the raster interpolates in `Double`, so the two agree to a few
    /// units in the last place of `Float` at the fixture's depth magnitude.
    /// Every fixture depth is below two, where that unit is 1.2e-7. What a
    /// variant then measures is that agreement in the hit's screen position
    /// multiplied by the depth its projection carries per device pixel, so
    /// the peak belongs to the steepest surface in screen space rather than
    /// to any one rasterisation rule. The variants whose surfaces face the
    /// camera stay near the conversion unit itself; the perspective straddle
    /// body runs to the eye, where that gradient grows without bound, and it
    /// consumes most of this allowance. Moving its front edge away from the
    /// horizon lowers the gradient, so a variant that needs more room adjusts
    /// the fixture and not this bound. A wider bound would accept a wrong
    /// interpolation rule, which moves depth by a thousand times this.
    static let depthTolerance = 1.0e-6
    /// The agreement the camera probe demands of a measured depth relative to
    /// its own magnitude. Depth is reported through a `Float` conversion, so
    /// an absolute bound alone would reject a correct reading of a large one.
    static let depthRelativeTolerance = 1.0e-6
    /// The agreement demanded between the camera measured before the straddle
    /// body enters the scene and the camera measured after. Both are the same
    /// derivation from the same layout, so this rejects any scene dependence.
    static let cameraProbeTolerance = 1.0e-9
    /// Points whose depth the axis-front basis fixes at the eye's elevation
    /// less their own. Measuring them proves depth is that affine function of
    /// world z before a body is placed relative to the near plane.
    static let depthLinearitySamples: [GeometryPoint3D] = [
        GeometryPoint3D(x: 0, y: 0, z: 0.25),
        GeometryPoint3D(x: 0, y: 0, z: -0.25),
        GeometryPoint3D(x: 0.25, y: 0, z: 0),
        GeometryPoint3D(x: 0, y: 0.25, z: 0)
    ]
    /// The orthographic straddle body's footprint in layout points. It holds
    /// twenty points of surface on each side of the near plane crossing.
    static let straddleCell = Cell(
        minimumX: 204, minimumY: 162, maximumX: 244, maximumY: 182
    )
    /// The layout x where the orthographic straddle body meets the near
    /// plane. It is a device-pixel boundary, so no pixel centre lands on the
    /// crossing itself and no fragment is a rounding away from either side.
    static let straddleCrossingX = 224.0
    /// World units of elevation per layout point of the orthographic straddle
    /// body's tilt. Across the twenty points on either side of the crossing it
    /// carries the surface four tenths of a world unit past the near plane,
    /// which is four hundred thousand times the depth agreement tolerance.
    static let straddleSlope = 0.02
    /// The layout row the perspective straddle body's front edge sits on, and
    /// the layout x of that edge's two corners. The edge lies at world z = 0,
    /// and the corners are far enough apart that the wedge the body projects
    /// to covers the whole rectangle from this row upwards.
    static let straddleFrontEdgeY = 180.0
    static let straddleFrontLeftX = 196.0
    static let straddleFrontRightX = 260.0
    /// How far behind the eye the perspective straddle body's back edge sits,
    /// in world units. That camera's near plane is a millionth of a unit in
    /// front of the eye, so only reaching behind the eye crosses it.
    static let straddleBehindEyeMargin = 0.25
    /// Bisection steps used to find where a triangle edge leaves the mounted
    /// projection. Each step halves a world-space interval, so this resolves a
    /// unit-length edge far below the precision the projection itself carries.
    static let projectionBisectionSteps = 60
    static let revision: UInt64 = 1

    static let bodies: [Body] = [
        Body(role: .backdrop, elevation: -0.40, isBackFacing: false,
             cells: [Cell(minimumX: 196, minimumY: 156, maximumX: 252, maximumY: 204)],
             subdividesWhenRetessellated: true),
        Body(role: .occluder, elevation: 0.20, isBackFacing: false,
             cells: [Cell(minimumX: 203, minimumY: 163, maximumX: 221, maximumY: 177)],
             subdividesWhenRetessellated: false),
        Body(role: .hidden, elevation: -0.20, isBackFacing: false,
             cells: [Cell(minimumX: 207, minimumY: 167, maximumX: 217, maximumY: 173)],
             subdividesWhenRetessellated: false),
        Body(role: .slab, elevation: 0.30, isBackFacing: false,
             cells: [Cell(minimumX: 226, minimumY: 162, maximumX: 228.5, maximumY: 180)],
             subdividesWhenRetessellated: false),
        Body(role: .nonconvex, elevation: 0.10, isBackFacing: false,
             cells: [
                Cell(minimumX: 233, minimumY: 162, maximumX: 241, maximumY: 172),
                Cell(minimumX: 233, minimumY: 172, maximumX: 241, maximumY: 178),
                Cell(minimumX: 241, minimumY: 172, maximumX: 246, maximumY: 178)
             ],
             subdividesWhenRetessellated: false),
        Body(role: .backface, elevation: 0.05, isBackFacing: true,
             cells: [Cell(minimumX: 203, minimumY: 185, maximumX: 225, maximumY: 196)],
             subdividesWhenRetessellated: false)
    ]

    /// Cuts at world z = 0.15 and retains the half-space below it, which
    /// removes the occluder and the slab and exposes the fully hidden body.
    static let sectionPlane = SectionAnalysisResult.Plane(
        sourceKind: .sketchPlane,
        sourceID: nil,
        sourceName: nil,
        origin: .init(x: 0, y: 0, z: 0.15),
        normal: .init(x: 0, y: 0, z: -1),
        u: .init(x: 0, y: 1, z: 0),
        v: .init(x: 1, y: 0, z: 0)
    )

    static func occurrenceID(for role: Role) -> SceneOccurrenceID {
        SceneOccurrenceID(rawValue: "occurrence.region-differential.\(role.rawValue)")
    }

    static func body(for role: Role) throws -> Body {
        guard let body = bodies.first(where: { $0.role == role }) else {
            throw FixtureFailure(
                description: "The fixture holds no \(role.rawValue) body."
            )
        }
        return body
    }

    static func layout(perspective: Bool) -> ViewportLayout {
        ViewportLayout(
            modelBounds: CGRect(x: 0, y: -0.5, width: 1, height: 1),
            size: viewportSize,
            camera: .init(
                zoom: 0.6,
                projection: perspective ? .standardPerspective : .parallel
            ),
            basis: .axisFront(.z),
            verticalBounds: 0...1
        )
    }

    // MARK: - Fixture construction

    private func source(
        for body: Body, layout: ViewportLayout, tessellation: Tessellation
    ) throws -> MeshSource {
        guard let map = PlaneMap(layout: layout, elevation: body.elevation) else {
            throw FixtureFailure(
                description: "The layout does not project the \(body.role.rawValue) plane."
            )
        }
        let cells: [Cell]
        if tessellation == .alternate, body.subdividesWhenRetessellated {
            cells = body.cells.flatMap { $0.subdivided() }
        } else {
            cells = body.cells
        }
        var builder = MeshSourceBuilder(
            identity: GeometrySourceID(
                rawValue: "mesh.region-differential.\(body.role.rawValue).\(tessellation.rawValue)"
            )
        )
        try builder.reserveCapacity(
            vertexCount: cells.count * 4,
            faceCount: cells.count * 2,
            cornerCount: cells.count * 8
        )
        var vertexByCorner: [Corner: MeshVertexID] = [:]
        for cell in cells {
            for loop in cell.loops(
                tessellation: tessellation, isBackFacing: body.isBackFacing
            ) {
                var vertexIDs: [MeshVertexID] = []
                vertexIDs.reserveCapacity(loop.count)
                for corner in loop {
                    if let existing = vertexByCorner[corner] {
                        vertexIDs.append(existing)
                        continue
                    }
                    let id = try builder.addVertex(
                        map.world(corner, elevation: body.elevation)
                    )
                    vertexByCorner[corner] = id
                    vertexIDs.append(id)
                }
                _ = try builder.addFace(vertexIDs: vertexIDs)
            }
        }
        return try builder.build()
    }

    private func item(
        for role: Role, source: MeshSource
    ) throws -> UniversalViewportSceneItem {
        UniversalViewportSceneItem(
            id: Self.occurrenceID(for: role),
            definitionID: ObjectDefinitionID(
                rawValue: "definition.region-differential.\(role.rawValue)"
            ),
            displayName: role.rawValue,
            representationID: GeometryRepresentationID(
                rawValue: "representation.region-differential.\(role.rawValue)"
            ),
            reference: .authoredMesh(source.identity),
            mesh: source,
            worldTransform: .identity,
            worldBounds: try source.bounds()
        )
    }

    private func scene(
        named name: String, items: [UniversalViewportSceneItem]
    ) -> UniversalViewportScene {
        let projectID = ProjectID(rawValue: "project.region-differential.\(name)")
        return UniversalViewportScene(
            snapshotID: EvaluationSnapshotID(
                projectID: projectID,
                purpose: .presentation,
                sourceRevision: DocumentTransactionRevision()
            ),
            projectID: projectID,
            items: items
        )
    }

    private func fixtureScene(
        layout: ViewportLayout, tessellation: Tessellation
    ) throws -> UniversalViewportScene {
        var items: [UniversalViewportSceneItem] = []
        for body in Self.bodies {
            items.append(
                try item(
                    for: body.role,
                    source: try source(
                        for: body, layout: layout, tessellation: tessellation
                    )
                )
            )
        }
        return scene(named: tessellation.rawValue, items: items)
    }

    /// One occurrence holding a hundred viewport-covering quadrilaterals at
    /// distinct depths. Each of the two hundred triangles spans the whole
    /// viewport bounding box, so the projected fragment charge exceeds the
    /// region ceiling without an injected limit.
    private func admissionScene(layout: ViewportLayout) throws -> UniversalViewportScene {
        let sourceID = GeometrySourceID(rawValue: "mesh.region-differential.admission")
        var builder = MeshSourceBuilder(identity: sourceID)
        try builder.reserveCapacity(vertexCount: 400, faceCount: 100, cornerCount: 400)
        let cell = Cell(minimumX: -8, minimumY: -8, maximumX: 520, maximumY: 392)
        for index in 0..<100 {
            let elevation = -0.4 + Double(index) * 0.008
            guard let map = PlaneMap(layout: layout, elevation: elevation) else {
                throw FixtureFailure(
                    description: "The layout does not project the admission plane \(index)."
                )
            }
            var vertexIDs: [MeshVertexID] = []
            vertexIDs.reserveCapacity(4)
            for corner in [cell.topLeft, cell.bottomLeft, cell.bottomRight, cell.topRight] {
                vertexIDs.append(
                    try builder.addVertex(map.world(corner, elevation: elevation))
                )
            }
            _ = try builder.addFace(vertexIDs: vertexIDs)
        }
        let source = try builder.build()
        let item = UniversalViewportSceneItem(
            id: SceneOccurrenceID(rawValue: "occurrence.region-differential.admission"),
            definitionID: ObjectDefinitionID(
                rawValue: "definition.region-differential.admission"
            ),
            displayName: "admission",
            representationID: GeometryRepresentationID(
                rawValue: "representation.region-differential.admission"
            ),
            reference: .authoredMesh(source.identity),
            mesh: source,
            worldTransform: .identity,
            worldBounds: try source.bounds()
        )
        return scene(named: "admission", items: [item])
    }

    /// The four world corners of the body that crosses the mounted camera's
    /// near plane, measured against the camera the frame mounts with.
    ///
    /// The two cameras hold that plane in different places and enforce it by
    /// different mechanisms, so each gets its own shape. The orthographic
    /// camera holds the plane one visible half-height in front of the eye,
    /// well inside the scene, and splits no triangle against it: it rejects a
    /// fragment whose interpolated depth falls in front of the plane. Its body
    /// is therefore a quadrilateral tilted through the plane, crossing it on a
    /// device pixel boundary with twenty layout points of surface on each
    /// side. The perspective camera holds the plane a millionth of a world
    /// unit in front of the eye and splits triangles against it, so only
    /// reaching behind the eye crosses it. Its body is therefore a
    /// quadrilateral whose front edge lies at the eye's own elevation and
    /// whose back edge lies behind the eye.
    private func straddleCorners(
        layout: ViewportLayout, probe: CameraProbe, perspective: Bool
    ) throws -> [GeometryPoint3D] {
        guard let map = PlaneMap(layout: layout, elevation: 0) else {
            throw FixtureFailure(
                description: "The layout does not project the straddle reference plane."
            )
        }
        guard perspective else {
            let cell = Self.straddleCell
            return [cell.topLeft, cell.bottomLeft, cell.bottomRight, cell.topRight]
                .map { corner -> GeometryPoint3D in
                    // The orthographic projection ignores elevation, so the
                    // tilt moves the surface through the plane without moving
                    // where the body draws.
                    let base = map.world(corner, elevation: 0)
                    return GeometryPoint3D(
                        x: base.x,
                        y: base.y,
                        z: probe.nearElevation + Self.straddleSlope
                            * (Self.straddleCrossingX - corner.x)
                    )
                }
        }
        let front = [
            Corner(x: Self.straddleFrontLeftX, y: Self.straddleFrontEdgeY),
            Corner(x: Self.straddleFrontRightX, y: Self.straddleFrontEdgeY)
        ].map { map.world($0, elevation: 0) }
        let behind = probe.eyeElevation + Self.straddleBehindEyeMargin
        return [
            front[0],
            front[1],
            GeometryPoint3D(x: front[1].x, y: front[1].y, z: behind),
            GeometryPoint3D(x: front[0].x, y: front[0].y, z: behind)
        ]
    }

    private func straddleSource(
        corners: [GeometryPoint3D]
    ) throws -> MeshSource {
        var builder = MeshSourceBuilder(
            identity: GeometrySourceID(rawValue: "mesh.region-differential.straddle")
        )
        try builder.reserveCapacity(vertexCount: 4, faceCount: 1, cornerCount: 4)
        var vertexIDs: [MeshVertexID] = []
        vertexIDs.reserveCapacity(corners.count)
        for corner in corners {
            vertexIDs.append(try builder.addVertex(corner))
        }
        _ = try builder.addFace(vertexIDs: vertexIDs)
        return try builder.build()
    }

    // MARK: - Mounting

    private func mount(
        scene: UniversalViewportScene, perspective: Bool, culls: Bool
    ) async throws -> MountedFrame {
        _ = NSApplication.shared
        let plan = try MeshSourcePresentationRenderPlan(scene: scene)
        let batch = try RealityViewportSpatialBatch(
            renderOrigin: .origin, retainedSurfaceByteCount: plan.retainedByteCount
        )
        let viewport = try await RealityViewport.prepare(
            plan: plan, spatialBatch: batch, reusing: nil
        )
        let layout = Self.layout(perspective: perspective)
        var reportedError: MeshSourcePresentationRenderError?
        let controller = NSHostingController(
            rootView: RealityViewportView(
                viewport: viewport,
                viewportRevision: Self.revision,
                displayMode: .solid,
                shading: .init(style: .flat, isBackfaceCullingEnabled: culls),
                occurrenceMaterials: [:],
                layout: layout,
                interaction: .init(
                    sceneNodeIDByOccurrenceID: [:],
                    selectedSceneNodeIDs: [],
                    previewSceneNodeIDs: [],
                    hoveredSceneNodeID: nil
                ),
                sectionPlane: nil,
                retainedSide: .front,
                sectionTolerance: 0,
                onUpdateResult: { reportedError = $0 }
            )
            .frame(width: Self.viewportSize.width, height: Self.viewportSize.height)
            .environment(\.displayScale, Self.displayScale)
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.viewportSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while viewport.project(Point3D(x: 0.5, y: 0.5, z: 0)) == nil {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        if let reportedError { throw reportedError }
        return MountedFrame(viewport: viewport, window: window)
    }

    private func unmount(_ frame: MountedFrame) {
        frame.viewport.unbind()
        frame.window.contentViewController = nil
        frame.window.close()
    }

    // MARK: - Camera probe

    /// Reads the mounted camera's near plane, and checks that depth is the
    /// affine function of world z the fixture places bodies by.
    ///
    /// Nothing here is a constant the fixture carries. The near depth comes
    /// from the camera itself and the eye's elevation from projecting the
    /// world origin, so a camera the layout derives differently moves the
    /// bodies with it instead of leaving them measured against a plane that
    /// is no longer there.
    private func probe(_ viewport: RealityViewport) throws -> CameraProbe {
        let interval = try viewport.cameraDepthInterval(revision: Self.revision)
        let eyeElevation = try viewport.projectedPointWithDepth(
            Point3D(x: 0, y: 0, z: 0), revision: Self.revision
        ).depth
        guard eyeElevation.isFinite else {
            throw FixtureFailure(
                description: "The mounted camera reports a non-finite depth for the world origin."
            )
        }
        for sample in Self.depthLinearitySamples {
            let measured = try viewport.projectedPointWithDepth(
                Point3D(x: sample.x, y: sample.y, z: sample.z), revision: Self.revision
            ).depth
            let expected = eyeElevation - sample.z
            let tolerance = max(
                Self.depthTolerance, abs(expected) * Self.depthRelativeTolerance
            )
            guard abs(measured - expected) <= tolerance else {
                throw FixtureFailure(
                    description: "The mounted camera reports depth \(measured) at world z \(sample.z), not the \(expected) an eye at \(eyeElevation) fixes."
                )
            }
        }
        return CameraProbe(near: interval.lowerBound, eyeElevation: eyeElevation)
    }

    /// The camera one layout mounts with, read from a frame that holds only
    /// the backdrop. It is what the straddle body's own shape is derived from.
    private func probeCamera(perspective: Bool) async throws -> CameraProbe {
        let layout = Self.layout(perspective: perspective)
        let backdrop = try Self.body(for: .backdrop)
        let probeScene = scene(
            named: "camera-probe",
            items: [
                try item(
                    for: .backdrop,
                    source: try source(
                        for: backdrop, layout: layout, tessellation: .baseline
                    )
                )
            ]
        )
        let frame = try await mount(
            scene: probeScene, perspective: perspective, culls: false
        )
        defer { unmount(frame) }
        return try probe(frame.viewport)
    }

    // MARK: - Differencing

    /// The device pixels whose centres lie in the half-open point interval,
    /// which is the rule the frame's own rectangle walk uses.
    private func devicePixels(from lower: Double, to upper: Double) -> ClosedRange<Int> {
        let scale = Double(Self.displayScale)
        let first = Int(((lower * scale) - 0.5).rounded(.up))
        let last = Int(((upper * scale) - 0.5).rounded(.up)) - 1
        return first...last
    }

    private func distance(
        from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint
    ) -> Double {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let px = Double(point.x - start.x)
        let py = Double(point.y - start.y)
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (px * px + py * py).squareRoot() }
        let fraction = min(max((px * dx + py * dy) / lengthSquared, 0), 1)
        let qx = px - fraction * dx
        let qy = py - fraction * dy
        return (qx * qx + qy * qy).squareRoot()
    }

    /// The projection of the last point on the edge running from `anchor`
    /// towards `limit` that the mounted camera still answers for.
    ///
    /// The anchor projects, so an answer always exists. Each step halves a
    /// world-space interval using the frame's own projection, and no clipping
    /// rule of the fixture's own.
    private func projectionLimit(
        from anchor: GeometryPoint3D,
        towards limit: GeometryPoint3D,
        viewport: RealityViewport
    ) throws -> CGPoint {
        guard var nearest = try viewport.projectedPointWithDepth(
            Point3D(x: anchor.x, y: anchor.y, z: anchor.z), revision: Self.revision
        ).point else {
            throw FixtureFailure(
                description: "The mounted camera declines to project the anchor of an edge it answered for."
            )
        }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<Self.projectionBisectionSteps {
            let middle = (lower + upper) / 2
            let sample = Point3D(
                x: anchor.x + (limit.x - anchor.x) * middle,
                y: anchor.y + (limit.y - anchor.y) * middle,
                z: anchor.z + (limit.z - anchor.z) * middle
            )
            if let projected = try viewport.projectedPointWithDepth(
                sample, revision: Self.revision
            ).point {
                nearest = projected
                lower = middle
            } else {
                upper = middle
            }
        }
        return nearest
    }

    /// The projected segment one triangle edge draws, or nil when the mounted
    /// camera projects neither of its ends.
    ///
    /// A body crossing the near plane has vertices the camera declines to
    /// project, and the frame still draws the part of such a triangle that
    /// stays in front of the plane. The boundary that decides whether a
    /// disagreement sits on a projected edge is therefore the part of the edge
    /// the camera answers for, not the whole of it. A projection carries a
    /// straight edge to a straight segment, so bisecting for the last
    /// answerable point recovers that part exactly.
    private func projectedEdge(
        from start: GeometryPoint3D,
        to end: GeometryPoint3D,
        viewport: RealityViewport
    ) throws -> (CGPoint, CGPoint)? {
        let first = try viewport.projectedPointWithDepth(
            Point3D(x: start.x, y: start.y, z: start.z), revision: Self.revision
        ).point
        let second = try viewport.projectedPointWithDepth(
            Point3D(x: end.x, y: end.y, z: end.z), revision: Self.revision
        ).point
        switch (first, second) {
        case let (.some(head), .some(tail)):
            return (head, tail)
        case let (.some(head), .none):
            return (
                head,
                try projectionLimit(from: start, towards: end, viewport: viewport)
            )
        case let (.none, .some(tail)):
            return (
                try projectionLimit(from: end, towards: start, viewport: viewport),
                tail
            )
        case (.none, .none):
            return nil
        }
    }

    /// One side of a drawn triangle, carrying the two vertex identities that
    /// name it, the two world positions that draw it, and the boundary
    /// identity the render plan gives it.
    private struct TriangleSide {
        let first: MeshVertexID
        let second: MeshVertexID
        let start: GeometryPoint3D
        let end: GeometryPoint3D
        /// nil for an interior tessellation diagonal, which is the only side
        /// the two triangles of one quad can share.
        let edgeID: MeshEdgeID?
    }

    /// A side two triangles of one occurrence have in common.
    private struct SharedEdge {
        let start: GeometryPoint3D
        let end: GeometryPoint3D
        let rasterEdgeID: MeshEdgeID?
        let nativeEdgeID: MeshEdgeID?
    }

    /// Why the raster and the native query named different triangles at one
    /// pixel centre.
    private enum Disagreement {
        /// The two answers are triangles of one occurrence that share a side,
        /// and the pixel centre lies on the projection of that side, so which
        /// of the two owns the pixel is a tie the two rasterisers are free to
        /// break differently.
        case sharedEdge(String)
        /// The mounted camera projects no part of the shared side, so the
        /// sweep cannot decide whether the pixel centre sits on it.
        case unprojectable
        /// The disagreement is an answer the region raster has to get right.
        case mismatch(String)
    }

    /// The three sides of a drawn triangle, in the order
    /// `MeshSourcePresentationTriangle` assigns boundary identities: 0-1, 1-2
    /// and 2-0.
    private func sides(
        of triangle: MeshSourcePresentationTriangle
    ) -> [TriangleSide] {
        let ids = [
            triangle.firstVertexID, triangle.secondVertexID, triangle.thirdVertexID
        ]
        let positions = [
            triangle.firstPosition, triangle.secondPosition, triangle.thirdPosition
        ]
        let edgeIDs = [
            triangle.firstEdgeID, triangle.secondEdgeID, triangle.thirdEdgeID
        ]
        return ids.indices.map { index in
            let next = (index + 1) % ids.count
            return TriangleSide(
                first: ids[index],
                second: ids[next],
                start: positions[index],
                end: positions[next],
                edgeID: edgeIDs[index]
            )
        }
    }

    /// The side two triangles have in common, or nil when they do not share
    /// exactly two vertices.
    ///
    /// `MeshSourcePresentationRenderPlan.Occurrence.triangle(at:)` reads one
    /// vertex identity buffer per occurrence through the triangle's own
    /// indices, so the two triangles a quad is tessellated into report the
    /// same `MeshVertexID` for the corners they share. Exactly two shared
    /// corners is therefore exactly one shared side. Three would be one
    /// triangle reported twice, which the caller has already excluded, and
    /// fewer than two leaves no boundary a pixel centre could sit on.
    private func sharedEdge(
        between raster: MeshSourcePresentationTriangle,
        and native: MeshSourcePresentationTriangle
    ) -> SharedEdge? {
        let rasterSides = sides(of: raster)
        let nativeSides = sides(of: native)
        let rasterIDs = Set(rasterSides.map(\.first))
        let nativeIDs = Set(nativeSides.map(\.first))
        guard rasterIDs.intersection(nativeIDs).count == 2 else { return nil }
        for rasterSide in rasterSides {
            let corners = Set([rasterSide.first, rasterSide.second])
            for nativeSide in nativeSides
            where Set([nativeSide.first, nativeSide.second]) == corners {
                return SharedEdge(
                    start: rasterSide.start,
                    end: rasterSide.end,
                    rasterEdgeID: rasterSide.edgeID,
                    nativeEdgeID: nativeSide.edgeID
                )
            }
        }
        return nil
    }

    /// Which of the three a disagreement at one pixel centre is.
    ///
    /// Only a tie on a shared side is excusable. A pixel one query draws and
    /// the other does not, a pixel two occurrences claim, and a pixel claimed
    /// by two triangles that share no side are all answers a rectangle
    /// selection depends on, so they are reported rather than excused.
    private func classify(
        raster: MeshSourcePresentationTriangle?,
        native: MeshSourcePresentationTriangle?,
        at point: CGPoint,
        viewport: RealityViewport
    ) throws -> Disagreement {
        let drawn = raster.map { name($0) } ?? "none"
        let hit = native.map { name($0) } ?? "none"
        let pair = "raster=\(drawn) native=\(hit)"
        guard let raster, let native else {
            return .mismatch("one side empty \(pair)")
        }
        guard raster.occurrenceID == native.occurrenceID else {
            return .mismatch("different occurrences \(pair)")
        }
        guard let shared = sharedEdge(between: raster, and: native) else {
            return .mismatch("no shared side \(pair)")
        }
        guard let edge = try projectedEdge(
            from: shared.start, to: shared.end, viewport: viewport
        ) else {
            return .unprojectable
        }
        let separation = distance(
            from: point, toSegmentFrom: edge.0, to: edge.1
        )
        guard separation <= Self.boundaryTolerance else {
            return .mismatch(
                "\(separation) pt from the shared side of \(pair)"
            )
        }
        let identities = "\(describe(shared.rasterEdgeID))/\(describe(shared.nativeEdgeID))"
        return .sharedEdge(
            "\(separation) pt from side \(identities) of \(pair)"
        )
    }

    /// How an excused side reports its boundary identity. An interior
    /// tessellation diagonal carries none.
    private func describe(_ edgeID: MeshEdgeID?) -> String {
        edgeID.map { "\($0)" } ?? "interior"
    }

    private func name(_ triangle: MeshSourcePresentationTriangle) -> String {
        let corners = "\(triangle.firstVertexID)/\(triangle.secondVertexID)/\(triangle.thirdVertexID)"
        return "\(triangle.occurrenceID.rawValue)#\(triangle.faceID)#\(corners)"
    }

    private func sweep(_ viewport: RealityViewport) throws -> Sweep {
        var result = Sweep()
        let scale = Double(Self.displayScale)
        let columns = devicePixels(
            from: Double(Self.rectangle.minX), to: Double(Self.rectangle.maxX)
        )
        let rows = devicePixels(
            from: Double(Self.rectangle.minY), to: Double(Self.rectangle.maxY)
        )
        result.pixelCount = columns.count * rows.count
        let slabID = Self.occurrenceID(for: .slab)
        let straddleID = Self.occurrenceID(for: .straddle)
        var slabByRow: [Int: Int] = [:]
        for row in rows {
            for column in columns {
                let point = CGPoint(
                    x: (Double(column) + 0.5) / scale,
                    y: (Double(row) + 0.5) / scale
                )
                let fragment = try viewport.regionFragment(
                    at: point, revision: Self.revision
                )
                let hit = try viewport.surfaceHit(at: point, revision: Self.revision)
                if let fragment {
                    result.drawn += 1
                    let occurrenceID = fragment.triangle.occurrenceID
                    result.counts[occurrenceID, default: 0] += 1
                    result.occurrences.insert(occurrenceID)
                    if !result.triangles.contains(fragment.triangle) {
                        result.triangles.append(fragment.triangle)
                    }
                    if occurrenceID == slabID {
                        slabByRow[row, default: 0] += 1
                    }
                    if occurrenceID == straddleID {
                        result.straddleMinimumColumn = min(
                            result.straddleMinimumColumn, column
                        )
                        result.straddleMaximumColumn = max(
                            result.straddleMaximumColumn, column
                        )
                        result.straddleMinimumRow = min(result.straddleMinimumRow, row)
                        result.straddleMaximumRow = max(result.straddleMaximumRow, row)
                    }
                }
                switch (fragment, hit) {
                case (nil, nil):
                    result.agreements += 1
                case (.some(let drawn), .some(let native))
                    where drawn.triangle == native.triangle:
                    result.agreements += 1
                    let depth = try viewport.projectedPointWithDepth(
                        native.point, revision: Self.revision
                    ).depth
                    result.maximumDepthDeviation = max(
                        result.maximumDepthDeviation, abs(depth - drawn.depth)
                    )
                default:
                    switch try classify(
                        raster: fragment?.triangle,
                        native: hit?.triangle,
                        at: point,
                        viewport: viewport
                    ) {
                    case .sharedEdge(let description):
                        result.boundarySkips += 1
                        if result.skips.count < 12 {
                            result.skips.append(
                                "(\(column),\(row)) \(description)"
                            )
                        }
                    case .unprojectable:
                        result.unprojectable += 1
                    case .mismatch(let reason):
                        if result.failures.count < 12 {
                            result.failures.append(
                                "(\(column),\(row)) \(reason)"
                            )
                        }
                    }
                }
            }
        }
        result.maximumSlabRun = slabByRow.values.max() ?? 0
        return result
    }

    private func measure(
        tessellation: Tessellation,
        culls: Bool,
        section: SectionAnalysisResult.Plane?,
        perspective: Bool
    ) async throws -> Sweep {
        let layout = Self.layout(perspective: perspective)
        let scene = try fixtureScene(layout: layout, tessellation: tessellation)
        let frame = try await mount(scene: scene, perspective: perspective, culls: culls)
        defer { unmount(frame) }
        if let section {
            try frame.viewport.applySection(plane: section, side: .front, tolerance: 0)
        }
        var result = try sweep(frame.viewport)
        result.notchOccurrence = try frame.viewport.regionFragment(
            at: Self.notchProbe, revision: Self.revision
        )?.triangle.occurrenceID
        result.regionOccurrences = Set(
            try frame.viewport.occurrenceIDs(
                intersecting: Self.rectangle, revision: Self.revision
            )
        )
        var emitted: [MeshSourcePresentationTriangle] = []
        try frame.viewport.forEachRegionTriangle(
            intersecting: Self.rectangle, revision: Self.revision
        ) { emitted.append($0) }
        result.regionTriangles = emitted
        return result
    }

    /// Mounts the backdrop and a body that crosses the mounted camera's near
    /// plane, and sweeps the rectangle over it.
    ///
    /// The camera is read twice: once on a frame holding only the backdrop, to
    /// derive the body's corners, and again on the frame that draws the body,
    /// so the placement is checked against the camera that actually clips it
    /// rather than assumed to have survived the change of scene.
    private func straddleMeasurement(
        perspective: Bool
    ) async throws -> StraddleMeasurement {
        let layout = Self.layout(perspective: perspective)
        let probed = try await probeCamera(perspective: perspective)
        let corners = try straddleCorners(
            layout: layout, probe: probed, perspective: perspective
        )
        let backdrop = try Self.body(for: .backdrop)
        let items = [
            try item(
                for: .backdrop,
                source: try source(
                    for: backdrop, layout: layout, tessellation: .baseline
                )
            ),
            try item(for: .straddle, source: try straddleSource(corners: corners))
        ]
        let frame = try await mount(
            scene: scene(named: "straddle", items: items),
            perspective: perspective,
            culls: false
        )
        defer { unmount(frame) }
        let mounted = try probe(frame.viewport)
        var result = try sweep(frame.viewport)
        result.regionOccurrences = Set(
            try frame.viewport.occurrenceIDs(
                intersecting: Self.rectangle, revision: Self.revision
            )
        )
        var emitted: [MeshSourcePresentationTriangle] = []
        try frame.viewport.forEachRegionTriangle(
            intersecting: Self.rectangle, revision: Self.revision
        ) { emitted.append($0) }
        result.regionTriangles = emitted
        var minimumDepth = Double.infinity
        var maximumDepth = -Double.infinity
        for corner in corners {
            let depth = try frame.viewport.projectedPointWithDepth(
                Point3D(x: corner.x, y: corner.y, z: corner.z), revision: Self.revision
            ).depth
            minimumDepth = min(minimumDepth, depth)
            maximumDepth = max(maximumDepth, depth)
        }
        return StraddleMeasurement(
            probe: probed,
            mountedProbe: mounted,
            sweep: result,
            minimumCornerDepth: minimumDepth,
            maximumCornerDepth: maximumDepth
        )
    }

    private func expectAgreement(_ sweep: Sweep, label: String) {
        print("""
            [region-differential] \(label) pixels=\(sweep.pixelCount) \
            drawn=\(sweep.drawn) agreements=\(sweep.agreements) \
            boundarySkips=\(sweep.boundarySkips) \
            depthDeviation=\(sweep.maximumDepthDeviation) \
            slabRun=\(sweep.maximumSlabRun)
            """)
        if !sweep.skips.isEmpty {
            print(
                "[region-differential] \(label) skipped \(sweep.skips.joined(separator: " | "))"
            )
        }
        #expect(
            sweep.failures.isEmpty,
            "\(label): the raster and the native hit disagree where no shared side of one occurrence explains it: \(sweep.failures.joined(separator: " | "))"
        )
        #expect(
            sweep.unprojectable == 0,
            "\(label): \(sweep.unprojectable) pixels could not be classified because the camera projects no part of the shared side"
        )
        #expect(
            sweep.drawn == sweep.pixelCount,
            "\(label): the backdrop covers the rectangle, so every swept pixel must draw, but \(sweep.drawn) of \(sweep.pixelCount) did"
        )
        #expect(
            Double(sweep.boundarySkips)
                <= Double(sweep.drawn) * Self.maximumBoundarySkipFraction,
            "\(label): \(sweep.boundarySkips) of \(sweep.drawn) pixels were excused as edge-ambiguous"
        )
        #expect(
            sweep.maximumDepthDeviation <= Self.depthTolerance,
            "\(label): the raster and the native hit disagree about depth by \(sweep.maximumDepthDeviation)"
        )
        #expect(
            sweep.regionOccurrences == sweep.occurrences,
            "\(label): the rectangle occurrence answer differs from the per-pixel sweep"
        )
        #expect(
            Set(sweep.regionTriangles.map { name($0) })
                == Set(sweep.triangles.map { name($0) }),
            "\(label): the rectangle triangle answer differs from the per-pixel sweep"
        )
    }

    private func count(_ sweep: Sweep, _ role: Role) -> Int {
        sweep.counts[Self.occurrenceID(for: role)] ?? 0
    }

    // MARK: - Tests

    /// The seven replacement conditions on a mounted frame: a five device pixel
    /// sliver, a back face, a fully occluded body, a non-convex silhouette, an
    /// active section, several placements, and a changed triangulation. Each
    /// variant is its own mount because the frame key that owns the raster
    /// includes the section and the culling rule.
    @Test(.timeLimit(.minutes(5)), arguments: [false, true])
    func regionRasterMatchesTheNativeSurfaceQuery(perspective: Bool) async throws {
        let camera = perspective ? "perspective" : "orthographic"

        let baseline = try await measure(
            tessellation: .baseline, culls: false, section: nil, perspective: perspective
        )
        expectAgreement(baseline, label: "baseline.\(camera)")
        #expect(
            count(baseline, .hidden) == 0,
            "baseline.\(camera): a body inset inside its occluder must not be selected"
        )
        for role in [Role.backdrop, .occluder, .slab, .nonconvex, .backface] {
            #expect(
                count(baseline, role) > 0,
                "baseline.\(camera): \(role.rawValue) is drawn and must be selected"
            )
        }
        #expect(
            (3...8).contains(baseline.maximumSlabRun),
            "baseline.\(camera): the 2.5 point sliver covered \(baseline.maximumSlabRun) device pixels per row"
        )
        #expect(
            baseline.notchOccurrence == Self.occurrenceID(for: .backdrop),
            "baseline.\(camera): the notch of the L must answer the backdrop behind it"
        )

        let sectioned = try await measure(
            tessellation: .baseline, culls: false,
            section: Self.sectionPlane, perspective: perspective
        )
        expectAgreement(sectioned, label: "section.\(camera)")
        #expect(
            count(sectioned, .occluder) == 0,
            "section.\(camera): the cut removes the occluder"
        )
        #expect(
            count(sectioned, .slab) == 0,
            "section.\(camera): the cut removes the slab"
        )
        #expect(
            count(sectioned, .hidden) > 0,
            "section.\(camera): removing the occluder exposes the body behind it"
        )

        let culled = try await measure(
            tessellation: .baseline, culls: true, section: nil, perspective: perspective
        )
        expectAgreement(culled, label: "cull.\(camera)")
        #expect(
            count(culled, .backface) == 0,
            "cull.\(camera): a back-facing body is not drawn and must not be selected"
        )
        #expect(
            count(culled, .occluder) > 0,
            "cull.\(camera): culling back faces must not remove front-facing bodies"
        )

        let retessellated = try await measure(
            tessellation: .alternate, culls: false, section: nil, perspective: perspective
        )
        expectAgreement(retessellated, label: "tessellation.\(camera)")
        for role in Role.allCases {
            #expect(
                count(retessellated, role) == count(baseline, role),
                "tessellation.\(camera): \(role.rawValue) changed from \(count(baseline, role)) to \(count(retessellated, role)) device pixels when only the triangulation changed"
            )
        }
    }

    /// A frame whose projected fragment charge exceeds the region ceiling
    /// refuses every rectangle query with the same typed code, and keeps
    /// answering the point query, so a consumer can tell an exhausted budget
    /// from a frame that is not ready.
    @Test(.timeLimit(.minutes(5)))
    func exhaustedRegionBudgetRefusesEveryRectangleQuery() async throws {
        let layout = Self.layout(perspective: false)
        let scene = try admissionScene(layout: layout)
        let frame = try await mount(scene: scene, perspective: false, culls: false)
        defer { unmount(frame) }
        let viewport = frame.viewport

        func expectExhausted(_ label: String, _ body: () throws -> Void) {
            do {
                try body()
                Issue.record("The \(label) query was admitted over an exhausted region budget.")
            } catch let error as MeshSourcePresentationRenderError {
                #expect(
                    error.code == .resourceExhausted,
                    "\(label): \(error.code.rawValue) \(error.message)"
                )
            } catch {
                Issue.record("The \(label) query failed with an untyped error: \(error)")
            }
        }

        expectExhausted("occurrenceIDs") {
            _ = try viewport.occurrenceIDs(
                intersecting: Self.rectangle, revision: Self.revision
            )
        }
        expectExhausted("forEachRegionTriangle") {
            try viewport.forEachRegionTriangle(
                intersecting: Self.rectangle, revision: Self.revision
            ) { _ in }
        }
        expectExhausted("regionFragment") {
            _ = try viewport.regionFragment(
                at: CGPoint(x: 256, y: 192), revision: Self.revision
            )
        }
        expectExhausted("regionSegmentProbe") {
            _ = try viewport.regionSegmentProbe(
                from: CGPoint(x: Self.rectangle.minX, y: Self.rectangle.minY),
                to: CGPoint(x: Self.rectangle.maxX, y: Self.rectangle.maxY),
                within: Self.rectangle, startingAt: 0, revision: Self.revision
            )
        }

        let centre = try viewport.surfaceHit(
            at: CGPoint(x: 256, y: 192), revision: Self.revision
        )
        #expect(
            centre != nil,
            "The point query must keep answering on a frame whose region budget is exhausted"
        )
    }

    /// A body that crosses the mounted camera's near plane keeps every device
    /// pixel of the part in front of the plane and none of the part behind it.
    ///
    /// The two cameras place the plane differently and enforce it by different
    /// mechanisms, so each mounts its own body and each asserts its own
    /// coverage. The orthographic frame rejects a fragment whose interpolated
    /// depth falls in front of the plane, so its tilted quadrilateral answers
    /// for the half of its footprint past the crossing and the backdrop
    /// answers for the rest. The perspective frame splits triangles against a
    /// plane a millionth of a unit in front of the eye, so its quadrilateral
    /// reaches behind the eye and answers for every rectangle pixel above its
    /// front edge. Each frame's whole rectangle is still swept against the
    /// native surface query, so a body the near plane removed too much of
    /// fails as a disagreement and not only as a count.
    @Test(.timeLimit(.minutes(5)), arguments: [false, true])
    func regionRasterClipsBodiesAcrossTheNearPlane(perspective: Bool) async throws {
        let camera = perspective ? "perspective" : "orthographic"
        let measurement = try await straddleMeasurement(perspective: perspective)
        let sweep = measurement.sweep
        expectAgreement(sweep, label: "straddle.\(camera)")

        #expect(
            measurement.mountedProbe.agrees(
                with: measurement.probe, tolerance: Self.cameraProbeTolerance
            ),
            "straddle.\(camera): the camera moved when the straddle body entered the scene, so the body is not placed against the plane that clips it: \(measurement.probe) became \(measurement.mountedProbe)"
        )
        #expect(
            measurement.minimumCornerDepth < measurement.mountedProbe.near,
            "straddle.\(camera): the nearest corner sits at depth \(measurement.minimumCornerDepth), behind the near plane at \(measurement.mountedProbe.near), so the body does not cross it"
        )
        #expect(
            measurement.maximumCornerDepth > measurement.mountedProbe.near,
            "straddle.\(camera): the farthest corner sits at depth \(measurement.maximumCornerDepth), in front of the near plane at \(measurement.mountedProbe.near), so the body does not cross it"
        )

        let columns = perspective
            ? devicePixels(
                from: Double(Self.rectangle.minX), to: Double(Self.rectangle.maxX)
            )
            : devicePixels(
                from: Self.straddleCrossingX, to: Self.straddleCell.maximumX
            )
        let rows = perspective
            ? devicePixels(
                from: Double(Self.rectangle.minY), to: Self.straddleFrontEdgeY
            )
            : devicePixels(
                from: Self.straddleCell.minimumY, to: Self.straddleCell.maximumY
            )
        let expected = columns.count * rows.count
        #expect(
            count(sweep, .straddle) == expected,
            "straddle.\(camera): the retained part of the body covers \(expected) device pixels but answered for \(count(sweep, .straddle))"
        )
        #expect(
            count(sweep, .backdrop) == sweep.pixelCount - expected,
            "straddle.\(camera): the backdrop must answer for the remaining \(sweep.pixelCount - expected) device pixels but answered for \(count(sweep, .backdrop))"
        )
        #expect(
            sweep.straddleMinimumColumn == columns.lowerBound
                && sweep.straddleMaximumColumn == columns.upperBound
                && sweep.straddleMinimumRow == rows.lowerBound
                && sweep.straddleMaximumRow == rows.upperBound,
            "straddle.\(camera): the body answered for columns \(sweep.straddleMinimumColumn)...\(sweep.straddleMaximumColumn) rows \(sweep.straddleMinimumRow)...\(sweep.straddleMaximumRow), not columns \(columns) rows \(rows)"
        )
    }
}
