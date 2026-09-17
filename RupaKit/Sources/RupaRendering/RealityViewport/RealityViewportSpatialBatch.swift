import CoreGraphics
import Foundation
import RealityKit
import RupaCoreTypes
import SwiftCAD
import SwiftUI
import simd

/// Immutable world geometry. Admission never changes the requested content.
struct RealityViewportSpatialBatch: Sendable {
    enum Topology: Sendable { case lines, triangles }
    enum Depth: Sendable, Hashable { case scene, annotation }
    enum Attachment: Sendable, CaseIterable, Hashable { case world, sectionedGeometry }

    struct Appearance: Equatable, Sendable {
        let color: SIMD4<Float>
        let depth: Depth
    }

    enum Offset: Sendable {
        case fixed(CGPoint)
        case directed(toward: Point3D, parallel: CGFloat, perpendicular: CGFloat)
        case projected(toward: Point3D, minimumLength: CGFloat, parallel: CGFloat, perpendicular: CGFloat)
        /// A source-owned world direction advanced by a screen length, resolved
        /// in native scene space rather than in the camera plane at the
        /// anchor's depth.
        ///
        /// The other cases normalize a screen direction before applying their
        /// point distances, which makes every projected direction the same
        /// length on screen. That is correct for an arrow the reader follows
        /// but wrong for a source direction whose foreshortening carries
        /// meaning, such as a rotation ring that must stay an ellipse in the
        /// plane it rotates about. This case keeps the world direction and
        /// converts only the length, so the projected extent is bounded by
        /// `lengthPoints` and independent of model size and zoom while the
        /// camera keeps its own foreshortening.
        case worldDirected(along: Vector3D, lengthPoints: CGFloat)

        static var zero: Self { .fixed(.zero) }
    }

    struct Mesh: Sendable {
        let positions: [Point3D]
        let indices: [UInt32]
        let topology: Topology
        let color: SIMD4<Float>
        var depth: Depth = .scene
        var attachment: Attachment = .world
        var handleIndex: UInt32? = nil
        var hitTolerancePoints: Float? = nil
    }

    struct PlanarPath: Sendable {
        let path: Path
        let origin: Point3D
        let xAxis: SIMD3<Double>
        let yAxis: SIMD3<Double>
        let color: SIMD4<Float>
        var depth: Depth = .scene
        var attachment: Attachment = .world
        var handleIndex: UInt32? = nil
        var hitTolerancePoints: Float? = nil
    }

    struct Label: Sendable {
        enum Alignment: Sendable { case leading, center, trailing }
        let text: String
        let anchor: Point3D
        let offset: Offset
        let heightPoints: Float
        let color: SIMD4<Float>
        var alignment: Alignment = .leading
        var depth: Depth = .annotation
        var attachment: Attachment = .world
        var handleIndex: UInt32? = nil
        var hitRectPoints: CGRect? = nil
    }

    struct Marker: Sendable {
        enum Shape: Sendable { case sphere, box, cone }
        let shape: Shape
        let anchor: Point3D
        let diameterPoints: Float
        let color: SIMD4<Float>
        var depth: Depth = .annotation
        var attachment: Attachment = .world
        var handleIndex: UInt32? = nil
        var hitTolerancePoints: Float? = nil
        /// Placement relative to `anchor`, resolved by the mounted camera on
        /// every update together with the marker's point diameter.
        var offset: Offset = .zero
    }

    /// Native filled/stroked Path coordinates are screen points about this world anchor.
    struct CameraPath: Sendable {
        let path: Path
        let anchor: Point3D
        let offset: Offset
        let color: SIMD4<Float>
        var depth: Depth = .annotation
        var attachment: Attachment = .world
        var handleIndex: UInt32? = nil
        var hitTolerancePoints: Float? = nil
    }

    /// A screen offset at an explicit world anchor's depth, never guessed depth.
    struct CameraPoint: Sendable {
        let anchor: Point3D
        let offset: Offset
    }

    struct CameraLine: Sendable {
        let points: [CameraPoint]
        let color: SIMD4<Float>
        var widthPoints: Float? = nil
        var depth: Depth = .annotation
        var attachment: Attachment = .world
        var handleIndex: UInt32? = nil
        var hitTolerancePoints: Float? = nil
    }

