import Foundation
import Metal
import RealityKit
import RupaCore
import RupaGeometry
import RupaViewportScene
import SwiftCAD
import SwiftUI
import simd

/// Owns native resources for one immutable presentation snapshot, never CAD data.
@MainActor
final class RealityViewport {
    static let surfaceCollisionGroup = CollisionGroup(rawValue: 1 << 0)
    static let spatialCollisionGroup = CollisionGroup(rawValue: 1 << 1)
    let root = Entity()
    let camera = Entity()
    let snapshotID: EvaluationSnapshotID?
    let renderOrigin: Point3D
    private(set) var appliedViewportRevision: UInt64?
    private(set) var appliedLayout: ViewportLayout?
    private(set) var maximumNativeUploadDuration: Duration = .zero
    private var surfaceResources: SurfaceResources?
    private var spatialResources: RealityViewportSpatialResources?
    private let lighting = Entity()
    private let clipper = Entity()
    private let geometryRoot = Entity()
    private var bounds = BoundingBox()
    private var fixedBounds = BoundingBox()
    private var entries: [(surface: ModelEntity, lines: ModelEntity?)] = []
    private var occurrenceByEntity: [ObjectIdentifier: Int] = [:]
    private var content: RealityViewCameraContent?
    private var bindingOwner: ObjectIdentifier?
    private var cameraCalibration: CameraCalibration?
    private var cameraCalibrationDepth: Double?
    private var appearance: Appearance?
    private var section: (normal: SIMD3<Double>, offset: Double, tolerance: Double)?
    private var requestedSection: (plane: SectionAnalysisResult.Plane, side: SectionAnalysisRetainedSide, tolerance: Double)?

    private struct Appearance: Equatable {
        let mode: ViewportDisplayMode
        let shading: ViewportShading
        let materialColors: [SceneOccurrenceID: ColorRGBA]
        let selected: Set<SceneNodeID>
        let preview: Set<SceneNodeID>
        let hovered: SceneNodeID?
        let plane: SectionAnalysisResult.Plane?
        let side: SectionAnalysisRetainedSide
        let tolerance: Double
    }

    /// A camera-local affine screen map sampled from the mounted native
    /// projection. Collision bounds are deliberately absent: this calibration
    /// is also the authority for empty-scene plane and axis queries.
    private struct CameraCalibration {
        let eye: SIMD3<Float>
        let inverseMapping: CGAffineTransform
        let sampleDepth: Float
        let step: Float
        let perspective: Bool
    }

    private struct NativeCameraRay {
        let origin: SIMD3<Float>
        let direction: SIMD3<Float>
        let near: Float
        let far: Float
    }

    /// A normalized native payload. Translation is kept as an instance value so
    /// equal geometry can share native resources without changing world-space
    /// presentation or CAD provenance.
    private struct Geometry: Sendable, Hashable {
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let lineIndices: [UInt32]
        let collisionIndices: [UInt32]
        let minimum: SIMD3<Float>
        let maximum: SIMD3<Float>
    }

    private struct GeometryPayload: Sendable {
        let geometry: Geometry
        let translation: SIMD3<Float>
    }

    /// This is the actual value stored for each unique geometry group. The
    /// visual index array is a COW reference to the representative occurrence
    /// buffer; collisionIndices already contains that same original prefix.
    private struct GeometryGroupRecord: Sendable {
        let geometry: Geometry
        let visualIndices: [UInt32]
        let reusedResourceIndex: Int?
    }

    private struct GeometryInstanceRecord: Sendable {
        let groupIndex: Int
        let translation: SIMD3<Float>
    }

    private struct GeometryGrouping: Sendable {
        let groups: [GeometryGroupRecord]
        let instances: [GeometryInstanceRecord]
        let groupByGeometry: [Geometry: Int]
    }

    /// Native resource references are retained once per unique geometry group.
    /// The corresponding entities remain distinct per occurrence.
    private struct NativeResourceReference {
        let visual: MeshResource
        let collision: ShapeResource
        let lines: MeshResource?
    }

    /// Immutable assets may outlive a frame; entities and appearance never do.
    private struct SurfaceResources {
        let plan: MeshSourcePresentationRenderPlan
        let materials: RealityViewportMaterial
        let resources: [NativeResourceReference]
        let groupByGeometry: [Geometry: Int]
        let instances: [GeometryInstanceRecord]
        let bounds: BoundingBox
    }

