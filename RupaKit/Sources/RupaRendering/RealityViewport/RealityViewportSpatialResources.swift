import AppKit
import Foundation
import Metal
import RealityKit
import RupaCoreTypes
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI
import simd

/// Prepared resources only. The viewport cache owns request identity and publication.
@MainActor
final class RealityViewportSpatialResources {
    enum CameraReadinessError: Error {
        case projectionUnavailable
    }
    let root = Entity()
    let sectionedRoot = Entity()
    private let batch: RealityViewportSpatialBatch
    private var labels: [(Entity, RealityViewportSpatialBatch.Label)] = []
    private var markers: [(Entity, RealityViewportSpatialBatch.Marker)] = []
    private var cameraLines: [(ModelEntity, LowLevelMesh, RealityViewportSpatialBatch.CameraLine)] = []
    private var cameraPaths: [(Entity, RealityViewportSpatialBatch.CameraPath)] = []
    private var boundsRulers: [(ViewportMeasurementRulerAxis, Entity, ModelEntity, LowLevelMesh)] = []
    private var grid: (entity: ModelEntity, mesh: LowLevelMesh)?
    private var gridLabels: [Entity] = []
    private var gridPlacement: ModelEntity?
    private var handleIndices: [ObjectIdentifier: UInt32] = [:]
    private let surfaceItemCount: Int
    private let surfacePositionCount: Int
    private let byteLimit: Int
    private(set) var disabledRulerAxes: Set<ViewportMeasurementRulerAxis> = []
    private(set) var scaleReadout: ViewportProjectedGrid.ScaleReadout?

    /// True when the prepared batch admitted native grid resources, independent
    /// of whether the grid is currently enabled for a frame.
    var hasGrid: Bool { grid != nil }

    let hasSectionedCameraGeometry: Bool

    private struct WorldGeometry: Sendable {
        let positions: [SIMD3<Float>]
        let indices: [UInt32]
        let parts: [LowLevelMesh.Part]
        let appearances: [RealityViewportSpatialBatch.Appearance]
    }

    private struct WorldGroup: Sendable {
        let attachment: RealityViewportSpatialBatch.Attachment
        let handleIndex: UInt32?
        var meshIndices: [Int]
    }

    /// Lookup coordinates only; the host owns CAD identity and frame matching.
    func handleIndex(for entity: Entity) -> UInt32? {
        var candidate: Entity? = entity
        while let current = candidate {
            if let index = handleIndices[ObjectIdentifier(current)] { return index }
            if current === root || current === sectionedRoot { return nil }
            candidate = current.parent
        }
        return nil
    }

    private func register(_ entity: Entity, handleIndex: UInt32?) {
        if let handleIndex { handleIndices[ObjectIdentifier(entity)] = handleIndex }
    }

    private struct CameraProjection {
        let worldFromCamera: simd_float4x4
        let cameraFromWorld: simd_float4x4
        let forward: CGAffineTransform
        let inverseOffset: CGAffineTransform
        let sampleDepth: Float
        let perspective: Bool
        let annotationDepth: Float

        func local(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let value = cameraFromWorld * SIMD4(point, 1)
            return SIMD3(value.x, value.y, value.z)
        }

        func depthScale(_ local: SIMD3<Float>) -> Float { perspective ? -local.z / sampleDepth : 1 }

        func project(_ point: SIMD3<Float>) -> CGPoint? {
            let point = local(point)
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite, point.z < 0 else { return nil }
            let scale = depthScale(point)
            let result = CGPoint(x: CGFloat(point.x / scale), y: CGFloat(point.y / scale)).applying(forward)
            return result.x.isFinite && result.y.isFinite ? result : nil
        }

        func point(at screen: CGPoint, depth: Float) -> SIMD3<Float> {
            let offset = CGPoint(x: screen.x - forward.tx, y: screen.y - forward.ty).applying(inverseOffset)
            let scale = perspective ? depth / sampleDepth : 1
            let value = worldFromCamera * SIMD4(Float(offset.x) * scale, Float(offset.y) * scale, -depth, 1)
            return SIMD3(value.x, value.y, value.z)
        }

        func unproject(_ screen: CGPoint, onto plane: ViewportCanvasPlane, origin: Point3D) -> Point3D? {
            guard let normal = plane.normal else { return nil }
            let sample = point(at: screen, depth: sampleDepth)
            let start = perspective ? SIMD3(worldFromCamera.columns.3.x, worldFromCamera.columns.3.y, worldFromCamera.columns.3.z)
                : point(at: screen, depth: 0)
            let direction = SIMD3<Double>(sample - start)
            let worldStart = SIMD3<Double>(start) + SIMD3(origin.x, origin.y, origin.z)
            let n = SIMD3(normal.x, normal.y, normal.z)
            let denominator = simd_dot(direction, n)
            guard denominator.isFinite, abs(denominator) > 1e-12 else { return nil }
            let distance = -simd_dot(worldStart, n) / denominator
            guard distance.isFinite, distance >= 0 else { return nil }
            let result = worldStart + direction * distance
            guard result.x.isFinite, result.y.isFinite, result.z.isFinite else { return nil }
            return Point3D(x: result.x, y: result.y, z: result.z)
        }
    }