    struct BoundsRulers: Sendable {
        let input: ViewportMeasurementBoundsRulerInput
        let heightPoints: Float
        let color: SIMD4<Float>
    }

    /// Missing dimensions consume the current native grid step, not a captured camera value.
    struct GridPlacement: Sendable {
        let center: Point3D
        let uAxis: SIMD3<Double>
        let vAxis: SIMD3<Double>
        let widthMeters: Double?
        let heightMeters: Double?
        let color: SIMD4<Float>

        func transform(minorStepMeters: Double, renderOrigin: Point3D) throws -> simd_float4x4 {
            let width = Float(widthMeters ?? minorStepMeters)
            let height = Float(heightMeters ?? minorStepMeters)
            guard width.isFinite, height.isFinite, width > 0, height > 0 else {
                throw RealityViewportSpatialBatch.invalid("Grid placement dimensions exceed native precision.")
            }
            let center = try RealityViewportSpatialBatch.nativePoint(center, relativeTo: renderOrigin)
            let matrix = simd_float4x4(columns: (
                SIMD4(SIMD3<Float>(uAxis) * width, 0),
                SIMD4(SIMD3<Float>(vAxis) * height, 0),
                SIMD4(SIMD3<Float>(simd_cross(uAxis, vAxis)), 0),
                SIMD4(center, 1)
            ))
            for index in 0..<4 {
                let corner = matrix * SIMD4<Float>(index & 1 == 0 ? -0.5 : 0.5,
                                                   index & 2 == 0 ? -0.5 : 0.5, 0, 1)
                guard corner.x.isFinite, corner.y.isFinite, corner.z.isFinite else {
                    throw RealityViewportSpatialBatch.invalid("Grid placement bounds exceed native precision.")
                }
            }
            return matrix
        }
    }

    let meshes: [Mesh]
    let paths: [PlanarPath]
    let labels: [Label]
    let markers: [Marker]
    let cameraLines: [CameraLine]
    let cameraPaths: [CameraPath]
    let boundsRulers: BoundsRulers?
    let includesGrid: Bool
    let includesAxes: Bool
    let gridPlacement: GridPlacement?
    let handleCount: Int
    let lineCollisionCount: Int
    let renderOrigin: Point3D
    let admittedByteCount: Int
    let retainedSurfaceByteCount: Int
    let retainedSemanticByteCount: Int
    let itemCount: Int
    let positionCount: Int
    let triangleCount: Int
    let limits: MeshSourcePresentationPlanLimits

