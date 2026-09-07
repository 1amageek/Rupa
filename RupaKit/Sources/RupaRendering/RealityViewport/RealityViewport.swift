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
    let root = Entity()
    let camera = Entity()
    let snapshotID: EvaluationSnapshotID
    let renderOrigin: Point3D
    private(set) var appliedViewportRevision: UInt64?
    private(set) var appliedLayout: ViewportLayout?
    private(set) var maximumNativeUploadDuration: Duration = .zero
    private let plan: MeshSourcePresentationRenderPlan
    private let materials: RealityViewportMaterial
    private let lighting = Entity()
    private let clipper = Entity()
    private let geometryRoot = Entity()
    private var bounds = BoundingBox()
    private var entries: [(surface: ModelEntity, lines: ModelEntity?)] = []
    private var occurrenceByEntity: [ObjectIdentifier: Int] = [:]
    private var content: RealityViewCameraContent?
    private var appearance: Appearance?
    private var section: (normal: SIMD3<Double>, offset: Double, tolerance: Double)?

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
    }

    private struct GeometryInstanceRecord: Sendable {
        let groupIndex: Int
        let translation: SIMD3<Float>
    }

    private struct GeometryGrouping: Sendable {
        let groups: [GeometryGroupRecord]
        let instances: [GeometryInstanceRecord]
    }

    /// Native resource references are retained once per unique geometry group.
    /// The corresponding entities remain distinct per occurrence.
    private struct NativeResourceReference {
        let visual: MeshResource
        let collision: ShapeResource
        let lines: MeshResource?
    }

    private init(plan: MeshSourcePresentationRenderPlan, origin: Point3D) async throws {
        self.plan = plan
        snapshotID = plan.snapshotID
        renderOrigin = origin
        materials = try await RealityViewportMaterial()
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
        try Task.checkCancellation()
        // The plan admits all owned Float position, face-normal, boundary, and collision
        // input arrays before this first native allocation. SDK-owned mesh,
        // collision, and program memory is bounded by admitted geometry/resource
        // counts and one candidate, not an invented exact native byte estimate.
        let first = plan.occurrences.first?.positions.first
        let origin = first.map { Point3D(x: $0.x, y: $0.y, z: $0.z) } ?? .origin
        let grouping = try await geometryGroups(
            occurrences: plan.occurrences,
            origin: origin,
            retainedByteCount: plan.retainedByteCount,
            nativePreparationByteLimit: plan.nativePreparationByteLimit
        )
        try Task.checkCancellation()
        let prepared = try await RealityViewport(plan: plan, origin: origin)
        var nativeResources: [NativeResourceReference] = []
        nativeResources.reserveCapacity(grouping.groups.count)
        for (groupIndex, group) in grouping.groups.enumerated() {
            try Task.checkCancellation()
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
            let lines = try await prepared.makeLineResource(group.geometry)
            try Task.checkCancellation()
            nativeResources.append(NativeResourceReference(visual: mesh, collision: collision, lines: lines))
        }

        for (index, occurrence) in plan.occurrences.enumerated() {
            try Task.checkCancellation()
            let instance = grouping.instances[index]
            let group = grouping.groups[instance.groupIndex]
            let resources = nativeResources[instance.groupIndex]
            let surface = ModelEntity(mesh: resources.visual, materials: [UnlitMaterial(color: .gray)])
            surface.position = instance.translation
            surface.components.set(CollisionComponent(shapes: [resources.collision]))
            prepared.geometryRoot.addChild(surface)
            let minimum = group.geometry.minimum + instance.translation
            let maximum = group.geometry.maximum + instance.translation
            guard (0..<3).allSatisfy({ minimum[$0].isFinite && maximum[$0].isFinite }) else {
                throw Self.failure("Native geometry bounds exceed Float precision.")
            }
            prepared.bounds.formUnion(BoundingBox(min: minimum, max: maximum))
            prepared.occurrenceByEntity[ObjectIdentifier(surface)] = index
            let lines: ModelEntity?
            if let lineResource = resources.lines {
                let entity = ModelEntity(mesh: lineResource, materials: [UnlitMaterial(color: .gray)])
                entity.position = instance.translation
                prepared.geometryRoot.addChild(entity)
                lines = entity
            } else {
                lines = nil
            }
            prepared.entries.append((surface, lines))
        }
        return prepared
    }

    @concurrent
    private nonisolated static func geometryGroups(
        occurrences: [MeshSourcePresentationRenderPlan.Occurrence],
        origin: Point3D,
        retainedByteCount: Int,
        nativePreparationByteLimit: Int
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
                                                  visualIndices: occurrence.vertexIndices))
                groupByGeometry[payload.geometry] = groupIndex
            }
            instances.append(GeometryInstanceRecord(groupIndex: groupIndex,
                                                    translation: payload.translation))
        }
        return GeometryGrouping(groups: groups, instances: instances)
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
            let extent = 0.5 / simd_length(depth)
            eye += forward * (2 * extent)
            var component = OrthographicCameraComponent()
            component.near = Float(extent)
            component.far = Float(3 * extent)
            // RealityKit's orthographic scale is the vertical half-extent.
            component.scale = Float(layout.viewportSize.height / (2 * layout.scale))
            component.scaleDirection = .vertical
            guard component.near.isFinite, component.near > 0,
                  component.far.isFinite, component.far > component.near,
                  component.scale.isFinite, component.scale > 0 else {
                throw Self.failure("The orthographic camera exceeds native precision.")
            }
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
        for occurrence in plan.occurrences {
            var color = shading.resolvedColor(for: occurrence.occurrenceID, materialColor: materialColors[occurrence.occurrenceID])
            switch interaction.state(for: occurrence.occurrenceID) {
            case .normal: break
            case .selected: color = SIMD4<Float>(0.14, 0.66, 0.95, 1)
            case .hovered: color = SIMD4<Float>(0.36, 0.77, 0.98, 1)
            }
            let wire = shading.resolvedWireColor(for: occurrence.occurrenceID, objectColor: color)
            prepared.append((try materials.surface(displayMode: displayMode, shading: shading, color: Self.color(color)),
                             materials.line(color: Self.color(wire))))
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
        guard let plane, !entries.isEmpty else {
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
            try applySection(plane: nil, side: side, tolerance: tolerance)
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

    func bind(_ content: RealityViewCameraContent) { self.content = content }

    func unbind() {
        content = nil
        appliedLayout = nil
        appliedViewportRevision = nil
        appearance = nil
        root.removeFromParent()
    }

    func invalidateCamera() {
        appliedLayout = nil
        appliedViewportRevision = nil
        root.isEnabled = false
    }

    func triangle(for hit: CollisionCastHit) -> MeshSourcePresentationTriangle? {
        guard let occurrence = occurrenceByEntity[ObjectIdentifier(hit.entity)], let face = hit.triangleHit?.faceIndex,
              let sourceFace = Self.sourceTriangleIndex(for: face, triangleCount: plan.occurrences[occurrence].triangleCount) else { return nil }
        return plan.occurrences[occurrence].triangle(at: sourceFace)
    }

    /// Collision winding copies never create a new editable CAD face.
    nonisolated static func sourceTriangleIndex(for face: Int, triangleCount: Int) -> Int? {
        guard triangleCount > 0, face >= 0 else { return nil }
        if face < triangleCount { return face }
        let reversedFace = face - triangleCount
        return reversedFace < triangleCount ? reversedFace : nil
    }

    func project(_ point: Point3D) -> CGPoint? {
        guard appliedViewportRevision != nil else { return nil }
        return content?.project(point: [Float(point.x - renderOrigin.x), Float(point.y - renderOrigin.y), Float(point.z - renderOrigin.z)], to: .local)
    }

    func hitTest(_ point: CGPoint, revision: UInt64) -> [CollisionCastHit] {
        guard appliedViewportRevision == revision, root.isEnabled, geometryRoot.isEnabled,
              let scene = root.scene, let ray = cameraRay(through: point) else { return [] }
        var hits = scene.raycast(origin: ray.origin, direction: ray.direction, length: ray.length, query: .all)
        hits.removeAll { hit in
            guard hit.distance.isFinite, hit.distance >= 0 else { return true }
            let depth = -camera.convert(position: hit.position, from: nil).z
            return !(depth >= ray.near && depth <= ray.far)
        }
        hits.sort { $0.distance < $1.distance }
        return retainedHits(hits, rayDirection: ray.direction)
    }

    /// Mounted macOS 27 inverse queries do not round-trip native projection.
    /// Invert only a camera-plane affine map sampled through native project;
    /// camera transforms and all geometry intersections remain RealityKit's.
    private func cameraRay(through point: CGPoint) -> (
        origin: SIMD3<Float>, direction: SIMD3<Float>, length: Float, near: Float, far: Float
    )? {
        guard point.x.isFinite, point.y.isFinite, !entries.isEmpty, let content else { return nil }
        let orthographic = camera.components[OrthographicCameraComponent.self]
        let perspective = camera.components[PerspectiveCameraComponent.self]
        guard orthographic == nil || perspective == nil else { return nil }
        let center = (SIMD3<Double>(bounds.min) + SIMD3<Double>(bounds.max)) / 2
        let eye = camera.convert(position: .zero, to: nil)
        let near: Float
        let far: Float
        let depth: Float
        let step: Float
        if let orthographic {
            near = orthographic.near
            far = orthographic.far
            depth = Float((Double(near) + Double(far)) / 2)
            step = orthographic.scale
        } else if let perspective {
            near = perspective.near
            far = perspective.far
            depth = Float(max(Double(near) * 2, simd_length(SIMD3<Double>(eye) - center)))
            step = depth
        } else { return nil }
        guard near.isFinite, near > 0, far > near,
              depth.isFinite, depth > 0, step.isFinite, step > 0 else { return nil }
        func project(_ local: SIMD3<Float>) -> CGPoint? {
            content.project(point: camera.convert(position: local, to: nil), to: .local)
        }
        guard let zero = project([0, 0, -depth]),
              let right = project([step, 0, -depth]),
              let up = project([0, step, -depth]),
              zero.x.isFinite, zero.y.isFinite, right.x.isFinite, right.y.isFinite,
              up.x.isFinite, up.y.isFinite else { return nil }
        let mapping = CGAffineTransform(a: right.x - zero.x, b: right.y - zero.y,
                                        c: up.x - zero.x, d: up.y - zero.y, tx: zero.x, ty: zero.y)
        let determinant = mapping.a * mapping.d - mapping.b * mapping.c
        guard determinant.isFinite, determinant != 0 else { return nil }
        let plane = point.applying(mapping.inverted())
        let local = SIMD3<Double>(Double(plane.x) * Double(step), Double(plane.y) * Double(step), -Double(depth))
        guard local.x.isFinite, local.y.isFinite else { return nil }
        let origin: SIMD3<Float>
        let direction: SIMD3<Float>
        if orthographic != nil {
            origin = camera.convert(position: [Float(local.x), Float(local.y), 0], to: nil)
            direction = camera.convert(direction: [0, 0, -1], to: nil)
        } else {
            origin = eye
            direction = camera.convert(direction: SIMD3<Float>(simd_normalize(local)), to: nil)
        }
        let magnitude = simd_length(SIMD3<Double>(direction))
        let diagonal = simd_length(SIMD3<Double>(bounds.max) - SIMD3<Double>(bounds.min))
        // A full diagonal leaves space beyond the enclosing sphere so native
        // raycast fully crosses the farthest surface, including flat bounds.
        let length = Float(simd_length(SIMD3<Double>(origin) - center) + diagonal).nextUp
        guard origin.x.isFinite, origin.y.isFinite, origin.z.isFinite,
              magnitude.isFinite, magnitude > 0, diagonal.isFinite, diagonal > 0,
              length.isFinite, length > 0, length < Float.greatestFiniteMagnitude else { return nil }
        return (origin, SIMD3<Float>(SIMD3<Double>(direction) / magnitude), length, near, far)
    }

    /// Native clipping changes rendering, not collision geometry. Keep the
    /// same half-space contract when resolving native collision results.
    func retainedHits(_ hits: [CollisionCastHit], rayDirection: SIMD3<Float>) -> [CollisionCastHit] {
        guard root.isEnabled, geometryRoot.isEnabled,
              rayDirection.x.isFinite, rayDirection.y.isFinite, rayDirection.z.isFinite,
              rayDirection != .zero else { return [] }
        let cullsBackfaces = appearance.map { $0.shading.isBackfaceCullingActive(in: $0.mode) } ?? false
        return hits.filter { hit in
            guard let triangle = triangle(for: hit) else { return false }
            if let section {
                let position = SIMD3<Double>(hit.position)
                guard simd_dot(position, section.normal) - section.offset >= -section.tolerance else { return false }
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
}