    private init(batch: RealityViewportSpatialBatch, surfacePlan: MeshSourcePresentationRenderPlan?) {
        self.batch = batch
        surfaceItemCount = surfacePlan?.itemCount ?? 0
        surfacePositionCount = surfacePlan?.positionCount ?? 0
        byteLimit = min(batch.limits.maxRetainedByteCount, surfacePlan?.nativePreparationByteLimit ?? batch.limits.maxRetainedByteCount)
        hasSectionedCameraGeometry = batch.labels.contains { $0.attachment == .sectionedGeometry }
            || batch.markers.contains { $0.attachment == .sectionedGeometry }
            || batch.cameraLines.contains { $0.attachment == .sectionedGeometry }
            || batch.cameraPaths.contains { $0.attachment == .sectionedGeometry }
        scaleReadout = nil
    }

    static func prepare(batch: RealityViewportSpatialBatch,
                        surfacePlan: MeshSourcePresentationRenderPlan? = nil) async throws -> RealityViewportSpatialResources {
        try Task.checkCancellation()
        try batch.validate(surfacePlan: surfacePlan)
        let result = RealityViewportSpatialResources(batch: batch, surfacePlan: surfacePlan)
        if batch.includesGrid {
            let capacity = ViewportProjectedGrid.maximumGridLineCount * 2
            let mesh = try LowLevelMesh(descriptor: descriptor(vertices: capacity, indices: capacity))
            // The SDK owns the fully initialized fixed-capacity grid buffers.
            // These bounded borrows never escape and updates retain their owner.
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                for index in 0..<capacity { vertices[index] = .zero }
            }
            mesh.withUnsafeMutableIndices { bytes in
                let indices = bytes.bindMemory(to: UInt32.self)
                for index in 0..<capacity { indices[index] = UInt32(index) }
            }
            mesh.parts.replaceAll((0..<3).map {
                .init(indexCount: 0, topology: .line, materialIndex: $0,
                      bounds: .init(min: .zero, max: .zero))
            })
            let resource = try await MeshResource(from: mesh)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [
                material([1, 1, 1, 0.055], depth: .scene),
                material([1, 1, 1, 0.135], depth: .scene),
                material([1, 1, 1, 0.22], depth: .scene)
            ])
            entity.isEnabled = false
            result.grid = (entity, mesh)
            result.root.addChild(entity)
        }
        if let placement = batch.gridPlacement {
            let mesh = try LowLevelMesh(descriptor: descriptor(vertices: 4, indices: 8))
            // Fixed unit rectangle; the native entity transform owns its world size.
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                vertices[0] = [-0.5, -0.5, 0]; vertices[1] = [0.5, -0.5, 0]
                vertices[2] = [0.5, 0.5, 0]; vertices[3] = [-0.5, 0.5, 0]
            }
            mesh.withUnsafeMutableIndices { bytes in
                let indices = bytes.bindMemory(to: UInt32.self)
                for edge in 0..<4 {
                    indices[edge * 2] = UInt32(edge)
                    indices[edge * 2 + 1] = UInt32((edge + 1) % 4)
                }
            }
            mesh.parts.replaceAll([.init(indexCount: 8, topology: .line, materialIndex: 0,
                                         bounds: .init(min: [-0.5, -0.5, 0], max: [0.5, 0.5, 0]))])
            let resource = try await MeshResource(from: mesh)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [material(placement.color, depth: .annotation)])
            entity.isEnabled = false
            result.gridPlacement = entity
            result.root.addChild(entity)
        }
        var pathResources: [CGPath: MeshResource] = [:]
        var textResources: [String: MeshResource] = [:]
        pathResources.reserveCapacity(batch.paths.count + batch.cameraPaths.count)
        let rulerLabelCount = ViewportMeasurementRulerAxis.allCases.reduce(0) {
            $0 + (batch.boundsRulers?.input.labels[$1] == nil ? 0 : 1)
        }
        textResources.reserveCapacity(batch.labels.count + rulerLabelCount)
        var groups: [WorldGroup] = []
        // ponytail: linear grouping is bounded by the admitted 640 descriptors;
        // use a keyed index only if preparation profiling makes this a bottleneck.
        for (index, source) in batch.meshes.enumerated() {
            try Task.checkCancellation()
            if let group = groups.firstIndex(where: {
                $0.attachment == source.attachment && $0.handleIndex == source.handleIndex
            }) {
                groups[group].meshIndices.append(index)
            } else {
                groups.append(.init(attachment: source.attachment, handleIndex: source.handleIndex,
                                    meshIndices: [index]))
            }
        }
        for group in groups {
            let geometry = try await worldGeometry(batch, meshIndices: group.meshIndices)
            try Task.checkCancellation()
            let mesh = try LowLevelMesh(descriptor: descriptor(vertices: geometry.positions.count, indices: geometry.indices.count))
            // All conversion and bounds work ran off MainActor. The SDK-owned
            // buffers receive two admitted bulk copies through nonescaping borrows.
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { destination in
                geometry.positions.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            mesh.withUnsafeMutableIndices { destination in
                geometry.indices.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            mesh.parts.replaceAll(geometry.parts)
            let resource = try await MeshResource(from: mesh)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: geometry.appearances.map { material($0.color, depth: $0.depth) })
            result.register(entity, handleIndex: group.handleIndex)
            result.root(for: group.attachment).addChild(entity)
        }
        for path in batch.paths {
            try Task.checkCancellation()
            let resource = try await pathResource(planarPath(path), cache: &pathResources)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [material(path.color, depth: path.depth)])
            entity.position = try RealityViewportSpatialBatch.nativePoint(path.origin, relativeTo: batch.renderOrigin)
            orient(entity, on: path)
            result.register(entity, handleIndex: path.handleIndex)
            result.root(for: path.attachment).addChild(entity)
        }
        for label in batch.labels {
            try Task.checkCancellation()
            let resource = try await textResource(label.text, cache: &textResources)
            try Task.checkCancellation()
            let glyph = ModelEntity(mesh: resource, materials: [material(label.color, depth: label.depth)])
            let bounds = resource.bounds
            switch label.alignment {
            case .leading: glyph.position.x = -bounds.min.x
            case .center: glyph.position.x = -bounds.center.x
            case .trailing: glyph.position.x = -bounds.max.x
            }
            let entity = Entity()
            entity.addChild(glyph)
            entity.components.set(BillboardComponent())
            entity.isEnabled = false
            result.labels.append((entity, label))
            result.register(entity, handleIndex: label.handleIndex)
            result.root(for: label.attachment).addChild(entity)
        }
        var sphere: MeshResource?
        var box: MeshResource?
        for marker in batch.markers {
            try Task.checkCancellation()
            let mesh: MeshResource
            switch marker.shape {
            case .sphere:
                if sphere == nil { sphere = .generateSphere(radius: 0.5) }
                guard let sphere else { throw RealityViewportSpatialBatch.invalid("Native marker resource is unavailable.") }
                mesh = sphere
            case .box:
                if box == nil { box = .generateBox(size: 1) }
                guard let box else { throw RealityViewportSpatialBatch.invalid("Native marker resource is unavailable.") }
                mesh = box
            }
            let entity = ModelEntity(mesh: mesh, materials: [material(marker.color, depth: marker.depth)])
            entity.position = try RealityViewportSpatialBatch.nativePoint(marker.anchor, relativeTo: batch.renderOrigin)
            entity.isEnabled = false
            result.markers.append((entity, marker))
            result.register(entity, handleIndex: marker.handleIndex)
            result.root(for: marker.attachment).addChild(entity)
        }
        for line in batch.cameraLines {
            try Task.checkCancellation()
            let count = line.points.count
            let mesh = try LowLevelMesh(descriptor: descriptor(vertices: count, indices: (count - 1) * 2))
            // RealityKit owns these fixed-capacity buffers. Every vertex and index
            // is initialized before conversion; scoped pointers never escape.
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                for index in 0..<count { vertices[index] = .zero }
            }
            mesh.withUnsafeMutableIndices { bytes in
                let indices = bytes.bindMemory(to: UInt32.self)
                for index in 0..<(count - 1) {
                    indices[2 * index] = UInt32(index)
                    indices[2 * index + 1] = UInt32(index + 1)
                }
            }
            mesh.parts.replaceAll([.init(indexCount: (count - 1) * 2, topology: .line, bounds: .init(min: .zero, max: .zero))])
            let resource = try await MeshResource(from: mesh)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [material(line.color, depth: line.depth)])
            entity.isEnabled = false
            result.cameraLines.append((entity, mesh, line))
            result.register(entity, handleIndex: line.handleIndex)
            result.root(for: line.attachment).addChild(entity)
        }
        for path in batch.cameraPaths {
            try Task.checkCancellation()
            let resource = try await pathResource(path.path.applying(.init(scaleX: 1, y: -1)), cache: &pathResources)
            try Task.checkCancellation()
            let entity = ModelEntity(mesh: resource, materials: [material(path.color, depth: path.depth)])
            entity.components.set(BillboardComponent())
            entity.isEnabled = false
            result.cameraPaths.append((entity, path))
            result.register(entity, handleIndex: path.handleIndex)
            result.root(for: path.attachment).addChild(entity)
        }
        if let group = batch.boundsRulers {
            for axis in ViewportMeasurementRulerAxis.allCases {
                guard let text = group.input.labels[axis] else { continue }
                let resource = try await textResource(text, cache: &textResources)
                let glyph = ModelEntity(mesh: resource, materials: [material(group.color, depth: .annotation)])
                glyph.position.x = -resource.bounds.center.x
                glyph.position.y = -resource.bounds.center.y
                let label = Entity()
                label.addChild(glyph)
                label.components.set(BillboardComponent())
                label.isEnabled = false
                let mesh = try LowLevelMesh(descriptor: descriptor(vertices: 6, indices: 6))
                // Fixed native capacity, fully initialized before publication.
                // The SDK owns both buffers; these borrows do not escape.
                mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                    let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                    for index in 0..<6 { vertices[index] = .zero }
                }
                mesh.withUnsafeMutableIndices { bytes in
                    let indices = bytes.bindMemory(to: UInt32.self)
                    for index in 0..<6 { indices[index] = UInt32(index) }
                }
                mesh.parts.replaceAll([.init(indexCount: 6, topology: .line, bounds: .init(min: .zero, max: .zero))])
                let lineResource = try await MeshResource(from: mesh)
                try Task.checkCancellation()
                let line = ModelEntity(mesh: lineResource, materials: [material(group.color, depth: .annotation)])
                line.isEnabled = false
                result.root.addChild(label)
                result.root.addChild(line)
                result.boundsRulers.append((axis, label, line, mesh))
                result.disabledRulerAxes.insert(axis)
            }
        }
        try Task.checkCancellation()
        return result
    }

    /// Native world geometry remains untouched. Only the already admitted
    /// camera-relative annotations change, synchronously with the mounted camera.
    @discardableResult
    func updateCamera(camera: Entity, content: RealityViewCameraContent,
                      safeRect: CGRect = .zero, excludedRects: [CGRect] = [],
                      gridRuler: RulerConfiguration? = nil, gridBasis: ViewportProjectionBasis = .isometric,
                      gridSize: CGSize = .zero, gridSpacing: ViewportGridVisualSpacingMode = .adaptive) throws -> MeshSourcePresentationRenderError? {
        guard grid != nil || !cameraPaths.isEmpty || !labels.isEmpty || !markers.isEmpty || !cameraLines.isEmpty || !boundsRulers.isEmpty else { return nil }
        guard let projection = cameraProjection(camera: camera, content: content) else {
            for (entity, _) in cameraPaths { entity.isEnabled = false }
            for (entity, _) in labels { entity.isEnabled = false }
            for (entity, _) in markers { entity.isEnabled = false }
            for (entity, _, _) in cameraLines { entity.isEnabled = false }
            for (axis, label, line, _) in boundsRulers {
                label.isEnabled = false; line.isEnabled = false; disabledRulerAxes.insert(axis)
            }
            hideGrid()
            throw CameraReadinessError.projectionUnavailable
        }
        for (entity, path) in cameraPaths {
            guard let placement = placement(anchor: path.anchor, offset: path.offset, projection: projection) else {
                entity.isEnabled = false
                continue
            }
            entity.position = placement.position
            entity.scale = SIMD3(repeating: placement.metersPerPoint)
            entity.isEnabled = true
        }
        for (entity, label) in labels {
            guard let placement = placement(anchor: label.anchor, offset: label.offset, projection: projection) else {
                entity.isEnabled = false
                continue
            }
            entity.position = placement.position
            entity.scale = SIMD3(repeating: placement.metersPerPoint * label.heightPoints)
            entity.isEnabled = true
        }
        for (entity, marker) in markers {
            guard let placement = placement(anchor: marker.anchor, offset: .zero, projection: projection) else {
                entity.isEnabled = false
                continue
            }
            entity.scale = SIMD3(repeating: placement.metersPerPoint * marker.diameterPoints)
            entity.isEnabled = true
        }
        for (entity, mesh, line) in cameraLines {
            var valid = true
            var bounds = BoundingBox()
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                for (index, point) in line.points.enumerated() {
                    guard let placement = placement(anchor: point.anchor, offset: point.offset, projection: projection) else {
                        valid = false
                        vertices[index] = .zero
                        continue
                    }
                    vertices[index] = placement.position
                    bounds.formUnion(BoundingBox(min: placement.position, max: placement.position))
                }
            }
            if valid {
                // Mutate one native part; do not allocate a replacement mesh or array.
                var part = mesh.parts[0]
                part.bounds = bounds
                mesh.parts[0] = part
            }
            entity.isEnabled = valid
        }
        try updateBoundsRulers(projection: projection, safeRect: safeRect, excludedRects: excludedRects)
        do {
            if let gridRuler {
                guard grid != nil else { throw RealityViewportSpatialBatch.invalid("The mounted frame did not admit a grid.") }
                let remaining = batch.limits.maxItemCount - batch.itemCount - surfaceItemCount
                guard excludedRects.count <= remaining else { throw RealityViewportSpatialBatch.exhausted() }
                let plane = ViewportCanvasPlane.displayed(for: gridBasis)
                var scaleAnchor: Point3D?
                for screen in [CGPoint(x: gridSize.width / 2, y: gridSize.height / 2), .zero,
                               CGPoint(x: gridSize.width, y: 0), CGPoint(x: 0, y: gridSize.height),
                               CGPoint(x: gridSize.width, y: gridSize.height)] {
                    if let point = projection.unproject(screen, onto: plane, origin: batch.renderOrigin) {
                        scaleAnchor = point
                        break
                    }
                }
                guard let scaleAnchor else {
                    hideGrid()
                    return nil
                }
                let nativeAnchor = try RealityViewportSpatialBatch.nativePoint(scaleAnchor, relativeTo: batch.renderOrigin)
                let projectedScale = hypot(projection.forward.c, projection.forward.d)
                    / CGFloat(projection.depthScale(projection.local(nativeAnchor)))
                let frame = try ViewportProjectedGrid.makeNativeFrame(.init(
                    ruler: gridRuler, basis: gridBasis, viewportSize: gridSize,
                    projectedScale: projectedScale,
                    project: { point in
                        let relative = SIMD3(Float(point.x - self.batch.renderOrigin.x),
                                             Float(point.y - self.batch.renderOrigin.y), Float(point.z - self.batch.renderOrigin.z))
                        return projection.project(relative)
                    },
                    unproject: { projection.unproject($0, onto: $1, origin: self.batch.renderOrigin) },
                    chromeExclusionRects: excludedRects, visualSpacingMode: gridSpacing
                ))
                if let frame {
                    try updateGrid(frame, projection: projection)
                } else {
                    hideGrid()
                }
            } else {
                hideGrid()
            }
        } catch let error as MeshSourcePresentationRenderError {
            return error
        } catch {
            return RealityViewportSpatialBatch.invalid("Native grid frame failed: \(error)")
        }
        return nil
    }

    private func hideGrid() {
        scaleReadout = nil
        grid?.entity.isEnabled = false
        gridPlacement?.isEnabled = false
        for label in gridLabels {
            label.components.remove(TextComponent.self)
            label.isEnabled = false
        }
    }

    private func updateGrid(_ frame: ViewportProjectedGrid.NativeFrame, projection: CameraProjection) throws {
        guard let grid, frame.worldLines.count <= ViewportProjectedGrid.maximumGridLineCount else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        let placementTransform = try batch.gridPlacement?.transform(
            minorStepMeters: frame.minorStepMeters, renderOrigin: batch.renderOrigin
        )
        let slotCount = max(gridLabels.count, frame.screenLabels.count)
        guard slotCount <= batch.limits.maxItemCount - batch.itemCount - surfaceItemCount else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        var byteCount = batch.admittedByteCount
        var positionCount = batch.positionCount + surfacePositionCount
        func charge(_ count: Int, _ stride: Int) throws {
            let size = count.multipliedReportingOverflow(by: stride)
            let sum = byteCount.addingReportingOverflow(size.partialValue)
            guard !size.overflow, !sum.overflow, sum.partialValue <= byteLimit else {
                throw RealityViewportSpatialBatch.exhausted()
            }
            byteCount = sum.partialValue
        }
        try charge(slotCount, MemoryLayout<Entity>.stride + MemoryLayout<TextComponent>.stride)
        try charge(frame.worldLines.count, MemoryLayout<ViewportProjectedGrid.NativeFrame.WorldLine>.stride + 2 * MemoryLayout<SIMD3<Float>>.stride)
        try charge(frame.screenLabels.count, MemoryLayout<ViewportProjectedGrid.NativeFrame.ScreenLabel>.stride)
        try charge(frame.screenLabels.count, MemoryLayout<(TextComponent, SIMD3<Float>)>.stride)
        for label in frame.screenLabels {
            guard !label.text.isEmpty, label.position.x.isFinite, label.position.y.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Grid label has invalid text or placement.")
            }
            try charge(label.text.utf8.count, 4)
            let count = positionCount.addingReportingOverflow(label.text.unicodeScalars.count)
            guard !count.overflow, count.partialValue <= batch.limits.maxPositionCount else {
                throw RealityViewportSpatialBatch.exhausted()
            }
            positionCount = count.partialValue
        }
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(frame.worldLines.count * 2)
        var parts: [LowLevelMesh.Part] = []
        for style in 0..<3 {
            let start = vertices.count
            var bounds = BoundingBox()
            for line in frame.worldLines where (line.isOrigin ? 2 : (line.isMajor ? 1 : 0)) == style {
                let start = try RealityViewportSpatialBatch.nativePoint(line.start, relativeTo: batch.renderOrigin)
                let end = try RealityViewportSpatialBatch.nativePoint(line.end, relativeTo: batch.renderOrigin)
                bounds.formUnion(.init(min: simd_min(start, end), max: simd_max(start, end)))
                vertices.append(start)
                vertices.append(end)
            }
            parts.append(.init(indexOffset: start * MemoryLayout<UInt32>.stride,
                               indexCount: vertices.count - start, topology: .line, materialIndex: style,
                               bounds: vertices.count == start ? .init(min: .zero, max: .zero) : bounds))
        }
        let unitsPerPoint = projection.depthScale([0, 0, -projection.annotationDepth])
            / Float(hypot(projection.forward.c, projection.forward.d))
        guard unitsPerPoint.isFinite, unitsPerPoint > 0 else {
            throw RealityViewportSpatialBatch.invalid("Grid text has no finite native point scale.")
        }
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        var text: [(TextComponent, SIMD3<Float>)] = []
        text.reserveCapacity(frame.screenLabels.count)
        for label in frame.screenLabels {
            let attributed = NSAttributedString(string: label.text, attributes: [
                .font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.42)
            ])
            let size = attributed.size()
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
                throw RealityViewportSpatialBatch.invalid("Native grid text has invalid measured bounds.")
            }
            var component = TextComponent()
            component.size = CGSize(width: ceil(size.width) + 2, height: ceil(size.height) + 2)
            component.text = AttributedString(attributed)
            let point = projection.point(at: label.position, depth: projection.annotationDepth)
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Native grid label position exceeds precision.")
            }
            text.append((component, point))
        }
        // Every fallible conversion and aggregate admission finished above. The
        // following synchronous publication changes the complete grid together.
        while gridLabels.count < slotCount {
            let label = Entity()
            label.isEnabled = false
            root.addChild(label)
            gridLabels.append(label)
        }
        grid.mesh.withUnsafeMutableBytes(bufferIndex: 0) { destination in
            vertices.withUnsafeBytes { source in destination.copyMemory(from: source) }
        }
        for index in 0..<3 { grid.mesh.parts[index] = parts[index] }
        grid.entity.isEnabled = !vertices.isEmpty
        if let placementTransform {
            gridPlacement?.transform = Transform(matrix: placementTransform)
            gridPlacement?.isEnabled = true
        }
        for (index, label) in gridLabels.enumerated() {
            guard text.indices.contains(index) else {
                label.components.remove(TextComponent.self)
                label.isEnabled = false
                continue
            }
            let (component, position) = text[index]
            let existing = label.components[TextComponent.self]
            if existing?.text != component.text || existing?.size != component.size {
                label.components.set(component)
            }
            label.position = position
            label.orientation = simd_quatf(projection.worldFromCamera)
            // TextComponent's native plane uses typographic points (1/72 inch).
            label.scale = .init(repeating: unitsPerPoint * 72 / 0.0254)
            label.isEnabled = true
        }
        scaleReadout = frame.scaleReadout
    }

    private func updateBoundsRulers(projection: CameraProjection,
                                    safeRect: CGRect, excludedRects: [CGRect]) throws {
        guard let group = batch.boundsRulers else { return }
        for (axis, label, line, _) in boundsRulers {
            label.isEnabled = false
            line.isEnabled = false
            disabledRulerAxes.insert(axis)
        }
        guard excludedRects.count <= batch.limits.maxItemCount - batch.itemCount else {
            throw MeshSourcePresentationRenderError(code: .resourceExhausted,
                message: "Current chrome exclusions exceed bounds ruler placement admission.")
        }
        let layout = ViewportMeasurementBoundsRulerLayout().placement(
            for: group.input.bounds, labels: group.input.labels,
            project: { point in
                do {
                    let native = try RealityViewportSpatialBatch.nativePoint(point, relativeTo: self.batch.renderOrigin)
                    return projection.project(native)
                } catch { return nil }
            }, safeRect: safeRect, excludedRects: excludedRects)
        disabledRulerAxes = layout.disabledAxes
        for ruler in layout.rulers {
            guard let (_, label, line, mesh) = boundsRulers.first(where: { $0.0 == ruler.axis }) else {
                throw RealityViewportSpatialBatch.invalid("Bounds ruler placement references an unprepared axis.")
            }
            let start = ruler.worldExtensionStart
            let end = ruler.worldExtensionEnd
            // Screen center is placed at the actual edge midpoint's depth.
            let midpoint = Point3D(x: start.x * 0.5 + end.x * 0.5,
                                   y: start.y * 0.5 + end.y * 0.5,
                                   z: start.z * 0.5 + end.z * 0.5)
            let nativeMidpoint = try RealityViewportSpatialBatch.nativePoint(midpoint, relativeTo: batch.renderOrigin)
            guard let projected = projection.project(nativeMidpoint),
                  let labelPlacement = placement(anchor: midpoint,
                    offset: .fixed(CGPoint(x: ruler.labelRect.midX - projected.x, y: ruler.labelRect.midY - projected.y)),
                    projection: projection) else {
                disabledRulerAxes.insert(ruler.axis)
                continue
            }
            var valid = true
            var bounds = BoundingBox()
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
                let vertices = bytes.bindMemory(to: SIMD3<Float>.self)
                for index in 0..<6 {
                    let anchor = index < 2 || index == 4 ? start : end
                    let offset = index == 0 || index == 2 ? CGPoint.zero : ruler.dimensionOffset
                    guard let value = placement(anchor: anchor, offset: .fixed(offset), projection: projection) else {
                        vertices[index] = .zero
                        valid = false
                        continue
                    }
                    vertices[index] = value.position
                    bounds.formUnion(.init(min: value.position, max: value.position))
                }
            }
            guard valid else { disabledRulerAxes.insert(ruler.axis); continue }
            var part = mesh.parts[0]
            part.bounds = bounds
            mesh.parts[0] = part
            label.position = labelPlacement.position
            label.scale = SIMD3(repeating: labelPlacement.metersPerPoint * group.heightPoints)
            label.isEnabled = true
            line.isEnabled = true
        }
    }

    private static func textResource(_ value: String, cache: inout [String: MeshResource]) async throws -> MeshResource {
        try Task.checkCancellation()
        if let existing = cache[value] { return existing }
        var text = AttributedString(value)
        text.font = NSFont.monospacedSystemFont(ofSize: 1, weight: .medium)
        var extrusion = MeshResource.ShapeExtrusionOptions()
        extrusion.extrusionMethod = .linear(depth: 0)
        let resource = try await MeshResource(extruding: text, extrusionOptions: extrusion)
        try Task.checkCancellation()
        cache[value] = resource
        return resource
    }

    private func root(for attachment: RealityViewportSpatialBatch.Attachment) -> Entity {
        attachment == .world ? root : sectionedRoot
    }

    @concurrent
    private nonisolated static func worldGeometry(
        _ batch: RealityViewportSpatialBatch, meshIndices: [Int]
    ) async throws -> WorldGeometry {
        let vertexCount = meshIndices.reduce(0) { $0 + batch.meshes[$1].positions.count }
        let indexCount = meshIndices.reduce(0) { $0 + batch.meshes[$1].indices.count }
        let meshCount = meshIndices.count
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var appearances: [RealityViewportSpatialBatch.Appearance] = []
        var parts: [LowLevelMesh.Part] = []
        positions.reserveCapacity(vertexCount)
        indices.reserveCapacity(indexCount)
        appearances.reserveCapacity(meshCount)
        parts.reserveCapacity(meshCount)
        var vertexOffset = 0
        var indexOffset = 0
        for sourceIndex in meshIndices {
            let geometry = batch.meshes[sourceIndex]
            try Task.checkCancellation()
            let materialIndex: Int
            let appearance = RealityViewportSpatialBatch.Appearance(color: geometry.color, depth: geometry.depth)
            if let existing = appearances.firstIndex(of: appearance) {
                materialIndex = existing
            } else {
                materialIndex = appearances.count
                appearances.append(appearance)
            }
            var bounds = BoundingBox()
            for point in geometry.positions {
                try Task.checkCancellation()
                let value = try RealityViewportSpatialBatch.nativePoint(point, relativeTo: batch.renderOrigin)
                positions.append(value)
                bounds.formUnion(BoundingBox(min: value, max: value))
            }
            for value in geometry.indices {
                try Task.checkCancellation()
                indices.append(UInt32(vertexOffset) + value)
            }
            parts.append(.init(indexOffset: indexOffset * MemoryLayout<UInt32>.stride,
                               indexCount: geometry.indices.count,
                               topology: geometry.topology == .lines ? .line : .triangle,
                               materialIndex: materialIndex, bounds: bounds))
            vertexOffset += geometry.positions.count
            indexOffset += geometry.indices.count
        }
        return WorldGeometry(positions: positions, indices: indices, parts: parts, appearances: appearances)
    }

    private func cameraProjection(camera: Entity, content: RealityViewCameraContent) -> CameraProjection? {
        let orthographic = camera.components[OrthographicCameraComponent.self]
        let perspective = camera.components[PerspectiveCameraComponent.self]
        guard (orthographic != nil) != (perspective != nil) else { return nil }
        let near: Float
        let far: Float
        if let orthographic { near = orthographic.near; far = orthographic.far }
        else if let perspective { near = perspective.near; far = perspective.far }
        else { return nil }
        guard near.isFinite, near > 0, far > near,
              orthographic == nil || far.isFinite else { return nil }
        let depth = Float(min((Double(near) + Double(far)) / 2, max(Double(near) * 2, 1)))
        let step = orthographic?.scale ?? depth
        guard depth.isFinite, depth > 0, step.isFinite, step > 0 else { return nil }
        func project(_ local: SIMD3<Float>) -> CGPoint? {
            content.project(point: camera.convert(position: local, to: nil), to: .local)
        }
        guard let a = project([0, 0, -depth]), let b = project([step, 0, -depth]),
              let c = project([0, step, -depth]), a.x.isFinite, a.y.isFinite,
              b.x.isFinite, b.y.isFinite, c.x.isFinite, c.y.isFinite else { return nil }
        let mapping = CGAffineTransform(a: (b.x - a.x) / CGFloat(step), b: (b.y - a.y) / CGFloat(step),
                                        c: (c.x - a.x) / CGFloat(step), d: (c.y - a.y) / CGFloat(step), tx: a.x, ty: a.y)
        let determinant = mapping.a * mapping.d - mapping.b * mapping.c
        guard determinant.isFinite, determinant != 0 else { return nil }
        var offsetMapping = mapping
        offsetMapping.tx = 0; offsetMapping.ty = 0
        let transform = camera.transformMatrix(relativeTo: nil)
        return CameraProjection(worldFromCamera: transform, cameraFromWorld: simd_inverse(transform),
                                forward: mapping, inverseOffset: offsetMapping.inverted(),
                                sampleDepth: depth, perspective: perspective != nil, annotationDepth: near * 1.01)
    }

    private func placement(anchor: Point3D, offset: RealityViewportSpatialBatch.Offset,
                           projection: CameraProjection) -> (position: SIMD3<Float>, metersPerPoint: Float)? {
        let point: SIMD3<Float>
        do { point = try RealityViewportSpatialBatch.nativePoint(anchor, relativeTo: batch.renderOrigin) }
        catch { return nil }
        let local = projection.local(point)
        guard local.x.isFinite, local.y.isFinite, local.z.isFinite, local.z < 0 else { return nil }
        let screenOffset: CGPoint
        switch offset {
        case .fixed(let value): screenOffset = value
        case .directed(let toward, let parallel, let perpendicular),
             .projected(let toward, _, let parallel, let perpendicular):
            let target: SIMD3<Float>
            do { target = try RealityViewportSpatialBatch.nativePoint(toward, relativeTo: batch.renderOrigin) }
            catch { return nil }
            guard let a = projection.project(point), let b = projection.project(target) else { return nil }
            let dx = b.x - a.x, dy = b.y - a.y
            let length = hypot(dx, dy)
            guard length.isFinite, length > 0 else { return nil }
            let distance: CGFloat
            if case .projected(_, let minimumLength, _, _) = offset {
                distance = max(length, minimumLength) + parallel
            } else {
                distance = parallel
            }
            screenOffset = CGPoint(x: (dx * distance - dy * perpendicular) / length,
                                   y: (dy * distance + dx * perpendicular) / length)
        }
        let delta = screenOffset.applying(projection.inverseOffset)
        let depthScale = projection.depthScale(local)
        let world = projection.worldFromCamera * SIMD4(local + SIMD3(Float(delta.x) * depthScale, Float(delta.y) * depthScale, 0), 1)
        let scale = depthScale / Float(hypot(projection.forward.c, projection.forward.d))
        guard world.x.isFinite, world.y.isFinite, world.z.isFinite, scale.isFinite, scale > 0 else { return nil }
        return (SIMD3(world.x, world.y, world.z), scale)
    }

    private static func descriptor(vertices: Int, indices: Int) -> LowLevelMesh.Descriptor {
        .init(vertexCapacity: vertices,
              vertexAttributes: [.init(semantic: .position, format: .float3, offset: 0)],
              vertexLayouts: [.init(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride)],
              indexCapacity: indices, indexType: .uint32)
    }

    private static func planarPath(_ path: RealityViewportSpatialBatch.PlanarPath) -> Path {
        let right = simd_normalize(path.xAxis)
        let normal = simd_normalize(simd_cross(path.xAxis, path.yAxis))
        let up = simd_cross(normal, right)
        return path.path.applying(CGAffineTransform(
            a: simd_dot(path.xAxis, right), b: 0,
            c: simd_dot(path.yAxis, right), d: simd_dot(path.yAxis, up), tx: 0, ty: 0
        ))
    }

    private static func pathResource(_ path: Path, cache: inout [CGPath: MeshResource]) async throws -> MeshResource {
        let key = path.cgPath
        if let existing = cache[key] { return existing }
        var extrusion = MeshResource.ShapeExtrusionOptions()
        extrusion.extrusionMethod = .linear(depth: 0)
        let resource = try await MeshResource(extruding: path, extrusionOptions: extrusion)
        try Task.checkCancellation()
        cache[key] = resource
        return resource
    }

    private static func orient(_ entity: Entity, on path: RealityViewportSpatialBatch.PlanarPath) {
        let right = simd_normalize(path.xAxis)
        let normal = simd_normalize(simd_cross(path.xAxis, path.yAxis))
        let up = simd_cross(normal, right)
        entity.orientation = simd_quatf(simd_float3x3(SIMD3<Float>(right), SIMD3<Float>(up), SIMD3<Float>(normal)))
    }

    private static func material(_ color: SIMD4<Float>, depth: RealityViewportSpatialBatch.Depth) -> UnlitMaterial {
        var material = UnlitMaterial(color: NSColor(red: CGFloat(color.x), green: CGFloat(color.y),
                                                   blue: CGFloat(color.z), alpha: CGFloat(color.w)))
        material.faceCulling = .none
        material.readsDepth = depth == .scene
        material.writesDepth = depth == .scene && color.w == 1
        if color.w < 1 { material.blending = .transparent(opacity: .init(scale: 1)) }
        return material
    }
}