    private init(snapshotID: EvaluationSnapshotID?, origin: Point3D) {
        self.snapshotID = snapshotID
        renderOrigin = origin
        root.addChild(camera)
        root.addChild(clipper)
        clipper.addChild(geometryRoot)
        camera.addChild(lighting)
        for (direction, intensity) in [(SIMD3<Float>(-0.4, -0.6, -1), Float(3_000)), (SIMD3<Float>(0.7, 0.2, -1), Float(1_200))] {
            let light = DirectionalLight()
            light.light.intensity = intensity
            light.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: simd_normalize(direction))
            lighting.addChild(light)
        }
    }

    static func prepare(plan: MeshSourcePresentationRenderPlan) async throws -> RealityViewport {
        try await prepare(plan: plan, spatialBatch: nil, reusing: nil)
    }

    /// Frame-local provenance only. The host must still match its preparation
    /// identity before resolving a CAD operation from this index.
    func spatialHandleIndex(for entity: Entity) -> UInt32? {
        spatialResources?.handleIndex(for: entity)
    }

    /// The scale readout published by the current native grid frame. It is
    /// cleared when the grid is hidden or its update fails, so callers never
    /// display a value from an older camera frame.
    var gridScaleReadout: ViewportProjectedGrid.ScaleReadout? {
        spatialResources?.scaleReadout
    }

    static func prepare(
        plan: MeshSourcePresentationRenderPlan?,
        spatialBatch: RealityViewportSpatialBatch?,
        reusing previous: RealityViewport?
    ) async throws -> RealityViewport {
        try Task.checkCancellation()
        try spatialBatch?.validate(surfacePlan: plan)
        let first = plan?.occurrences.first?.positions.first
        let origin = spatialBatch?.renderOrigin
            ?? first.map { Point3D(x: $0.x, y: $0.y, z: $0.z) } ?? .origin
        let prepared = RealityViewport(snapshotID: plan?.snapshotID, origin: origin)
        if let plan, !plan.occurrences.isEmpty {
            if previous?.snapshotID == plan.snapshotID, previous?.renderOrigin == origin,
               let resources = previous?.surfaceResources {
                prepared.surfaceResources = resources
            } else {
                prepared.surfaceResources = try await prepared.prepareSurface(
                    plan: plan, retainedByteCount: spatialBatch?.admittedByteCount ?? plan.retainedByteCount,
                    reusing: previous?.surfaceResources)
            }
            try prepared.attachSurfaces()
        }
        if let spatialBatch {
            let spatial = try await RealityViewportSpatialResources.prepare(batch: spatialBatch, surfacePlan: plan)
            try Task.checkCancellation()
            prepared.spatialResources = spatial
            prepared.root.addChild(spatial.root)
            prepared.geometryRoot.addChild(spatial.sectionedRoot)
            if !spatial.sectionedRoot.children.isEmpty {
                prepared.bounds.formUnion(spatial.sectionedRoot.visualBounds(relativeTo: prepared.root, excludeInactive: false))
            }
        }
        prepared.fixedBounds = prepared.bounds
        try prepared.validateSurfaceCompleteness()
        try Task.checkCancellation()
        return prepared
    }

    private func prepareSurface(plan: MeshSourcePresentationRenderPlan, retainedByteCount: Int,
                                reusing previous: SurfaceResources?) async throws -> SurfaceResources {
        // The plan admits all owned Float position, face-normal, boundary, and collision
        // input arrays before this first native allocation. SDK-owned mesh,
        // collision, and program memory is bounded by admitted geometry/resource
        // counts and one candidate, not an invented exact native byte estimate.
        let grouping = try await Self.geometryGroups(
            occurrences: plan.occurrences,
            origin: renderOrigin,
            retainedByteCount: retainedByteCount,
            nativePreparationByteLimit: plan.nativePreparationByteLimit,
            previousGroups: previous?.groupByGeometry ?? [:]
        )
        try Task.checkCancellation()
        let materials: RealityViewportMaterial
        if let previous { materials = previous.materials }
        else { materials = try await RealityViewportMaterial() }
        var nativeResources: [NativeResourceReference] = []
        nativeResources.reserveCapacity(grouping.groups.count)
        for (groupIndex, group) in grouping.groups.enumerated() {
            try Task.checkCancellation()
            if let reusedIndex = group.reusedResourceIndex, let previous {
                nativeResources.append(previous.resources[reusedIndex])
                continue
            }
            var descriptor = MeshDescriptor(name: "group.\(groupIndex)")
            descriptor.positions = MeshBuffers.Positions(group.geometry.positions)
            // Face-rate normals ask RealityKit to preserve hard CAD face boundaries.
            descriptor.normals = MeshBuffers.Normals(group.geometry.normals).usingRate(.face)
            // The representative occurrence's buffer is the original visual
            // prefix of collisionIndices; retaining it avoids another index copy.
            descriptor.primitives = .triangles(group.visualIndices)
            let mesh = try await MeshResource(from: [descriptor])
            try Task.checkCancellation()
            // The macOS 27 runtime observes one-sided static collisions regardless
            // of material culling. A double-winding mesh keeps both sides pickable
            // without changing visual topology or source provenance.
            var collisionDescriptor = MeshDescriptor(name: "group.\(groupIndex).collision")
            collisionDescriptor.positions = MeshBuffers.Positions(group.geometry.positions)
            collisionDescriptor.primitives = .triangles(group.geometry.collisionIndices)
            let collisionMesh = try await MeshResource(from: [collisionDescriptor])
            try Task.checkCancellation()
            let collision = try await ShapeResource.generateStaticMesh(from: collisionMesh)
            try Task.checkCancellation()
            let lines = try await makeLineResource(group.geometry)
            try Task.checkCancellation()
            nativeResources.append(NativeResourceReference(visual: mesh, collision: collision, lines: lines))
        }

        var bounds = BoundingBox()
        for instance in grouping.instances {
            try Task.checkCancellation()
            let group = grouping.groups[instance.groupIndex]
            let minimum = group.geometry.minimum + instance.translation
            let maximum = group.geometry.maximum + instance.translation
            guard (0..<3).allSatisfy({ minimum[$0].isFinite && maximum[$0].isFinite }) else {
                throw Self.failure("Native geometry bounds exceed Float precision.")
            }
            bounds.formUnion(BoundingBox(min: minimum, max: maximum))
        }
        return SurfaceResources(plan: plan, materials: materials, resources: nativeResources,
                                groupByGeometry: grouping.groupByGeometry,
                                instances: grouping.instances, bounds: bounds)
    }

    private func attachSurfaces() throws {
        guard let surfaceResources else { return }
        bounds = surfaceResources.bounds
        for (index, instance) in surfaceResources.instances.enumerated() {
            try Task.checkCancellation()
            let resources = surfaceResources.resources[instance.groupIndex]
            let surface = ModelEntity(mesh: resources.visual, materials: [UnlitMaterial(color: .gray)])
            surface.position = instance.translation
            surface.components.set(CollisionComponent(
                shapes: [resources.collision],
                filter: .init(group: Self.surfaceCollisionGroup, mask: .all)
            ))
            geometryRoot.addChild(surface)
            occurrenceByEntity[ObjectIdentifier(surface)] = index
            let lines: ModelEntity?
            if let lineResource = resources.lines {
                let entity = ModelEntity(mesh: lineResource, materials: [UnlitMaterial(color: .gray)])
                entity.position = instance.translation
                geometryRoot.addChild(entity)
                lines = entity
            } else {
                lines = nil
            }
            entries.append((surface, lines))
        }
    }

    /// Validated once before publication. Only this owner may mutate surface
    /// descendants; the exposed root is reserved for host mount/unmount.
    func validateSurfaceCompleteness() throws {
        let count = surfaceResources?.plan.occurrences.count ?? 0
        guard entries.count == count, occurrenceByEntity.count == count else {
            throw Self.queryFailure("The prepared surface entries do not match source provenance.")
        }
        for (index, entry) in entries.enumerated() {
            try Task.checkCancellation()
            guard entry.surface.parent === geometryRoot,
                  occurrenceByEntity[ObjectIdentifier(entry.surface)] == index,
                  let collision = entry.surface.components[CollisionComponent.self],
                  !collision.shapes.isEmpty else {
                throw Self.queryFailure("The prepared surface is missing collision data or source provenance.")
            }
        }
    }

    @concurrent
    private nonisolated static func geometryGroups(
        occurrences: [MeshSourcePresentationRenderPlan.Occurrence],
        origin: Point3D,
        retainedByteCount: Int,
        nativePreparationByteLimit: Int,
        previousGroups: [Geometry: Int]
    ) async throws -> GeometryGrouping {
        try Task.checkCancellation()
        let reservation = try groupingReservation(occurrenceCount: occurrences.count)
        let required = try checkedAdd(retainedByteCount, reservation)
        guard retainedByteCount >= 0, nativePreparationByteLimit >= 0,
              required <= nativePreparationByteLimit else {
            throw resourceFailure("Native geometry grouping exceeds the admitted preparation byte limit.")
        }

        // The admission above covers the worst case in which every occurrence is
        // a unique group. The dictionary and both arrays are therefore bounded
        // before their first reserve/allocation.
        var groups: [GeometryGroupRecord] = []
        groups.reserveCapacity(occurrences.count)
        var instances: [GeometryInstanceRecord] = []
        instances.reserveCapacity(occurrences.count)
        var groupByGeometry: [Geometry: Int] = [:]
        groupByGeometry.reserveCapacity(occurrences.count)

        for (index, occurrence) in occurrences.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let payload = try await geometry(for: occurrence, origin: origin)
            try Task.checkCancellation()
            let groupIndex: Int
            if let existing = groupByGeometry[payload.geometry] {
                groupIndex = existing
            } else {
                groupIndex = groups.count
                groups.append(GeometryGroupRecord(geometry: payload.geometry,
                                                  visualIndices: occurrence.vertexIndices,
                                                  reusedResourceIndex: previousGroups[payload.geometry]))
                groupByGeometry[payload.geometry] = groupIndex
            }
            instances.append(GeometryInstanceRecord(groupIndex: groupIndex,
                                                    translation: payload.translation))
        }
        return GeometryGrouping(groups: groups, instances: instances, groupByGeometry: groupByGeometry)
    }

    @concurrent
    private nonisolated static func geometry(
        for occurrence: MeshSourcePresentationRenderPlan.Occurrence,
        origin: Point3D
    ) async throws -> GeometryPayload {
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(occurrence.positions.count)
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = -minimum
        for (index, point) in occurrence.positions.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let relative = SIMD3<Float>(Float(point.x - origin.x), Float(point.y - origin.y), Float(point.z - origin.z))
            guard relative.x.isFinite, relative.y.isFinite, relative.z.isFinite else {
                throw failure("Geometry cannot be represented relative to the native scene origin.")
            }
            positions.append(relative)
            minimum = simd_min(minimum, relative)
            maximum = simd_max(maximum, relative)
        }
        var normals: [SIMD3<Float>] = []
        var lineIndices: [UInt32] = []
        var collisionIndices = occurrence.vertexIndices
        collisionIndices.reserveCapacity(occurrence.vertexIndices.count * 2)
        normals.reserveCapacity(occurrence.triangleCount)
        lineIndices.reserveCapacity(occurrence.boundaryIndexCount)
        for triangle in 0..<occurrence.triangleCount {
            if triangle.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let base = triangle * 3
            let corners = occurrence.vertexIndices[base..<(base + 3)]
            let a = occurrence.positions[Int(corners[base])]
            let b = occurrence.positions[Int(corners[base + 1])]
            let c = occurrence.positions[Int(corners[base + 2])]
            let ab = SIMD3<Double>(b.x - a.x, b.y - a.y, b.z - a.z)
            let ac = SIMD3<Double>(c.x - a.x, c.y - a.y, c.z - a.z)
            let nativeA = positions[Int(corners[base])]
            let nativeCross = simd_cross(positions[Int(corners[base + 1])] - nativeA,
                                        positions[Int(corners[base + 2])] - nativeA)
            guard nativeCross.x.isFinite, nativeCross.y.isFinite, nativeCross.z.isFinite,
                  nativeCross != .zero else {
                throw failure("Native precision would collapse or overflow a presentation triangle.")
            }
            let normal = simd_normalize(simd_cross(ab, ac))
            guard normal.x.isFinite, normal.y.isFinite, normal.z.isFinite else {
                throw failure("A presentation triangle has no finite normal.")
            }
            normals.append(SIMD3<Float>(Float(normal.x), Float(normal.y), Float(normal.z)))
            collisionIndices.append(corners[base])
            collisionIndices.append(corners[base + 2])
            collisionIndices.append(corners[base + 1])
            for side in 0..<3 where occurrence.boundaryCornerIndices[base + side] != UInt32.max {
                lineIndices.append(occurrence.vertexIndices[base + side])
                lineIndices.append(occurrence.vertexIndices[base + (side + 1) % 3])
            }
        }
        let translation = positions.first ?? .zero
        var canCanonicalize = !positions.isEmpty
        if canCanonicalize {
            for (index, position) in positions.enumerated() {
                if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
                let local = position - translation
                let restored = local + translation
                guard local.x.isFinite, local.y.isFinite, local.z.isFinite,
                      restored.x == position.x, restored.y == position.y, restored.z == position.z else {
                    canCanonicalize = false
                    break
                }
            }
        }
        if canCanonicalize {
            // The first pass proved exact Float round-trip. Mutating the unique
            // freshly-built array in place avoids a second positions allocation.
            minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            maximum = -minimum
            for index in positions.indices {
                if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
                positions[index] -= translation
                minimum = simd_min(minimum, positions[index])
                maximum = simd_max(maximum, positions[index])
            }
            return GeometryPayload(
                geometry: Geometry(positions: positions, normals: normals, lineIndices: lineIndices,
                                   collisionIndices: collisionIndices, minimum: minimum, maximum: maximum),
                translation: translation
            )
        }
        return GeometryPayload(
            geometry: Geometry(positions: positions, normals: normals, lineIndices: lineIndices,
                               collisionIndices: collisionIndices, minimum: minimum, maximum: maximum),
            translation: .zero
        )
    }

    private func makeLineResource(_ geometry: Geometry) async throws -> MeshResource? {
        guard !geometry.lineIndices.isEmpty else { return nil }
        let mesh: LowLevelMesh
        do {
            let start = ContinuousClock.now
            let signposter = ViewportResponsivenessSignposts.signposter
            let interval = signposter.beginInterval("NativeLineUpload", id: signposter.makeSignpostID())
            defer {
                maximumNativeUploadDuration = max(maximumNativeUploadDuration, start.duration(to: .now))
                signposter.endInterval("NativeLineUpload", interval)
            }
            var descriptor = LowLevelMesh.Descriptor()
            descriptor.vertexCapacity = geometry.positions.count
            descriptor.indexCapacity = geometry.lineIndices.count
            descriptor.vertexAttributes = [.init(semantic: .position, format: .float3, offset: 0)]
            descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride)]
            descriptor.indexType = .uint32
            mesh = try LowLevelMesh(descriptor: descriptor)
            // The SDK requires this native allocation and scoped copy on MainActor.
            // Neither borrow escapes; off-actor preparation already built the arrays.
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { destination in
                geometry.positions.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            mesh.withUnsafeMutableIndices { destination in
                geometry.lineIndices.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            mesh.parts.replaceAll([.init(indexCount: geometry.lineIndices.count, topology: .line,
                                        bounds: .init(min: geometry.minimum, max: geometry.maximum))])
        }
        return try await MeshResource(from: mesh)
    }

    func applyCamera(layout: ViewportLayout, revision: UInt64) throws {
        cameraCalibration = nil
        cameraCalibrationDepth = nil
        let viewportCenter = CGPoint(x: layout.viewportSize.width / 2, y: layout.viewportSize.height / 2)
        guard let rows = layout.projectionRows(relativeTo: renderOrigin),
              let normal = layout.basis.viewNormal,
              let centerRay = layout.viewportRay(for: viewportCenter) else {
            throw Self.failure("The native camera requires a valid finite viewport layout.")
        }
        let forward = SIMD3<Double>(normal.x, normal.y, normal.z)
        let right = SIMD3<Double>(Double(layout.basis.xDirection.dx), Double(layout.basis.yDirection.dx), Double(layout.basis.zDirection.dx))
        let up = -SIMD3<Double>(Double(layout.basis.xDirection.dy), Double(layout.basis.yDirection.dy), Double(layout.basis.zDirection.dy))
        var eye = SIMD3<Double>(centerRay.origin.x - renderOrigin.x, centerRay.origin.y - renderOrigin.y, centerRay.origin.z - renderOrigin.z)
        var orthographic: OrthographicCameraComponent?
        var perspective: PerspectiveCameraComponent?
        switch layout.projection {
        case .parallel:
            let depth = SIMD3<Double>(rows.depth.x, rows.depth.y, rows.depth.z)
            // RealityKit's orthographic scale is the vertical half-extent.
            let visibleHalfHeight = layout.viewportSize.height / (2 * layout.scale)
            guard visibleHalfHeight.isFinite, visibleHalfHeight > 0 else {
                throw Self.failure("The orthographic camera vertical extent exceeds native precision.")
            }
            // The scene's own depth extent degenerates whenever every drawn
            // point shares one plane perpendicular to the view direction. A
            // sketch seen face-on reports an extent near zero, and the clip
            // window derived from it is thinner than the screen-sized handles
            // the overlay stands on that plane, so every native handle hit
            // falls outside the admitted near/far interval. Admitting at least
            // the visible half-extent keeps those handles inside the window;
            // the eye still sits two extents in front of the focus plane, so
            // the focus plane stays at the window's center and no admitted
            // scene depth is lost.
            var extent = max(0.5 / simd_length(depth), visibleHalfHeight)
            guard extent.isFinite, extent > 0 else {
                throw Self.failure("The orthographic camera depth extent exceeds native precision.")
            }
            let hasGrid = spatialResources?.hasGrid == true
            if hasGrid {
                let plane = ViewportCanvasPlane.displayed(for: layout.basis)
                let corners = [
                    CGPoint.zero,
                    CGPoint(x: layout.viewportSize.width, y: 0),
                    CGPoint(x: 0, y: layout.viewportSize.height),
                    CGPoint(x: layout.viewportSize.width, y: layout.viewportSize.height)
                ]
                for corner in corners {
                    guard let point = layout.unproject(corner, onto: plane),
                          point.x.isFinite, point.y.isFinite, point.z.isFinite else {
                        continue
                    }
                    let relative = SIMD3<Double>(
                        point.x - centerRay.origin.x,
                        point.y - centerRay.origin.y,
                        point.z - centerRay.origin.z
                    )
                    let distance = abs(simd_dot(relative, forward))
                    guard distance.isFinite else {
                        throw Self.failure("The native grid depth extent exceeds finite precision.")
                    }
                    extent = max(extent, distance)
                }
                let nativeExtent = Float(extent).nextUp
                guard nativeExtent.isFinite, nativeExtent > 0 else {
                    throw Self.failure("The orthographic camera depth extent exceeds native precision.")
                }
                extent = Double(nativeExtent)
            }
            eye += forward * (2 * extent)
            var component = OrthographicCameraComponent()
            component.near = Float(extent)
            component.far = Float(3 * extent)
            component.scale = Float(visibleHalfHeight)
            component.scaleDirection = .vertical
            guard component.near.isFinite, component.near > 0,
                  component.far.isFinite, component.far > component.near,
                  component.scale.isFinite, component.scale > 0 else {
                throw Self.failure("The orthographic camera exceeds native precision.")
            }
            cameraCalibrationDepth = (Double(component.near) + Double(component.far)) / 2
            orthographic = component
        case .perspective:
            let distance = (centerRay.origin - layout.focus).dot(normal)
            // Layout FOV describes the fitting rectangle. RealityKit's vertical
            // FOV describes the full viewport, including the reserved chrome.
            let fieldOfView = Float(2 * atan(Double(layout.viewportSize.height) / (2 * Double(layout.scale) * distance)) * 180 / .pi)
            guard distance.isFinite, distance > ViewportLayout.minimumPerspectiveW,
                  fieldOfView.isFinite, fieldOfView > 0, fieldOfView < 180 else {
                throw Self.failure("The perspective camera exceeds native precision.")
            }
            perspective = PerspectiveCameraComponent(
                near: Float(ViewportLayout.minimumPerspectiveW), far: .infinity,
                fieldOfViewInDegrees: fieldOfView, fieldOfViewOrientation: .vertical
            )
            cameraCalibrationDepth = max(Double(ViewportLayout.minimumPerspectiveW) * 2, distance)
        }
        let world = simd_double4x4(SIMD4<Double>(right, 0), SIMD4<Double>(up, 0), SIMD4<Double>(forward, 0), SIMD4<Double>(eye, 1))
        let nativeWorld = try Self.nativeMatrix(world)
        camera.transform = Transform(matrix: nativeWorld)
        if let orthographic {
            camera.components.remove(PerspectiveCameraComponent.self)
            camera.components.set(orthographic)
        }
        if let perspective {
            camera.components.remove(OrthographicCameraComponent.self)
            camera.components.set(perspective)
        }
        appliedLayout = layout
        appliedViewportRevision = revision
    }

    func applyAppearance(
        displayMode: ViewportDisplayMode, shading: ViewportShading,
        materialColors: [SceneOccurrenceID: ColorRGBA],
        interaction: MeshSourcePresentationInteractionStateResolver,
        sectionPlane: SectionAnalysisResult.Plane?, retainedSide: SectionAnalysisRetainedSide, sectionTolerance: Double
    ) throws {
        let key = Appearance(mode: displayMode, shading: shading, materialColors: materialColors, selected: interaction.selectedSceneNodeIDs,
                             preview: interaction.previewSceneNodeIDs, hovered: interaction.hoveredSceneNodeID,
                             plane: sectionPlane, side: retainedSide, tolerance: sectionTolerance)
        guard appearance != key else { return }
        try shading.validate()
        for color in materialColors.values {
            try RealityViewportMaterial.validate(color: color, field: "occurrence material color")
        }
        var prepared: [(any RealityKit.Material, UnlitMaterial)] = []
        if let surfaceResources {
          for occurrence in surfaceResources.plan.occurrences {
            var color = shading.resolvedColor(for: occurrence.occurrenceID, materialColor: materialColors[occurrence.occurrenceID])
            switch interaction.state(for: occurrence.occurrenceID) {
            case .normal: break
            case .selected: color = SIMD4<Float>(0.14, 0.66, 0.95, 1)
            case .hovered: color = SIMD4<Float>(0.36, 0.77, 0.98, 1)
            }
            let wire = shading.resolvedWireColor(for: occurrence.occurrenceID, objectColor: color)
            prepared.append((try surfaceResources.materials.surface(displayMode: displayMode, shading: shading, color: Self.color(color)),
                             surfaceResources.materials.line(color: Self.color(wire))))
          }
        }
        try applySection(plane: sectionPlane, side: retainedSide, tolerance: sectionTolerance)
        for (index, entry) in entries.enumerated() {
            entry.surface.model?.materials = [prepared[index].0]
            entry.lines?.model?.materials = [prepared[index].1]
            entry.lines?.isEnabled = displayMode == .wireframe || displayMode == .solidWithEdges
        }
        lighting.orientation = simd_quatf(angle: Float(shading.studioRotationDegrees * .pi / 180), axis: [0, 0, 1])
        appearance = key
    }

    /// One native clipping volume owns the cut for both surfaces and boundary lines.
    func applySection(plane: SectionAnalysisResult.Plane?, side: SectionAnalysisRetainedSide, tolerance: Double) throws {
        try updateSection(plane: plane, side: side, tolerance: tolerance)
        requestedSection = plane.map { ($0, side, tolerance) }
    }

    private func updateSection(plane: SectionAnalysisResult.Plane?, side: SectionAnalysisRetainedSide, tolerance: Double) throws {
        guard let plane, !geometryRoot.children.isEmpty else {
            section = nil
            clipper.components.remove(ClippingComponent.self)
            clipper.transform = .identity
            geometryRoot.transform = .identity
            geometryRoot.isEnabled = true
            return
        }
        let normal = SIMD3<Double>(plane.normal.x, plane.normal.y, plane.normal.z)
        guard plane.origin.isFinite, normal.x.isFinite, normal.y.isFinite, normal.z.isFinite,
              simd_length_squared(normal) > 0, simd_length_squared(normal).isFinite,
              tolerance.isFinite, tolerance >= 0 else {
            throw Self.failure("The section plane and tolerance must be finite and valid.")
        }
        let z = simd_normalize(normal) * (side == .front ? 1.0 : -1.0)
        let reference = abs(z.x) < 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
        let x = simd_normalize(simd_cross(reference, z))
        let y = simd_cross(z, x)
        let relative = SIMD3<Double>(plane.origin.x - renderOrigin.x, plane.origin.y - renderOrigin.y, plane.origin.z - renderOrigin.z)
        let offset = simd_dot(relative, z)
        let frame = simd_double4x4(SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(0, 0, 0, 1))
        let cut = offset - tolerance
        guard offset.isFinite, cut.isFinite else {
            throw Self.failure("The section offset exceeds finite scene precision.")
        }
        var minimum = SIMD3<Double>(repeating: .greatestFiniteMagnitude)
        var maximum = -minimum
        for corner in 0..<8 {
            let point = SIMD3<Double>(Double(corner & 1 == 0 ? bounds.min.x : bounds.max.x),
                                      Double(corner & 2 == 0 ? bounds.min.y : bounds.max.y),
                                      Double(corner & 4 == 0 ? bounds.min.z : bounds.max.z))
            let local = SIMD3<Double>(simd_dot(point, x), simd_dot(point, y), simd_dot(point, z))
            minimum = simd_min(minimum, local)
            maximum = simd_max(maximum, local)
        }
        // A distant plane must not move an entirely retained scene through a
        // large native transform and lose its local floating-point precision.
        if minimum.z >= cut {
            try updateSection(plane: nil, side: side, tolerance: tolerance)
            return
        }
        if maximum.z < cut {
            geometryRoot.isEnabled = false
            section = (z, offset, tolerance)
            return
        }
        // Only the cut-side bound represents a CAD boundary. Keep the other
        // five faces outside the complete scene by one scene diagonal, rather
        // than making nearly zero-width volumes for planar source geometry.
        let padding = simd_length(SIMD3<Double>(bounds.extents))
        minimum -= SIMD3(repeating: padding)
        maximum += SIMD3(repeating: padding)
        minimum.z = max(minimum.z, cut)
        let nativeFrame = try Self.nativeMatrix(frame)
        let nativeTransform = Transform(rotation: simd_quatf(nativeFrame))
        let inverseRotation = nativeTransform.rotation.inverse
        // Plane position belongs to the clipping bounds. Rotation-only
        // compensation avoids translation cancellation moving depth-boundary
        // geometry outside the camera volume.
        let nativeInverse = Transform(rotation: inverseRotation)
        let nativeMin = SIMD3<Float>(minimum)
        let nativeMax = SIMD3<Float>(maximum)
        guard (0..<3).allSatisfy({ nativeMin[$0].isFinite && nativeMax[$0].isFinite }) else {
            throw Self.failure("The section bounds exceed native scene precision.")
        }
        geometryRoot.isEnabled = minimum.z <= maximum.z
        guard geometryRoot.isEnabled else { return }
        clipper.transform = nativeTransform
        geometryRoot.transform = nativeInverse
        var clipping = ClippingComponent(bounds: BoundingBox(min: nativeMin, max: nativeMax))
        clipping.featheredEdge = .none
        clipping.shouldClipChildren = true
        clipping.shouldClipSelf = false
        clipper.components.set(clipping)
        section = (z, offset, tolerance)
    }

    func bind(_ content: RealityViewCameraContent, owner: ObjectIdentifier? = nil) {
        self.content = content
        bindingOwner = owner
    }

    func isBound(to owner: ObjectIdentifier) -> Bool {
        content != nil && bindingOwner == owner
    }

    @discardableResult
    func updateSpatialCamera(safeRect: CGRect = .zero, excludedRects: [CGRect] = [],
                             gridRuler: RulerConfiguration? = nil,
                             gridSpacing: ViewportGridVisualSpacingMode = .adaptive) throws -> MeshSourcePresentationRenderError? {
        guard let content, let appliedLayout, appliedViewportRevision != nil else { return nil }
        let gridError = try spatialResources?.updateCamera(camera: camera, content: content, safeRect: safeRect, excludedRects: excludedRects,
                                           gridRuler: gridRuler, gridBasis: appliedLayout.basis,
                                           gridSize: appliedLayout.viewportSize, gridSpacing: gridSpacing)
        try updateCameraCalibration(content: content)
        if let spatialResources, spatialResources.hasSectionedCameraGeometry {
            bounds = fixedBounds
            bounds.formUnion(spatialResources.sectionedRoot.visualBounds(relativeTo: root, excludeInactive: false))
            if let requestedSection {
                try updateSection(plane: requestedSection.plane, side: requestedSection.side, tolerance: requestedSection.tolerance)
            }
        }
        return gridError
    }

    /// Rebuilds the projection-free camera map only after the mounted native
    /// camera has accepted the current frame. This remains valid when the
    /// frame has no collision geometry because it samples the camera itself.
    private func updateCameraCalibration(content: RealityViewCameraContent) throws {
        let orthographic = camera.components[OrthographicCameraComponent.self]
        let perspective = camera.components[PerspectiveCameraComponent.self]
        guard orthographic == nil || perspective == nil else {
            throw Self.failure("The native camera has conflicting projection components.")
        }
        let near: Float
        let far: Float
        let sampleDepth: Float
        let step: Float
        let isPerspective: Bool
        if let orthographic {
            near = orthographic.near
            far = orthographic.far
            sampleDepth = Float((Double(near) + Double(far)) / 2)
            step = orthographic.scale
            isPerspective = false
        } else if let perspective {
            near = perspective.near
            far = perspective.far
            guard let requestedDepth = cameraCalibrationDepth else {
                throw Self.failure("The perspective camera has no admitted calibration depth.")
            }
            sampleDepth = Float(requestedDepth)
            step = sampleDepth
            isPerspective = true
        } else {
            throw Self.failure("The native camera has no projection component.")
        }
        guard near.isFinite, near > 0, far.isFinite || far == .infinity, far > near,
              sampleDepth.isFinite, sampleDepth > 0,
              step.isFinite, step > 0 else {
            throw Self.failure("The native camera calibration depth is not finite and positive.")
        }
        func project(_ local: SIMD3<Float>) -> CGPoint? {
            content.project(point: camera.convert(position: local, to: nil), to: .local)
        }
        guard let zero = project([0, 0, -sampleDepth]),
              let right = project([step, 0, -sampleDepth]),
              let up = project([0, step, -sampleDepth]),
              zero.x.isFinite, zero.y.isFinite,
              right.x.isFinite, right.y.isFinite,
              up.x.isFinite, up.y.isFinite else {
            throw RealityViewportSpatialResources.CameraReadinessError.projectionUnavailable
        }
        let mapping = CGAffineTransform(a: right.x - zero.x, b: right.y - zero.y,
                                         c: up.x - zero.x, d: up.y - zero.y,
                                         tx: zero.x, ty: zero.y)
        let determinant = mapping.a * mapping.d - mapping.b * mapping.c
        guard determinant.isFinite, determinant != 0 else {
            throw RealityViewportSpatialResources.CameraReadinessError.projectionUnavailable
        }
        let inverse = mapping.inverted()
        let eye = camera.convert(position: .zero, to: nil)
        guard eye.x.isFinite, eye.y.isFinite, eye.z.isFinite else {
            throw Self.failure("The native camera eye is not finite.")
        }
        cameraCalibration = CameraCalibration(
            eye: eye, inverseMapping: inverse,
            sampleDepth: sampleDepth, step: step, perspective: isPerspective
        )
    }

    func unbind(owner: ObjectIdentifier? = nil) {
        guard bindingOwner == owner else { return }
        // A RealityView root has no Entity parent. Withdraw it from its actual
        // scene owner before releasing the content and camera query lifetime.
        content?.remove(root)
        content = nil
        bindingOwner = nil
        appliedLayout = nil
        appliedViewportRevision = nil
        cameraCalibration = nil
        cameraCalibrationDepth = nil
        appearance = nil
        root.removeFromParent()
    }

    func invalidateCamera() {
        appliedLayout = nil
        appliedViewportRevision = nil
        cameraCalibration = nil
        cameraCalibrationDepth = nil
        root.isEnabled = false
    }

    /// Keep the native camera active while withholding an incomplete spatial frame.
    func setPresentationEnabled(_ enabled: Bool) {
        clipper.isEnabled = enabled
        spatialResources?.root.isEnabled = enabled
    }

    func triangle(for hit: CollisionCastHit) -> MeshSourcePresentationTriangle? {
        guard let plan = surfaceResources?.plan,
              let occurrence = occurrenceByEntity[ObjectIdentifier(hit.entity)], let face = hit.triangleHit?.faceIndex,
              let sourceFace = Self.sourceTriangleIndex(for: face, triangleCount: plan.occurrences[occurrence].triangleCount) else { return nil }
        return plan.occurrences[occurrence].triangle(at: sourceFace)
    }

    /// Queries the exact mounted native surface frame. A nil result is a valid
    /// miss after the native ray and all visibility/provenance filters run;
    /// readiness, camera, conversion, and provenance failures remain typed.
    func surfaceHit(at point: CGPoint, revision: UInt64) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)? {
        guard point.x.isFinite, point.y.isFinite else {
            throw Self.queryFailure("The native surface query point is not finite.")
        }
        try validateMountedFrame(describing: "surface query")
        try validateAppliedRevision(revision, describing: "surface query")
        guard !entries.isEmpty else { return nil }
        guard geometryRoot.isEnabled else { return nil }

        let query = try nativeHits(at: point)
        let hits = query.hits
        guard !hits.isEmpty else { return nil }
        for hit in hits where triangle(for: hit) == nil {
            throw Self.queryFailure("The native collision hit has no prepared surface provenance.")
        }
        guard let hit = retainedHits(hits, rayDirection: query.rayDirection).first,
              let triangle = triangle(for: hit) else {
            return nil
        }
        let worldPoint = Point3D(
            x: Double(hit.position.x) + renderOrigin.x,
            y: Double(hit.position.y) + renderOrigin.y,
            z: Double(hit.position.z) + renderOrigin.z
        )
        guard worldPoint.x.isFinite, worldPoint.y.isFinite, worldPoint.z.isFinite else {
            throw Self.queryFailure("The native collision point cannot be represented in CAD world space.")
        }
        return (triangle: triangle, point: worldPoint)
    }

    /// The occurrences this mounted frame draws inside `rect`, in the retained
    /// plan's order and de-duplicated.
    ///
    /// The rectangle is answered from `surfaceResources.plan` — the plan this
    /// frame itself drew — and from this frame's own projection and surface
    /// query, so the geometry it projects and the pixels it samples can never
    /// belong to two different plans. Section clipping, occlusion and back-face
    /// retention come from the surface query itself, so this path adds no
    /// filter of its own.
    ///
    /// An empty result is a valid answer once the frame is mounted and holds
    /// geometry; readiness, camera revision, projection and provenance failures
    /// remain typed. The two lists the answer carries, and the bounded cost
    /// contract, belong to `ViewportNativeOccurrenceRectangleResolver`.
    func occurrenceIDs(
        intersecting rect: CGRect, revision: UInt64
    ) throws -> ViewportRectangleResolution<SceneOccurrenceID> {
        try validateMountedFrame(describing: "occurrence rectangle query")
        try validateAppliedRevision(revision, describing: "occurrence rectangle query")
        guard !entries.isEmpty, geometryRoot.isEnabled, let plan = surfaceResources?.plan else {
            // A mounted frame holding no geometry judged no candidate, so
            // nothing here is unconfirmed.
            return ViewportRectangleResolution(confirmed: [], unconfirmed: [])
        }
        var occurrences: [MeshSourcePresentationOccurrenceView] = []
        occurrences.reserveCapacity(plan.occurrences.count)
        plan.forEachOccurrence { occurrences.append($0) }
        return try ViewportNativeOccurrenceRectangleResolver.occurrenceIDs(
            intersecting: rect,
            occurrences: occurrences,
            depthInterval: try cameraDepthInterval(revision: revision),
            projectWithDepth: { try self.projectedPointWithDepth($0, revision: revision) },
            drawnOccurrenceID: { try self.surfaceHit(at: $0, revision: revision)?.triangle.occurrenceID }
        )
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): These hits are the production input
    // authority only for the migrated routes. `Viewport.beginViewportPress` and
    // `Viewport.hover` resolve the prepared axis handles and the body transform
    // affordance from them; the sketch, curve, surface, pattern,
    // construction-plane and profile routes still fall through to the legacy
    // CPU selectors. RK-4.2.2/3 completes the cutover by preparing records for
    // those routes. Rectangle selection does not wait on this method at all:
    // `Viewport.selectionDragTarget` answers CAD face, edge and vertex
    // rectangles from prepared topology, and the occurrence rectangle from
    // `occurrenceIDs(intersecting:revision:)`, both through this same mounted
    // frame.
    func spatialHandleHits(at point: CGPoint, revision: UInt64) throws -> [UInt32] {
        guard point.x.isFinite, point.y.isFinite, appliedViewportRevision == revision,
              root.isEnabled, clipper.isEnabled, content != nil, root.scene != nil else {
            throw Self.queryFailure("The native handle query requires a finite point and matching mounted frame.")
        }
        guard let spatialResources, spatialResources.collisionBounds != nil else { return [] }
        let query = try nativeHits(at: point, mask: [Self.surfaceCollisionGroup, Self.spatialCollisionGroup])
        var occluder: Float?
        for hit in query.hits {
            guard hit.entity.isEnabledInHierarchy else { continue }
            guard let group = hit.entity.components[CollisionComponent.self]?.filter.group else {
                throw Self.queryFailure("The native hit lost its collision classification.")
            }
            if group == Self.surfaceCollisionGroup {
                guard triangle(for: hit) != nil else {
                    throw Self.queryFailure("The native collision hit has no prepared surface provenance.")
                }
                if occluder == nil, retains(hit, rayDirection: query.rayDirection) {
                    occluder = -camera.convert(position: hit.position, from: nil).z
                }
            } else if group != Self.spatialCollisionGroup {
                throw Self.queryFailure("The native collision hit has an ambiguous classification.")
            }
        }
        var candidates: [(index: UInt32, annotation: Bool, projected: CGFloat, distance: Float)] = []
        for hit in query.hits where hit.entity.isEnabledInHierarchy
            && hit.entity.components[CollisionComponent.self]?.filter.group == Self.spatialCollisionGroup {
            guard let metadata = spatialResources.handleMetadata(for: hit.entity) else {
                throw Self.queryFailure("The native collision hit has no prepared handle provenance.")
            }
            guard let distance = try spatialResources.projectedHandleDistance(for: hit.entity, at: point,
                section: metadata.attachment == .sectionedGeometry ? section : nil, project: {
                self.content?.project(point: $0, to: .local)
            }) else { continue }
            let position = distance.position ?? hit.position
            let depth = -camera.convert(position: position, from: nil).z
            guard distance.distance.isFinite, distance.distance >= 0,
                  position.x.isFinite, position.y.isFinite, position.z.isFinite, depth.isFinite else {
                throw Self.queryFailure("The native handle distance is not finite.")
            }
            // Conservative descriptor queries clip their source geometry before
            // finding its nearest point; exact colliders use the native hit.
            if distance.position == nil, metadata.attachment == .sectionedGeometry, let section,
               !Self.retains(SIMD3<Double>(position), section: section) {
                continue
            }
            if metadata.depth == .scene, let occluder, depth > occluder { continue }
            candidates.append((metadata.index, metadata.depth == .annotation, distance.distance, hit.distance))
        }
        candidates.sort {
            if $0.annotation != $1.annotation { return $0.annotation }
            if $0.projected != $1.projected { return $0.projected < $1.projected }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.index < $1.index
        }
        var seen: Set<UInt32> = []
        return candidates.compactMap { seen.insert($0.index).inserted ? $0.index : nil }
    }

    /// Collision winding copies never create a new editable CAD face.
    nonisolated static func sourceTriangleIndex(for face: Int, triangleCount: Int) -> Int? {
        guard triangleCount > 0, face >= 0 else { return nil }
        if face < triangleCount { return face }
        let reversedFace = face - triangleCount
        return reversedFace < triangleCount ? reversedFace : nil
    }

    func project(_ point: Point3D) -> CGPoint? {
        guard appliedViewportRevision != nil, root.isEnabled, clipper.isEnabled else { return nil }
        return content?.project(point: [Float(point.x - renderOrigin.x), Float(point.y - renderOrigin.y), Float(point.z - renderOrigin.z)], to: .local)
    }

    /// Projects operation baselines only through their matching mounted camera.
    func project(_ point: Point3D, revision: UInt64) throws -> CGPoint {
        guard appliedViewportRevision == revision, root.isEnabled, clipper.isEnabled,
              root.scene != nil, let content else {
            throw Self.queryFailure("The native projection requires a matching mounted camera revision.")
        }
        let local = SIMD3<Float>(
            Float(point.x - renderOrigin.x),
            Float(point.y - renderOrigin.y),
            Float(point.z - renderOrigin.z)
        )
        guard local.x.isFinite, local.y.isFinite, local.z.isFinite,
              let projected = content.project(point: local, to: .local),
              projected.x.isFinite, projected.y.isFinite else {
            throw Self.queryFailure("The native projection cannot represent the requested world point.")
        }
        return projected
    }

    /// The mounted camera's own depth interval, in the linear view-space depth
    /// `projectedPointWithDepth(_:revision:)` reports.
    ///
    /// A selection rectangle clips candidate geometry against this interval in
    /// world space, so it needs the interval itself and not only a per-point
    /// verdict. The rectangle and the point path read the interval only here,
    /// so the two cannot form a second opinion about where the camera stops
    /// drawing.
    ///
    /// The near plane is always finite and positive. The far plane is finite
    /// beyond it under the orthographic camera, and unbounded under the
    /// perspective camera this owner mounts with an infinite far plane, so the
    /// returned upper bound may be `.infinity` and means the camera never stops
    /// drawing rather than a malformed interval. This matches the interval the
    /// calibration and ray queries already accept.
    func cameraDepthInterval(revision: UInt64) throws -> ClosedRange<Double> {
        try validateCameraQuery(point: .zero, revision: revision)
        guard let near = camera.components[OrthographicCameraComponent.self]?.near
            ?? camera.components[PerspectiveCameraComponent.self]?.near,
              let far = camera.components[OrthographicCameraComponent.self]?.far
            ?? camera.components[PerspectiveCameraComponent.self]?.far else {
            throw Self.queryFailure("The mounted native camera has no depth interval.")
        }
        guard near.isFinite, near > 0, (far.isFinite && far > near) || far == .infinity else {
            throw Self.queryFailure("The mounted native camera has no ordered depth interval.")
        }
        return Double(near) ... Double(far)
    }

    /// Reports a world point's camera-space depth, and its projected point
    /// wherever the mounted camera answers for one.
    ///
    /// Depth is reported for every point this scene can represent, including
    /// one the camera's depth interval excludes, because a rectangle clips a
    /// candidate against that interval in world space and the crossing is
    /// interpolated from the depths on both sides of it. A nil point is the
    /// camera declining to project, which a caller reads as a miss; readiness,
    /// camera revision and scene-space representation failures stay typed.
    func projectedPointWithDepth(
        _ point: Point3D,
        revision: UInt64
    ) throws -> (point: CGPoint?, depth: Double) {
        try validateCameraQuery(point: .zero, revision: revision)
        let local = SIMD3<Float>(
            Float(point.x - renderOrigin.x), Float(point.y - renderOrigin.y),
            Float(point.z - renderOrigin.z)
        )
        guard local.x.isFinite, local.y.isFinite, local.z.isFinite else {
            throw Self.queryFailure("The world point cannot be represented in native scene space.")
        }
        let depth = -camera.convert(position: local, from: nil).z
        guard depth.isFinite else {
            throw Self.queryFailure("The mounted native camera reports no finite depth for the world point.")
        }
        guard let content, let projected = content.project(point: local, to: .local),
              projected.x.isFinite, projected.y.isFinite else {
            return (point: nil, depth: Double(depth))
        }
        return (point: projected, depth: Double(depth))
    }

    /// Admits a world point against the mounted camera's depth interval and
    /// reports its camera-space depth. A nil result is a valid depth rejection
    /// after the exact-ready gate; readiness, camera revision, representation
    /// and calibration failures remain typed. Screen containment, section
    /// clipping and occlusion are separate queries.
    func projectedPointWithinDepthRange(
        _ point: Point3D,
        revision: UInt64
    ) throws -> (point: CGPoint, depth: Double)? {
        let interval = try cameraDepthInterval(revision: revision)
        let answer = try projectedPointWithDepth(point, revision: revision)
        guard interval.contains(answer.depth) else { return nil }
        guard let projected = answer.point else {
            throw Self.queryFailure("The native projection cannot represent the requested world point.")
        }
        return (point: projected, depth: answer.depth)
    }

    /// Admits a world point against the mounted camera's depth interval only;
    /// screen containment, section clipping and occlusion are separate queries.
    func projectWithinDepthRange(_ point: Point3D, revision: UInt64) throws -> CGPoint {
        guard let admitted = try projectedPointWithinDepthRange(point, revision: revision) else {
            throw Self.queryFailure("The world point is outside the native camera depth range.")
        }
        return admitted.point
    }

    /// Reports the projection the mounted camera drew the frame with. Camera
    /// depth is linear in screen space under an orthographic camera and linear
    /// in reciprocal depth under a perspective camera, so a caller that
    /// interpolates along a projected segment has to follow the mode the frame
    /// was drawn with instead of inferring one from the sampled depths.
    func usesPerspectiveProjection(revision: UInt64) throws -> Bool {
        try validateCameraQuery(point: .zero, revision: revision)
        guard let cameraCalibration else {
            throw Self.queryFailure("The mounted native camera has no calibration.")
        }
        return cameraCalibration.perspective
    }

    /// Reports whether the mounted frame retains `point` on the kept side of
    /// the active section, using the predicate that admits native surface hits.
    ///
    /// Section clipping is not observable through the depth interval or through
    /// an empty pixel: a point the section removed draws nothing, exactly like a
    /// silhouette point just outside the tessellated outline. This query is the
    /// authority that separates the two, so no caller has to re-derive the cut
    /// from the section plane it did not apply.
    func retainsSectionedPoint(_ point: Point3D, revision: UInt64) throws -> Bool {
        try validateCameraQuery(point: .zero, revision: revision)
        // The point is validated before the scene state is read. A whole scene
        // behind the cut and a scene with no section both answer without the
        // predicate, so validating later would let an unrepresentable point
        // receive a plain `false` or `true` instead of the failure it owns.
        let local = SIMD3<Double>(
            point.x - renderOrigin.x, point.y - renderOrigin.y, point.z - renderOrigin.z
        )
        guard local.x.isFinite, local.y.isFinite, local.z.isFinite else {
            throw Self.queryFailure("The world point cannot be represented in native scene space.")
        }
        guard geometryRoot.isEnabled else { return false }
        guard let section else { return true }
        return Self.retains(local, section: section)
    }

    /// The single section admission predicate. `position` is in native scene
    /// space, which is `renderOrigin`-relative, so every caller converts before
    /// asking. Sharing one implementation keeps the drawn frame and the queries
    /// that report about it from drifting apart.
    private static func retains(
        _ position: SIMD3<Double>,
        section: (normal: SIMD3<Double>, offset: Double, tolerance: Double)
    ) -> Bool {
        simd_dot(position, section.normal) - section.offset >= -section.tolerance
    }

    /// Intersects a screen point with a world plane using the exact mounted
    /// native camera calibration. The returned point is in CAD world space;
    /// native scene coordinates remain relative to `renderOrigin` internally.
    func worldPlaneIntersection(
        at point: CGPoint,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        revision: UInt64
    ) throws -> Point3D {
        try validateCameraQuery(point: point, revision: revision)
        let normal = SIMD3<Double>(planeNormal.x, planeNormal.y, planeNormal.z)
        let normalLength = simd_length(normal)
        guard normal.x.isFinite, normal.y.isFinite, normal.z.isFinite,
              normalLength.isFinite, normalLength > 0,
              planeOrigin.x.isFinite, planeOrigin.y.isFinite, planeOrigin.z.isFinite else {
            throw Self.queryFailure("The native camera plane is not finite and valid.")
        }
        let unitNormal = normal / normalLength
        let ray = try nativeCameraRay(through: point)
        let origin = SIMD3<Double>(ray.origin)
        let rawDirection = SIMD3<Double>(ray.direction)
        let directionLength = simd_length(rawDirection)
        guard directionLength.isFinite, directionLength > 0 else {
            throw Self.queryFailure("The native camera ray direction is not finite.")
        }
        let direction = rawDirection / directionLength
        let denominator = simd_dot(direction, unitNormal)
        guard denominator.isFinite, abs(denominator) > 1e-12 else {
            throw Self.queryFailure("The native camera ray is parallel to the requested plane.")
        }
        let plane = SIMD3<Double>(
            planeOrigin.x - renderOrigin.x,
            planeOrigin.y - renderOrigin.y,
            planeOrigin.z - renderOrigin.z
        )
        let distance = simd_dot(plane - origin, unitNormal) / denominator
        guard distance.isFinite, distance >= 0 else {
            throw Self.queryFailure("The requested plane lies behind the native camera ray.")
        }
        let result = origin + direction * distance
        let world = Point3D(x: result.x + renderOrigin.x,
                            y: result.y + renderOrigin.y,
                            z: result.z + renderOrigin.z)
        guard world.x.isFinite, world.y.isFinite, world.z.isFinite else {
            throw Self.queryFailure("The native plane intersection is not finite in CAD world space.")
        }
        return world
    }

    /// Returns the signed physical distance along a retained world axis from
    /// its origin to the closest point represented by the native screen ray.
    /// The ray/axis closest-point solve preserves perspective reversal and does
    /// not treat a two-point screen chord as a world-space distance.
    func worldAxisParameter(
        at point: CGPoint,
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        revision: UInt64
    ) throws -> Double {
        try validateCameraQuery(point: point, revision: revision)
        let rawAxis = SIMD3<Double>(axisDirection.x, axisDirection.y, axisDirection.z)
        let axisLength = simd_length(rawAxis)
        guard rawAxis.x.isFinite, rawAxis.y.isFinite, rawAxis.z.isFinite,
              axisLength.isFinite, axisLength > 0,
              axisOrigin.x.isFinite, axisOrigin.y.isFinite, axisOrigin.z.isFinite else {
            throw Self.queryFailure("The native world axis is not finite and valid.")
        }
        let axis = rawAxis / axisLength
        let ray = try nativeCameraRay(through: point)
        let rawDirection = SIMD3<Double>(ray.direction)
        let directionLength = simd_length(rawDirection)
        guard directionLength.isFinite, directionLength > 0 else {
            throw Self.queryFailure("The native camera ray direction is not finite.")
        }
        let direction = rawDirection / directionLength
        let origin = SIMD3<Double>(ray.origin)
        let base = SIMD3<Double>(axisOrigin.x - renderOrigin.x,
                                 axisOrigin.y - renderOrigin.y,
                                 axisOrigin.z - renderOrigin.z)
        let offset = origin - base
        let dot = simd_dot(direction, axis)
        let denominator = 1 - dot * dot
        guard dot.isFinite, denominator.isFinite, denominator > 1e-12 else {
            throw Self.queryFailure("The native camera ray is parallel to the requested world axis.")
        }
        let rayParameter = simd_dot(direction, offset)
        let axisParameter = simd_dot(axis, offset)
        let rayDistance = (dot * axisParameter - rayParameter) / denominator
        let parameter = (axisParameter - dot * rayParameter) / denominator
        guard rayDistance.isFinite, rayDistance >= 0, parameter.isFinite else {
            throw Self.queryFailure("The requested world axis lies behind the native camera ray.")
        }
        return parameter
    }

    /// Returns the signed retained-axis movement between two native screen
    /// points. Both points are resolved independently against the same exact
    /// mounted camera revision.
    func worldAxisDelta(
        from start: CGPoint,
        to end: CGPoint,
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        revision: UInt64
    ) throws -> Double {
        let first = try worldAxisParameter(at: start, axisOrigin: axisOrigin,
                                           axisDirection: axisDirection, revision: revision)
        let second = try worldAxisParameter(at: end, axisOrigin: axisOrigin,
                                            axisDirection: axisDirection, revision: revision)
        let delta = second - first
        guard delta.isFinite else {
            throw Self.queryFailure("The native world-axis delta is not finite.")
        }
        return delta
    }

    func isCameraReady(revision: UInt64) -> Bool {
        do {
            // `.zero` is finite, so this asks only about the frame itself.
            try validateCameraQuery(point: .zero, revision: revision)
            return true
        } catch {
            return false
        }
    }

    /// The mount conditions every native query needs before a camera revision
    /// can mean anything: this view is installed and un-withdrawn, its content
    /// is live, and its entity graph belongs to a RealityKit scene.
    ///
    /// A frame failing these has drawn nothing and judged nothing, so the
    /// refusal is not-ready rather than an answer the caller must act on. It is
    /// checked before the applied revision because an unmounted frame has no
    /// revision to be stale about.
    private func validateMountedFrame(describing subject: String) throws {
        guard root.isEnabled, clipper.isEnabled, content != nil else {
            throw Self.notReadyFailure("The native \(subject) is unavailable for the mounted frame.")
        }
        guard root.scene != nil else {
            throw Self.notReadyFailure("The mounted native surface has no RealityKit scene.")
        }
    }

    /// Matches a query against the revision the mounted frame actually applied.
    ///
    /// A frame that has applied none is still arriving, so that is not-ready. A
    /// frame that applied a different one drew pixels this query must not be
    /// answered from, so that is a refusal.
    private func validateAppliedRevision(_ revision: UInt64, describing subject: String) throws {
        guard let applied = appliedViewportRevision else {
            throw Self.notReadyFailure("The native \(subject) has no applied camera revision yet.")
        }
        guard applied == revision else {
            throw Self.queryFailure("The native \(subject) uses a stale camera revision.")
        }
    }

    private func validateCameraQuery(point: CGPoint, revision: UInt64) throws {
        guard point.x.isFinite, point.y.isFinite else {
            throw Self.queryFailure("The native camera query point is not finite.")
        }
        try validateMountedFrame(describing: "camera query")
        guard cameraCalibration != nil else {
            throw Self.notReadyFailure("The native camera query has no calibrated mounted camera yet.")
        }
        try validateAppliedRevision(revision, describing: "camera query")
    }


    func hitTest(_ point: CGPoint, revision: UInt64) -> [CollisionCastHit] {
        guard appliedViewportRevision == revision, root.isEnabled, clipper.isEnabled, geometryRoot.isEnabled else {
            return []
        }
        do {
            let query = try nativeHits(at: point)
            return retainedHits(query.hits, rayDirection: query.rayDirection)
        } catch {
            // This legacy adapter retains its historical empty-result refusal
            // contract. The throwing surface query above is the RK-4 authority.
            return []
        }
    }

    private func nativeHits(at point: CGPoint, mask: CollisionGroup = surfaceCollisionGroup) throws -> (hits: [CollisionCastHit], rayDirection: SIMD3<Float>) {
        guard let scene = root.scene else {
            throw Self.queryFailure("The mounted native surface has no RealityKit scene.")
        }
        let ray = try cameraRay(through: point)
        var hits = scene.raycast(origin: ray.origin, direction: ray.direction, length: ray.length,
                                query: .all, mask: mask)
        try hits.removeAll { hit in
            guard hit.distance.isFinite, hit.distance >= 0 else {
                throw Self.queryFailure("The native collision query returned a non-finite distance.")
            }
            guard hit.position.x.isFinite, hit.position.y.isFinite, hit.position.z.isFinite else {
                throw Self.queryFailure("The native collision query returned a non-finite position.")
            }
            let depth = -camera.convert(position: hit.position, from: nil).z
            guard depth.isFinite else {
                throw Self.queryFailure("The native collision query returned a non-finite camera depth.")
            }
            return !(depth >= ray.near && depth <= ray.far)
        }
        hits.sort { $0.distance < $1.distance }
        return (hits: hits, rayDirection: ray.direction)
    }

    /// Mounted macOS 27 inverse queries do not round-trip native projection.
    /// Invert only a camera-plane affine map sampled through native project;
    /// camera transforms and all geometry intersections remain RealityKit's.
    private func nativeCameraRay(through point: CGPoint) throws -> NativeCameraRay {
        guard point.x.isFinite, point.y.isFinite,
              let calibration = cameraCalibration else {
            throw Self.queryFailure("The mounted native camera has no exact-ready calibration.")
        }
        let plane = point.applying(calibration.inverseMapping)
        guard plane.x.isFinite, plane.y.isFinite else {
            throw Self.queryFailure("The native camera plane inverse is not finite.")
        }
        let local = SIMD3<Double>(Double(plane.x) * Double(calibration.step),
                                  Double(plane.y) * Double(calibration.step),
                                  -Double(calibration.sampleDepth))
        guard local.x.isFinite, local.y.isFinite, local.z.isFinite else {
            throw Self.queryFailure("The native camera query point exceeds finite precision.")
        }
        let origin: SIMD3<Float>
        let direction: SIMD3<Float>
        if calibration.perspective {
            origin = calibration.eye
            direction = camera.convert(direction: SIMD3<Float>(simd_normalize(local)), to: nil)
        } else {
            origin = camera.convert(position: [Float(local.x), Float(local.y), 0], to: nil)
            direction = camera.convert(direction: [0, 0, -1], to: nil)
        }
        let magnitude = simd_length(SIMD3<Double>(direction))
        guard origin.x.isFinite, origin.y.isFinite, origin.z.isFinite,
              magnitude.isFinite, magnitude > 0 else {
            throw Self.queryFailure("The native camera ray is not finite and directed.")
        }
        let unitDirection = SIMD3<Float>(SIMD3<Double>(direction) / magnitude)
        guard unitDirection.x.isFinite, unitDirection.y.isFinite, unitDirection.z.isFinite else {
            throw Self.queryFailure("The native camera ray direction is not finite.")
        }
        let near = camera.components[OrthographicCameraComponent.self]?.near
            ?? camera.components[PerspectiveCameraComponent.self]?.near
        let far = camera.components[OrthographicCameraComponent.self]?.far
            ?? camera.components[PerspectiveCameraComponent.self]?.far
        guard let near, let far, near.isFinite, near > 0,
              (far.isFinite && far > near) || far == .infinity else {
            throw Self.queryFailure("The native camera clipping interval is invalid.")
        }
        return NativeCameraRay(origin: origin, direction: unitDirection, near: near, far: far)
    }

    /// Collision queries add a finite geometry-bounds length to the exact
    /// camera calibration. Plane and axis queries intentionally bypass this
    /// bounds requirement so an empty frame remains queryable.
    private func cameraRay(through point: CGPoint) throws -> (
        origin: SIMD3<Float>, direction: SIMD3<Float>, length: Float, near: Float, far: Float
    ) {
        var queryBounds = entries.isEmpty ? nil : bounds
        if let spatialBounds = spatialResources?.collisionBounds {
            if queryBounds == nil { queryBounds = spatialBounds }
            else { queryBounds?.formUnion(spatialBounds) }
        }
        guard let queryBounds else {
            throw Self.queryFailure("The mounted native camera has no finite collision bounds.")
        }
        let ray = try nativeCameraRay(through: point)
        let center = (SIMD3<Double>(queryBounds.min) + SIMD3<Double>(queryBounds.max)) / 2
        let diagonal = simd_length(SIMD3<Double>(queryBounds.max) - SIMD3<Double>(queryBounds.min))
        // A full diagonal leaves space beyond the enclosing sphere so native
        // raycast fully crosses the farthest surface, including flat bounds.
        let length = Float(simd_length(SIMD3<Double>(ray.origin) - center) + diagonal).nextUp
        guard diagonal.isFinite, diagonal > 0,
              length.isFinite, length > 0, length < Float.greatestFiniteMagnitude else {
            throw Self.queryFailure("The native collision bounds do not provide a finite ray length.")
        }
        return (ray.origin, ray.direction, length, ray.near, ray.far)
    }

    /// Native clipping changes rendering, not collision geometry. Keep the
    /// same half-space contract when resolving native collision results.
    func retainedHits(_ hits: [CollisionCastHit], rayDirection: SIMD3<Float>) -> [CollisionCastHit] {
        hits.filter { retains($0, rayDirection: rayDirection) }
    }

    private func retains(_ hit: CollisionCastHit, rayDirection: SIMD3<Float>) -> Bool {
        guard root.isEnabled, geometryRoot.isEnabled,
              rayDirection.x.isFinite, rayDirection.y.isFinite, rayDirection.z.isFinite,
              rayDirection != .zero else { return false }
        let cullsBackfaces = appearance.map { $0.shading.isBackfaceCullingActive(in: $0.mode) } ?? false
        guard let triangle = triangle(for: hit) else { return false }
        if let section {
            guard Self.retains(SIMD3<Double>(hit.position), section: section) else { return false }
        }
        if cullsBackfaces {
            let a = triangle.firstPosition
            let b = triangle.secondPosition
            let c = triangle.thirdPosition
            let ab = SIMD3<Double>(b.x - a.x, b.y - a.y, b.z - a.z)
            let ac = SIMD3<Double>(c.x - a.x, c.y - a.y, c.z - a.z)
            // Only classify a native hit; intersection remains RealityKit's.
            return simd_dot(simd_cross(ab, ac), SIMD3<Double>(rayDirection)) < 0
        }
        return true
    }

    private nonisolated static func color(_ value: SIMD4<Float>) -> ColorRGBA {
        ColorRGBA(r: Double(value.x), g: Double(value.y), b: Double(value.z), a: Double(value.w))
    }

    private nonisolated static func groupingReservation(occurrenceCount: Int) throws -> Int {
        guard occurrenceCount >= 0 else {
            throw resourceFailure("Native geometry grouping received a negative occurrence count.")
        }
        let groupBytes = try checkedMultiply(occurrenceCount, MemoryLayout<GeometryGroupRecord>.stride)
        let instanceBytes = try checkedMultiply(occurrenceCount, MemoryLayout<GeometryInstanceRecord>.stride)
        let resourceBytes = try checkedMultiply(occurrenceCount, MemoryLayout<NativeResourceReference>.stride)
        let dictionaryBytes: Int
        if occurrenceCount == 0 {
            dictionaryBytes = 0
        } else {
            let requestedBuckets = try checkedMultiply(occurrenceCount, 2)
            var bucketCount = 2
            while bucketCount < requestedBuckets {
                bucketCount = try checkedMultiply(bucketCount, 2)
            }
            // Account for the actual Geometry/Int key-value record plus one
            // machine word for occupancy/hash metadata per bucket and the same
            // fixed dictionary header allowance used by existing scratch charges.
            let keyValueStride = try checkedAdd(
                MemoryLayout<Geometry>.stride,
                MemoryLayout<Int>.stride
            )
            let bucketStride = try checkedAdd(keyValueStride, MemoryLayout<UInt64>.stride)
            dictionaryBytes = try checkedAdd(
                try checkedMultiply(bucketCount, bucketStride),
                128
            )
        }
        return try checkedAdd(
            try checkedAdd(groupBytes, instanceBytes),
            try checkedAdd(resourceBytes, dictionaryBytes)
        )
    }

    private nonisolated static func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw resourceFailure("Native geometry grouping reservation overflowed.")
        }
        return result.partialValue
    }

    private nonisolated static func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else {
            throw resourceFailure("Native geometry grouping reservation overflowed.")
        }
        return result.partialValue
    }

    private nonisolated static func resourceFailure(_ message: String) -> MeshSourcePresentationRenderError {
        .init(code: .resourceExhausted, message: message)
    }

    private static func nativeMatrix(_ matrix: simd_double4x4) throws -> simd_float4x4 {
        let result = simd_float4x4(SIMD4<Float>(matrix.columns.0), SIMD4<Float>(matrix.columns.1),
                                   SIMD4<Float>(matrix.columns.2), SIMD4<Float>(matrix.columns.3))
        for column in 0..<4 {
            for row in 0..<4 where !result[column][row].isFinite { throw failure("Native camera matrix is not finite.") }
        }
        return result
    }

    private nonisolated static func failure(_ message: String) -> MeshSourcePresentationRenderError {
        .init(code: .invalidTransform, message: message)
    }

    private nonisolated static func queryFailure(_ message: String) -> MeshSourcePresentationRenderError {
        .init(code: .failed, message: message)
    }

    /// A query that arrived before any frame could judge it. The caller may ask
    /// again; it must not read this as an answer.
    private nonisolated static func notReadyFailure(_ message: String) -> MeshSourcePresentationRenderError {
        .init(code: .frameNotReady, message: message)
    }
}