    init(
        meshes: [Mesh] = [], paths: [PlanarPath] = [], labels: [Label] = [],
        markers: [Marker] = [], cameraLines: [CameraLine] = [], cameraPaths: [CameraPath] = [],
        boundsRulers: BoundsRulers? = nil,
        includesGrid: Bool = false,
        includesAxes: Bool = false,
        gridPlacement: GridPlacement? = nil,
        handleCount: Int = 0,
        retainedSemanticByteCount: Int = 0,
        renderOrigin: Point3D, retainedSurfaceByteCount: Int,
        limits: MeshSourcePresentationPlanLimits = .standard
    ) throws {
        try limits.validate()
        guard handleCount >= 0 else { throw Self.invalid("Spatial handle count is negative.") }
        guard handleCount <= limits.maxItemCount else { throw Self.exhausted() }
        guard renderOrigin.isFinite, retainedSurfaceByteCount >= 0, retainedSemanticByteCount >= 0 else {
            throw Self.invalid("Spatial overlay origin or retained surface charge is invalid.")
        }
        var bytes = retainedSurfaceByteCount
        var positionCount = 0
        var triangleCount = 0
        var itemCount = 0
        var handleFragmentCount = 0
        var markerCollisionCount = 0
        var labelCollisionCount = 0
        var lineCollisionCount = 0
        var labelCollisionResourceCharged = false
        func charge(_ count: Int, stride: Int) throws {
            let product = count.multipliedReportingOverflow(by: stride)
            let sum = bytes.addingReportingOverflow(product.partialValue)
            guard !product.overflow, !sum.overflow else { throw Self.exhausted() }
            bytes = sum.partialValue
            guard bytes <= limits.maxRetainedByteCount else { throw Self.exhausted() }
        }
        func positions(_ count: Int) throws {
            let sum = positionCount.addingReportingOverflow(count)
            guard !sum.overflow, sum.partialValue <= limits.maxPositionCount else { throw Self.exhausted() }
            positionCount = sum.partialValue
        }
        try charge(retainedSemanticByteCount, stride: 1)
        func item() throws {
            guard itemCount < limits.maxItemCount else { throw Self.exhausted() }
            itemCount += 1
        }
        func validateHandle(_ index: UInt32?) throws {
            guard let index else { return }
            guard Int(index) < handleCount else {
                throw Self.invalid("Spatial handle index is outside its frame identity table.")
            }
            handleFragmentCount += 1
        }
        func validateHitTolerance(_ value: Float?) throws {
            guard let value else { return }
            guard value.isFinite, value >= 0 else {
                throw Self.invalid("Spatial interaction tolerance is not finite or nonnegative.")
            }
        }
        func validateHitRect(_ value: CGRect?) throws {
            guard let value else { return }
            guard value.origin.x.isFinite, value.origin.y.isFinite,
                  value.size.width.isFinite, value.size.height.isFinite,
                  value.size.width > 0, value.size.height > 0,
                  value.minX.isFinite, value.minY.isFinite,
                  value.maxX.isFinite, value.maxY.isFinite else {
                throw Self.invalid("Spatial label interaction rectangle is invalid.")
            }
        }
        func validateOffset(_ offset: Offset) throws {
            if case .projected(_, let minimumLength, _, _) = offset {
                guard minimumLength.isFinite, minimumLength >= 0 else {
                    throw Self.invalid("Camera-relative minimum length is invalid.")
                }
            }
            switch offset {
            case .fixed(let point):
                guard point.x.isFinite, point.y.isFinite else {
                    throw Self.invalid("Camera-relative offset is not finite.")
                }
            case .directed(let toward, let parallel, let perpendicular),
                 .projected(let toward, _, let parallel, let perpendicular):
                try item()
                try positions(1)
                _ = try Self.nativePoint(toward, relativeTo: renderOrigin)
                guard parallel.isFinite, perpendicular.isFinite else {
                    throw Self.invalid("Camera-relative directional distances are not finite.")
                }
            case .worldDirected(let direction, let lengthPoints):
                // A world direction needs no second world point, so it charges
                // no additional item or position. Its length and non-degeneracy
                // are source properties the camera cannot repair, unlike a
                // behind-camera anchor, so both are refused at admission rather
                // than disabling the placement every frame.
                guard direction.isFinite, direction.length > 0 else {
                    throw Self.invalid("Camera-relative world direction is degenerate.")
                }
                guard lengthPoints.isFinite, lengthPoints >= 0 else {
                    throw Self.invalid("Camera-relative world length is invalid.")
                }
            }
        }
        try charge(1, stride: MemoryLayout<Self>.stride)
        if includesGrid {
            // Reserve the complete native grid capacity, not the current camera's
            // visible prefix. Camera updates cannot grow these native buffers.
            for _ in 0..<ViewportProjectedGrid.maximumGridLineCount { try item() }
            let capacity = ViewportProjectedGrid.maximumGridLineCount * 2
            try positions(capacity)
            try charge(capacity, stride: MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<UInt32>.stride)
            try charge(3, stride: MemoryLayout<LowLevelMesh.Part>.stride + MemoryLayout<UnlitMaterial>.stride)
            try charge(1, stride: MemoryLayout<(ModelEntity, LowLevelMesh)>.stride)
        }
        if includesAxes {
            // Three fixed two-vertex native line resources and three native
            // TextComponent label entities are admitted before allocation.
            for _ in 0..<6 { try item() }
            try positions(6)
            try charge(3, stride: MemoryLayout<LowLevelMesh.Part>.stride
                       + MemoryLayout<UnlitMaterial>.stride
                       + MemoryLayout<(ModelEntity, LowLevelMesh)>.stride)
            try charge(6, stride: MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<UInt32>.stride)
            try charge(3, stride: MemoryLayout<Entity>.stride + MemoryLayout<TextComponent>.stride)
            try charge(3, stride: MemoryLayout<String>.stride)
        }
        if let placement = gridPlacement {
            guard includesGrid, placement.widthMeters == nil || placement.heightMeters == nil,
                  Self.isFinite(placement.uAxis), Self.isFinite(placement.vAxis),
                  abs(simd_length_squared(placement.uAxis) - 1) < 1e-8,
                  abs(simd_length_squared(placement.vAxis) - 1) < 1e-8,
                  abs(simd_dot(placement.uAxis, placement.vAxis)) < 1e-8 else {
                throw Self.invalid("Grid placement requires an admitted grid and an orthonormal world plane.")
            }
            try Self.validateColor(placement.color)
            _ = try placement.transform(minorStepMeters: 1, renderOrigin: renderOrigin)
            try item()
            try positions(4)
            try charge(1, stride: MemoryLayout<GridPlacement>.stride + MemoryLayout<LowLevelMesh.Part>.stride
                       + MemoryLayout<UnlitMaterial>.stride + MemoryLayout<(ModelEntity, LowLevelMesh)>.stride
                       + MemoryLayout<simd_float4x4>.stride)
            try charge(4, stride: MemoryLayout<SIMD3<Float>>.stride)
            try charge(8, stride: MemoryLayout<UInt32>.stride)
        }
        for mesh in meshes {
            try Task.checkCancellation()
            try validateHandle(mesh.handleIndex)
            try validateHitTolerance(mesh.hitTolerancePoints)
            try item()
            try positions(mesh.positions.count)
            try charge(1, stride: MemoryLayout<Mesh>.stride + MemoryLayout<LowLevelMesh.Part>.stride
                       + MemoryLayout<UnlitMaterial>.stride + MemoryLayout<Appearance>.stride
                       + MemoryLayout<BoundingBox>.stride)
            // Source COW buffers plus native input/buffer capacity are admitted
            // together. Engine-internal mesh allocations are opaque, not exact bytes.
            try charge(mesh.positions.count, stride: MemoryLayout<Point3D>.stride + 2 * MemoryLayout<SIMD3<Float>>.stride)
            try charge(mesh.indices.count, stride: 3 * MemoryLayout<UInt32>.stride)
            try Self.validateColor(mesh.color)
            let arity = mesh.topology == .lines ? 2 : 3
            guard !mesh.indices.isEmpty, mesh.indices.count.isMultiple(of: arity) else {
                throw Self.invalid("Spatial topology has an incomplete primitive.")
            }
            if mesh.topology == .triangles {
                let sum = triangleCount.addingReportingOverflow(mesh.indices.count / 3)
                guard !sum.overflow, sum.partialValue <= limits.maxTriangleCount else { throw Self.exhausted() }
                triangleCount = sum.partialValue
            }
            for point in mesh.positions { _ = try Self.nativePoint(point, relativeTo: renderOrigin) }
            for index in mesh.indices where Int(index) >= mesh.positions.count {
                throw Self.invalid("Spatial topology references an absent vertex.")
            }
            if mesh.handleIndex != nil, mesh.hitTolerancePoints != nil {
                if mesh.topology == .triangles {
                    // The native static-mesh collision shares the admitted mesh
                    // topology, but its component and shape reference remain
                    // application-owned admission items.
                    try charge(1, stride: MemoryLayout<CollisionComponent>.stride
                               + MemoryLayout<[ShapeResource]>.stride
                               + MemoryLayout<ShapeResource>.stride)
                } else {
                    // Line geometry uses one bounded native proxy entity per
                    // segment. The proxies are prepared once and only their
                    // transforms change with the camera.
                    for _ in 0..<(mesh.indices.count / 2) {
                        try item()
                        lineCollisionCount += 1
                        handleFragmentCount += 1
                        try charge(1, stride: MemoryLayout<Entity>.stride
                                   + MemoryLayout<CollisionComponent>.stride
                                   + MemoryLayout<[ShapeResource]>.stride + MemoryLayout<ShapeResource>.stride
                                   + MemoryLayout<RealityViewportSpatialResources.LineCollision>.stride)
                    }
                }
            }
        }
        for path in paths {
            try validateHandle(path.handleIndex)
            try validateHitTolerance(path.hitTolerancePoints)
            try Task.checkCancellation()
            try item()
            try charge(1, stride: MemoryLayout<PlanarPath>.stride)
            if path.handleIndex != nil, path.hitTolerancePoints != nil {
                try charge(1, stride: MemoryLayout<CollisionComponent>.stride
                           + MemoryLayout<[ShapeResource]>.stride
                           + MemoryLayout<ShapeResource>.stride)
            }
            try Self.validateColor(path.color)
            _ = try Self.nativePoint(path.origin, relativeTo: renderOrigin)
            let xLength = simd_length(path.xAxis)
            let normalLength = simd_length(simd_cross(path.xAxis, path.yAxis))
            guard Self.isFinite(path.xAxis), Self.isFinite(path.yAxis),
                  xLength.isFinite, xLength > 0, normalLength.isFinite, normalLength > 0 else {
                throw Self.invalid("Spatial path requires an independent finite plane basis.")
            }
            var pointCount = 0
            var valid = true
            var excessive = false
            var drawable = false
            func check(_ point: CGPoint) {
                valid = valid && point.x.isFinite && point.y.isFinite
                let world = SIMD3<Double>(path.origin.x - renderOrigin.x, path.origin.y - renderOrigin.y,
                                          path.origin.z - renderOrigin.z)
                    + path.xAxis * Double(point.x) + path.yAxis * Double(point.y)
                let native = SIMD3<Float>(world)
                valid = valid && native.x.isFinite && native.y.isFinite && native.z.isFinite
                if pointCount < limits.maxPositionCount { pointCount += 1 } else { excessive = true }
            }
            path.path.forEach { element in
                switch element {
                case .move(let p): check(p)
                case .line(let p): check(p); drawable = true
                case .quadCurve(let p, let c): check(p); check(c); drawable = true
                case .curve(let p, let c1, let c2): check(p); check(c1); check(c2); drawable = true
                case .closeSubpath: return
                }
            }
            guard !excessive else { throw Self.exhausted() }
            guard valid, drawable else { throw Self.invalid("Spatial path has no drawable topology or has invalid control points.") }
            try positions(pointCount)
            try positions(pointCount)
            // Source, transformed cache key, and temporary native normalization.
            try charge(pointCount, stride: 3 * MemoryLayout<Path.Element>.stride)
        }
        for label in labels {
            try validateHandle(label.handleIndex)
            try validateHitRect(label.hitRectPoints)
            try Task.checkCancellation()
            try item()
            try charge(1, stride: MemoryLayout<Label>.stride + MemoryLayout<(Entity, Label, Entity?)>.stride)
            if label.handleIndex != nil, label.hitRectPoints != nil {
                try item()
                labelCollisionCount += 1
                handleFragmentCount += 1
                if !labelCollisionResourceCharged {
                    labelCollisionResourceCharged = true
                    // The shared zero-thickness quad is built once per prepared
                    // owner. Admit its fixed native buffers before allocation.
                    try positions(4)
                    try charge(4, stride: MemoryLayout<SIMD3<Float>>.stride)
                    try charge(12, stride: MemoryLayout<UInt32>.stride)
                    try charge(1, stride: MemoryLayout<LowLevelMesh.Descriptor>.stride
                               + MemoryLayout<LowLevelMesh.Part>.stride
                               + MemoryLayout<MeshResource>.stride
                               + MemoryLayout<ShapeResource>.stride)
                }
                try charge(1, stride: MemoryLayout<CollisionComponent>.stride
                           + MemoryLayout<[ShapeResource]>.stride
                           + MemoryLayout<ShapeResource>.stride
                           + MemoryLayout<Entity>.stride)
            }
            try charge(label.text.utf8.count, stride: 2)
            try positions(label.text.unicodeScalars.count)
            try Self.validateColor(label.color)
            _ = try Self.nativePoint(label.anchor, relativeTo: renderOrigin)
            try validateOffset(label.offset)
            guard !label.text.isEmpty,
                  label.heightPoints.isFinite, label.heightPoints > 0 else {
                throw Self.invalid("Spatial label text, size, or offset is invalid.")
            }
        }
        for marker in markers {
            try validateHandle(marker.handleIndex)
            try validateHitTolerance(marker.hitTolerancePoints)
            try item()
            try charge(1, stride: MemoryLayout<Marker>.stride + MemoryLayout<(Entity, Marker)>.stride)
            if marker.handleIndex != nil, let tolerance = marker.hitTolerancePoints, tolerance > 0 {
                try item()
                markerCollisionCount += 1
                handleFragmentCount += 1
                // Application-owned component and one-element shape reference
                // storage; RealityKit's native collision allocation is opaque.
                try charge(1, stride: MemoryLayout<Entity>.stride + MemoryLayout<CollisionComponent>.stride
                           + MemoryLayout<[ShapeResource]>.stride + MemoryLayout<ShapeResource>.stride)
            }
            try Self.validateColor(marker.color)
            _ = try Self.nativePoint(marker.anchor, relativeTo: renderOrigin)
            try validateOffset(marker.offset)
            guard marker.diameterPoints.isFinite, marker.diameterPoints > 0 else {
                throw Self.invalid("Spatial marker size is invalid.")
            }
        }
        for line in cameraLines {
            guard line.points.count >= 2 else { throw Self.invalid("A camera-relative line requires two points.") }
            if let width = line.widthPoints {
                guard width.isFinite, width > 0 else { throw Self.invalid("Camera line width is invalid.") }
                for _ in 1..<line.points.count {
                    try item()
                    try positions(24)
                    let sum = triangleCount.addingReportingOverflow(12)
                    guard !sum.overflow, sum.partialValue <= limits.maxTriangleCount else {
                        throw Self.exhausted()
                    }
                    triangleCount = sum.partialValue
                    try charge(1, stride: MemoryLayout<ModelEntity>.stride)
                    try charge(24, stride: MemoryLayout<SIMD3<Float>>.stride)
                    try charge(36, stride: MemoryLayout<UInt32>.stride)
                }
            }
            try validateHandle(line.handleIndex)
            try validateHitTolerance(line.hitTolerancePoints)
            try item()
            try positions(line.points.count)
            try charge(1, stride: MemoryLayout<CameraLine>.stride + MemoryLayout<(ModelEntity, LowLevelMesh, CameraLine, [Entity], [ModelEntity])>.stride)
            try charge(line.points.count, stride: MemoryLayout<CameraPoint>.stride + MemoryLayout<SIMD3<Float>>.stride + 2 * MemoryLayout<UInt32>.stride)
            try Self.validateColor(line.color)
            guard line.points.count >= 2 else { throw Self.invalid("A camera-relative line requires two points.") }
            for point in line.points {
                // Per-camera placements share the existing item ceiling; a line
                // cannot hide an unbounded camera-frame loop in its point array.
                try item()
                _ = try Self.nativePoint(point.anchor, relativeTo: renderOrigin)
                try validateOffset(point.offset)
            }
            if line.handleIndex != nil, line.hitTolerancePoints != nil {
                for _ in 0..<(line.points.count - 1) {
                    try item()
                    lineCollisionCount += 1
                    handleFragmentCount += 1
                    try charge(1, stride: 2 * MemoryLayout<Entity>.stride
                               + MemoryLayout<CollisionComponent>.stride
                               + MemoryLayout<[ShapeResource]>.stride + MemoryLayout<ShapeResource>.stride
                               + MemoryLayout<RealityViewportSpatialResources.LineCollision>.stride)
                }
            }
        }
        for path in cameraPaths {
            try validateHandle(path.handleIndex)
            try validateHitTolerance(path.hitTolerancePoints)
            try Task.checkCancellation()
            try item()
            try charge(1, stride: MemoryLayout<CameraPath>.stride + MemoryLayout<(Entity, CameraPath, Entity?)>.stride)
            if path.handleIndex != nil, let tolerance = path.hitTolerancePoints, tolerance > 0 {
                try item()
                markerCollisionCount += 1
                handleFragmentCount += 1
                try charge(1, stride: MemoryLayout<CollisionComponent>.stride
                           + MemoryLayout<[ShapeResource]>.stride
                           + MemoryLayout<ShapeResource>.stride
                           + MemoryLayout<Entity>.stride)
            }
            _ = try Self.nativePoint(path.anchor, relativeTo: renderOrigin)
            try Self.validateColor(path.color)
            try validateOffset(path.offset)
            guard !path.path.isEmpty else {
                throw Self.invalid("Camera path or offset is invalid.")
            }
            var count = 0
            var valid = true
            var drawable = false
            func check(_ point: CGPoint) {
                valid = valid && Float(point.x).isFinite && Float(point.y).isFinite
                count += 1
            }
            path.path.forEach { element in
                switch element {
                case .move(let p): check(p)
                case .line(let p): check(p); drawable = true
                case .quadCurve(let p, let c): check(p); check(c); drawable = true
                case .curve(let p, let c1, let c2): check(p); check(c1); check(c2); drawable = true
                case .closeSubpath: break
                }
            }
            guard valid, drawable else { throw Self.invalid("Camera path has no drawable topology or has invalid control points.") }
            try positions(count)
            try positions(count)
            try charge(count, stride: 3 * MemoryLayout<Path.Element>.stride)
        }
        var rulerLabelCount = 0
        if let group = boundsRulers {
            try charge(1, stride: MemoryLayout<BoundsRulers>.stride)
            let bounds = group.input.bounds
            _ = try Self.nativePoint(Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.minimum.z), relativeTo: renderOrigin)
            _ = try Self.nativePoint(Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.maximum.z), relativeTo: renderOrigin)
            guard bounds.minimum.x <= bounds.maximum.x,
                  bounds.minimum.y <= bounds.maximum.y,
                  bounds.minimum.z <= bounds.maximum.z,
                  group.heightPoints.isFinite, group.heightPoints > 0 else {
                throw Self.invalid("Bounds ruler bounds or label size is invalid.")
            }
            try Self.validateColor(group.color)
            for axis in ViewportMeasurementRulerAxis.allCases {
                let extent: Double
                switch axis {
                case .x: extent = bounds.maximum.x - bounds.minimum.x
                case .y: extent = bounds.maximum.y - bounds.minimum.y
                case .z: extent = bounds.maximum.z - bounds.minimum.z
                }
                guard extent.isFinite, (group.input.labels[axis] != nil) == (extent > 1e-12) else {
                    throw Self.invalid("Bounds ruler labels do not match the finite nonzero axes.")
                }
                guard let text = group.input.labels[axis] else { continue }
                guard !text.isEmpty else { throw Self.invalid("Bounds ruler label is empty.") }
                rulerLabelCount += 1
                // One label, one line mesh, and six camera-relative points.
                for _ in 0..<8 { try item() }
                try positions(6)
                try positions(text.unicodeScalars.count)
                try charge(text.utf8.count, stride: 2)
                try charge(1, stride: MemoryLayout<(ViewportMeasurementRulerAxis, Entity, ModelEntity, LowLevelMesh)>.stride
                           + MemoryLayout<LowLevelMesh.Part>.stride + 2 * MemoryLayout<UnlitMaterial>.stride)
                try charge(6, stride: MemoryLayout<CameraPoint>.stride + MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<UInt32>.stride)
            }
            guard rulerLabelCount > 0 else { throw Self.invalid("Bounds ruler group has no eligible axis.") }
        }
        // All counts have now passed the hard 640-item ceiling. Use the same
        // conservative dictionary reservation as native geometry grouping:
        // power-of-two buckets for twice the entries, occupancy word, and header.
        if handleFragmentCount > 0 {
            var buckets = 2
            while buckets < handleFragmentCount * 2 { buckets *= 2 }
            try charge(buckets, stride: MemoryLayout<ObjectIdentifier>.stride + MemoryLayout<UInt32>.stride
                       + MemoryLayout<UInt64>.stride)
            try charge(128, stride: 1)
        }
        if markerCollisionCount > 0 {
            var buckets = 2
            while buckets < markerCollisionCount * 2 { buckets *= 2 }
            try charge(buckets, stride: MemoryLayout<ObjectIdentifier>.stride
                       + MemoryLayout<RealityViewportSpatialResources.MarkerCollision>.stride
                       + MemoryLayout<UInt64>.stride)
            try charge(128, stride: 1)
        }
        if labelCollisionCount > 0 {
            var buckets = 2
            while buckets < labelCollisionCount * 2 { buckets *= 2 }
            try charge(buckets, stride: MemoryLayout<ObjectIdentifier>.stride
                       + MemoryLayout<RealityViewportSpatialResources.LabelCollision>.stride
                       + MemoryLayout<UInt64>.stride)
            try charge(128, stride: 1)
            try charge(1, stride: MemoryLayout<LowLevelMesh>.stride
                       + MemoryLayout<MeshResource>.stride + MemoryLayout<ShapeResource>.stride)
        }
        if lineCollisionCount > 0 {
            var buckets = 2
            while buckets < lineCollisionCount * 2 { buckets *= 2 }
            try charge(buckets, stride: MemoryLayout<ObjectIdentifier>.stride + MemoryLayout<Int>.stride + MemoryLayout<UInt64>.stride)
            try charge(128, stride: 1)
        }
        // A grouped mesh retains a bounded source-index list and native owner.
        // Reserving once per source mesh covers the worst case of distinct handles.
        try charge(meshes.count, stride: 2 * MemoryLayout<Int>.stride
                   + 2 * MemoryLayout<(Attachment, UInt32?, [Int])>.stride
                   + MemoryLayout<(ModelEntity, LowLevelMesh)>.stride)
        for (count, keyStride) in [(paths.count + cameraPaths.count, MemoryLayout<CGPath>.stride),
                                   (labels.count + rulerLabelCount, MemoryLayout<String>.stride)] where count > 0 {
            var buckets = 2
            while buckets < count * 2 { buckets *= 2 }
            try charge(buckets, stride: keyStride + MemoryLayout<MeshResource>.stride + MemoryLayout<UInt64>.stride)
            try charge(128, stride: 1)
        }
        self.meshes = meshes
        self.lineCollisionCount = lineCollisionCount
        self.paths = paths
        self.labels = labels
        self.markers = markers
        self.cameraLines = cameraLines
        self.cameraPaths = cameraPaths
        self.boundsRulers = boundsRulers
        self.includesGrid = includesGrid
        self.includesAxes = includesAxes
        self.gridPlacement = gridPlacement
        self.handleCount = handleCount
        self.renderOrigin = renderOrigin
        self.retainedSurfaceByteCount = retainedSurfaceByteCount
        self.retainedSemanticByteCount = retainedSemanticByteCount
        self.itemCount = itemCount
        self.positionCount = positionCount
        self.triangleCount = triangleCount
        self.limits = limits
        admittedByteCount = bytes
    }

    func validate(surfacePlan: MeshSourcePresentationRenderPlan?) throws {
        guard retainedSurfaceByteCount == (surfacePlan?.retainedByteCount ?? 0) else {
            throw Self.invalid("Spatial admission does not match the retained surface plan.")
        }
        for (spatial, surface, maximum) in [
            (itemCount, surfacePlan?.itemCount ?? 0, limits.maxItemCount),
            (positionCount, surfacePlan?.positionCount ?? 0, limits.maxPositionCount),
            (triangleCount, surfacePlan?.triangleCount ?? 0, limits.maxTriangleCount)
        ] {
            let sum = spatial.addingReportingOverflow(surface)
            guard !sum.overflow, sum.partialValue <= maximum else { throw Self.exhausted() }
        }
        guard admittedByteCount <= (surfacePlan?.nativePreparationByteLimit ?? limits.maxRetainedByteCount) else {
            throw Self.exhausted()
        }
    }

    static func nativePoint(_ point: Point3D, relativeTo origin: Point3D) throws -> SIMD3<Float> {
        let point = SIMD3<Float>(Float(point.x - origin.x), Float(point.y - origin.y), Float(point.z - origin.z))
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
            throw invalid("Spatial position exceeds native coordinate precision.")
        }
        return point
    }

    private static func isFinite(_ vector: SIMD3<Double>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    private static func validateColor(_ color: SIMD4<Float>) throws {
        guard (0..<4).allSatisfy({ color[$0].isFinite && (0...1).contains(color[$0]) }) else {
            throw invalid("Spatial color is outside the finite unit range.")
        }
    }

    static func invalid(_ message: String) -> MeshSourcePresentationRenderError {
        .init(code: .invalidSceneItem, message: message)
    }

    static func exhausted() -> MeshSourcePresentationRenderError {
        .init(code: .resourceExhausted, message: "The complete spatial overlay exceeds viewport admission limits.")
    }
}
