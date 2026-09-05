import CoreGraphics
import Foundation
import Metal
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaViewportScene
import simd

/// Immutable native surface resources shared by the viewport and GPU checks.
/// Build off MainActor; encoding visits occurrences, never individual triangles.
public final class ViewportSurfaceRenderer: Sendable {
    private struct Pipeline: Sendable {
        let device: any MTLDevice
        let queue: any MTLCommandQueue
        let state: any MTLRenderPipelineState
        let lineState: any MTLRenderPipelineState
        let depthOnlyState: any MTLRenderPipelineState
        let depth: any MTLDepthStencilState

        init() throws {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue() else {
                throw Self.failure(.gpuUnavailable, "Metal is unavailable.")
            }
            let state: any MTLRenderPipelineState
            let lineState: any MTLRenderPipelineState
            let depthOnlyState: any MTLRenderPipelineState
            do {
                let library = try device.makeLibrary(source: ViewportSurfaceRenderer.shader, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "surfaceVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "surfaceFragment")
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                descriptor.depthAttachmentPixelFormat = .depth32Float
                state = try device.makeRenderPipelineState(descriptor: descriptor)

                let lineDescriptor = MTLRenderPipelineDescriptor()
                lineDescriptor.vertexFunction = library.makeFunction(name: "surfaceVertex")
                lineDescriptor.fragmentFunction = library.makeFunction(name: "surfaceLineFragment")
                lineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                lineDescriptor.depthAttachmentPixelFormat = .depth32Float
                lineState = try device.makeRenderPipelineState(descriptor: lineDescriptor)

                let depthOnlyDescriptor = MTLRenderPipelineDescriptor()
                depthOnlyDescriptor.vertexFunction = library.makeFunction(name: "surfaceVertex")
                depthOnlyDescriptor.fragmentFunction = library.makeFunction(name: "surfaceLineFragment")
                depthOnlyDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                depthOnlyDescriptor.colorAttachments[0].writeMask = MTLColorWriteMask(rawValue: 0)
                depthOnlyDescriptor.depthAttachmentPixelFormat = .depth32Float
                depthOnlyState = try device.makeRenderPipelineState(descriptor: depthOnlyDescriptor)
            } catch {
                throw Self.failure(.gpuFailure, "Metal surface pipeline creation failed: \(error.localizedDescription)")
            }
            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.depthCompareFunction = .less
            depthDescriptor.isDepthWriteEnabled = true
            guard let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else {
                throw Self.failure(.gpuFailure, "Metal could not create depth testing state.")
            }
            self.device = device
            self.queue = queue
            self.state = state
            self.lineState = lineState
            self.depthOnlyState = depthOnlyState
            self.depth = depth
        }

        private static func failure(
            _ code: MeshSourcePresentationRenderError.Code, _ message: String
        ) -> MeshSourcePresentationRenderError {
            MeshSourcePresentationRenderError(code: code, message: message)
        }
    }

    private struct Draw: Sendable {
        let occurrenceID: SceneOccurrenceID
        let indexOffset: Int
        let indexCount: Int
        let baseVertex: Int
        let boundaryIndexOffset: Int
        let boundaryIndexCount: Int
    }

    /// Metal's SDK buffer handles are mutable and not Sendable. This private
    /// owner never exposes them: initialization finishes all CPU writes before
    /// publication, and every subsequent binding is GPU-read-only. There are
    /// no writable aliases, mapped pointers, CPU writes, or GPU write bindings
    /// after construction. Command buffers retain both owners until completion.
    private final class ImmutableGeometry: @unchecked Sendable {
        let positions: any MTLBuffer
        let indices: any MTLBuffer
        let boundaryIndices: (any MTLBuffer)?

        init(
            positions: any MTLBuffer,
            indices: any MTLBuffer,
            boundaryIndices: (any MTLBuffer)?
        ) {
            self.positions = positions
            self.indices = indices
            self.boundaryIndices = boundaryIndices
        }
    }

    // Immutable native shader state is process-owned, independent of snapshots.
    // The production cache first accesses it on its detached preparation task.
    private static let pipeline = Result { try Pipeline() }
    private let pipeline: Pipeline
    private let geometry: ImmutableGeometry?
    private let draws: [Draw]
    private let origin: Point3D
    private let radius: Double
    public let snapshotID: EvaluationSnapshotID
    public let triangleCount: Int
    public let allocatedGeometryByteCount: Int

    public var device: any MTLDevice { pipeline.device }

    /// Two drawable color buffers and one depth attachment fit this separate
    /// 2.5%-of-8-GiB frame budget. App evidence includes it in pipeline memory.
    public static let maximumAttachmentByteCount = (8 * 1024 * 1024 * 1024) / 40

    public static func attachmentByteCount(width: Int, height: Int) throws -> Int {
        guard width > 0, height > 0 else {
            throw failure(.invalidLimit, "The surface drawable must have positive dimensions.")
        }
        let pixels = width.multipliedReportingOverflow(by: height)
        let bytes = pixels.partialValue.multipliedReportingOverflow(by: 12)
        guard !pixels.overflow, !bytes.overflow,
              bytes.partialValue <= maximumAttachmentByteCount else {
            throw failure(.resourceExhausted, "The surface drawable exceeds its attachment memory limit.")
        }
        return bytes.partialValue
    }

    public init(plan: MeshSourcePresentationRenderPlan) throws {
        try Task.checkCancellation()
        let pipeline = try Self.pipeline.get()
        try Task.checkCancellation()
        self.pipeline = pipeline
        snapshotID = plan.snapshotID
        triangleCount = plan.triangleCount
        let first = plan.occurrences.lazy.compactMap { $0.positions.first }.first
            ?? GeometryPoint3D(x: 0, y: 0, z: 0)
        origin = Point3D(x: first.x, y: first.y, z: first.z)
        let vertexBytes = try Self.product(plan.positionCount, MemoryLayout<SIMD4<Float>>.stride)
        let indexBytes = try Self.product(plan.triangleCount, 3 * MemoryLayout<UInt32>.stride)
        let boundaryBytes = try Self.product(plan.boundaryIndexCount, MemoryLayout<UInt32>.stride)
        guard vertexBytes <= plan.retainedByteCount,
              indexBytes <= plan.retainedByteCount - vertexBytes,
              boundaryBytes <= plan.retainedByteCount - vertexBytes - indexBytes else {
            throw Self.failure(.resourceExhausted, "GPU geometry has no admission in the presentation plan.")
        }
        if plan.positionCount == 0 || plan.triangleCount == 0 {
            geometry = nil
            draws = []
            radius = 1
            allocatedGeometryByteCount = 0
            return
        }
        guard let positions = pipeline.device.makeBuffer(length: vertexBytes, options: .storageModeShared),
              let indices = pipeline.device.makeBuffer(length: indexBytes, options: .storageModeShared) else {
            throw Self.failure(.gpuFailure, "Metal could not allocate admitted surface geometry.")
        }
        positions.label = "Rupa immutable surface positions"
        indices.label = "Rupa immutable surface indices"
        let boundaries: (any MTLBuffer)?
        if boundaryBytes > 0 {
            guard let buffer = pipeline.device.makeBuffer(length: boundaryBytes, options: .storageModeShared) else {
                throw Self.failure(.gpuFailure, "Metal could not allocate admitted boundary geometry.")
            }
            buffer.label = "Rupa immutable source-face boundary indices"
            boundaries = buffer
        } else {
            boundaries = nil
        }
        var draws: [Draw] = []
        draws.reserveCapacity(plan.itemCount)
        var vertexOffset = 0
        var indexOffset = 0
        var boundaryOffset = 0
        var radius = 0.0
        // Metal owns both allocations. The typed borrows cover exactly their
        // checked lengths, initialize every element once, and never escape.
        // Command buffers retain the immutable owners until GPU completion.
        let vertexPointer = positions.contents().bindMemory(to: SIMD4<Float>.self, capacity: plan.positionCount)
        let indexPointer = indices.contents().bindMemory(to: UInt32.self, capacity: plan.triangleCount * 3)
        let boundaryPointer = boundaries?.contents().bindMemory(to: UInt32.self, capacity: plan.boundaryIndexCount)
        for occurrence in plan.occurrences {
            try Task.checkCancellation()
            for (index, point) in occurrence.positions.enumerated() {
                if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
                let relative = SIMD3<Double>(point.x - first.x, point.y - first.y, point.z - first.z)
                let converted = SIMD3<Float>(relative)
                guard converted.x.isFinite, converted.y.isFinite, converted.z.isFinite else {
                    throw Self.failure(.invalidTransform, "Surface coordinates cannot be represented relative to their origin.")
                }
                vertexPointer.advanced(by: vertexOffset + index).initialize(to: SIMD4<Float>(converted, 1))
                radius = max(radius, abs(relative.x), abs(relative.y), abs(relative.z))
            }
            for (index, value) in occurrence.vertexIndices.enumerated() {
                if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
                indexPointer.advanced(by: indexOffset + index).initialize(to: value)
            }
            let firstBoundary = boundaryOffset
            for (side, corner) in occurrence.boundaryCornerIndices.enumerated() {
                if side.isMultiple(of: 4_096) { try Task.checkCancellation() }
                guard corner != UInt32.max else { continue }
                guard let boundaryPointer, boundaryOffset <= plan.boundaryIndexCount - 2 else {
                    throw Self.failure(.invalidCornerReference, "Boundary indices exceed their admitted range.")
                }
                let next = side - side % 3 + (side + 1) % 3
                boundaryPointer.advanced(by: boundaryOffset).initialize(to: occurrence.vertexIndices[side])
                boundaryPointer.advanced(by: boundaryOffset + 1).initialize(to: occurrence.vertexIndices[next])
                boundaryOffset += 2
            }
            draws.append(Draw(
                occurrenceID: occurrence.occurrenceID,
                indexOffset: indexOffset * MemoryLayout<UInt32>.stride,
                indexCount: occurrence.vertexIndices.count,
                baseVertex: vertexOffset,
                boundaryIndexOffset: firstBoundary * MemoryLayout<UInt32>.stride,
                boundaryIndexCount: boundaryOffset - firstBoundary
            ))
            vertexOffset += occurrence.positions.count
            indexOffset += occurrence.vertexIndices.count
        }
        try Task.checkCancellation()
        guard boundaryOffset == plan.boundaryIndexCount else {
            throw Self.failure(.invalidCornerReference, "Boundary indices do not match their admitted count.")
        }
        geometry = ImmutableGeometry(positions: positions, indices: indices, boundaryIndices: boundaries)
        self.draws = draws
        self.radius = max(radius * 4, 1.0e-9)
        allocatedGeometryByteCount = positions.allocatedSize + indices.allocatedSize + (boundaries?.allocatedSize ?? 0)
    }

    public func makeCommandBuffer() throws -> any MTLCommandBuffer {
        guard let buffer = pipeline.queue.makeCommandBuffer() else {
            throw Self.failure(.gpuFailure, "Metal could not create a surface command buffer.")
        }
        return buffer
    }

    /// The caller owns submission/completion. No wait or readback occurs here.
    public func encode(
        into commandBuffer: any MTLCommandBuffer,
        pass: MTLRenderPassDescriptor,
        layout: ViewportLayout,
        displayMode: ViewportDisplayMode = .solid,
        state: (SceneOccurrenceID) -> MeshSourcePresentationVisualState = { _ in .normal },
        sectionPlane: SectionAnalysisResult.Plane? = nil,
        retainedSide: SectionAnalysisRetainedSide = .front,
        sectionTolerance: Double = 0
    ) throws {
        guard let target = pass.colorAttachments[0].texture,
              target.pixelFormat == .bgra8Unorm, target.sampleCount == 1,
              let depth = pass.depthAttachment.texture,
              depth.pixelFormat == .depth32Float, depth.sampleCount == 1,
              depth.width == target.width, depth.height == target.height else {
            throw Self.failure(.gpuFailure, "Surface drawing requires matching single-sample BGRA8 and depth32 attachments.")
        }
        _ = try Self.attachmentByteCount(width: target.width, height: target.height)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw Self.failure(.gpuFailure, "Metal could not encode a surface pass.")
        }
        defer { encoder.endEncoding() }
        guard let geometry else { return }
        var uniforms = try makeUniforms(
            layout: layout, sectionPlane: sectionPlane,
            retainedSide: retainedSide, sectionTolerance: sectionTolerance
        )
        uniforms.options.x = displayMode == .normals ? 1 : 0
        encoder.setRenderPipelineState(displayMode == .wireframe ? pipeline.depthOnlyState : pipeline.state)
        encoder.setDepthStencilState(pipeline.depth)
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setVertexBuffer(geometry.positions, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        for draw in draws {
            switch state(draw.occurrenceID) {
            case .normal: uniforms.color = SIMD4<Float>(0.64, 0.69, 0.73, 1)
            case .hovered: uniforms.color = SIMD4<Float>(0.24, 0.88, 0.82, 1)
            case .selected: uniforms.color = SIMD4<Float>(0.14, 0.66, 0.95, 1)
            }
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: draw.indexCount, indexType: .uint32,
                indexBuffer: geometry.indices, indexBufferOffset: draw.indexOffset,
                instanceCount: 1, baseVertex: draw.baseVertex, baseInstance: 0
            )
        }
        if (displayMode == .solidWithEdges || displayMode == .wireframe),
           let boundaries = geometry.boundaryIndices {
            encoder.setRenderPipelineState(pipeline.lineState)
            // A one-ULP offset applies only to the line pass. Strict depth writes retain
            // first-occurrence ownership for coincident lines; all surfaces
            // already populated depth before any boundary is submitted.
            uniforms.options.y = 1
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            for draw in draws where draw.boundaryIndexCount > 0 {
                switch state(draw.occurrenceID) {
                case .normal: uniforms.color = displayMode == .wireframe
                    ? SIMD4<Float>(0.48, 0.56, 0.64, 1) : SIMD4<Float>(0.08, 0.12, 0.17, 1)
                case .hovered: uniforms.color = SIMD4<Float>(0.24, 0.88, 0.82, 1)
                case .selected: uniforms.color = SIMD4<Float>(0.14, 0.66, 0.95, 1)
                }
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.drawIndexedPrimitives(
                    type: .line, indexCount: draw.boundaryIndexCount, indexType: .uint32,
                    indexBuffer: boundaries, indexBufferOffset: draw.boundaryIndexOffset,
                    instanceCount: 1, baseVertex: draw.baseVertex, baseInstance: 0
                )
            }
        }
    }

    private struct Uniforms {
        var x: SIMD4<Float>
        var y: SIMD4<Float>
        var depth: SIMD4<Float>
        var view: SIMD4<Float>
        var light: SIMD4<Float>
        var clip: SIMD4<Float>
        var color: SIMD4<Float>
        var options = SIMD4<Float>(repeating: 0)
    }

    private func makeUniforms(
        layout: ViewportLayout, sectionPlane: SectionAnalysisResult.Plane?,
        retainedSide: SectionAnalysisRetainedSide, sectionTolerance: Double
    ) throws -> Uniforms {
        guard layout.viewportSize.width > 0, layout.viewportSize.height > 0,
              let normal = layout.basis.viewNormal else {
            throw Self.failure(.invalidTransform, "Surface projection is singular.")
        }
        let center = layout.project(origin)
        let xScale = Double(2 * layout.scale / layout.viewportSize.width)
        let yScale = Double(-2 * layout.scale / layout.viewportSize.height)
        let basis = layout.basis
        let right = SIMD3<Float>(Float(basis.xDirection.dx), Float(basis.yDirection.dx), Float(basis.zDirection.dx))
        let up = SIMD3<Float>(-Float(basis.xDirection.dy), -Float(basis.yDirection.dy), -Float(basis.zDirection.dy))
        let view = SIMD3<Float>(Float(normal.x), Float(normal.y), Float(normal.z))
        let light = simd_normalize(-0.45 * right + 0.65 * up + 0.75 * view)
        var clip = SIMD4<Float>(0, 0, 0, 1)
        if let sectionPlane {
            let sign = retainedSide == .front ? 1.0 : -1.0
            let n = sectionPlane.normal
            let distance = (origin.x - sectionPlane.origin.x) * n.x
                + (origin.y - sectionPlane.origin.y) * n.y
                + (origin.z - sectionPlane.origin.z) * n.z
            clip = SIMD4<Float>(Float(n.x * sign), Float(n.y * sign), Float(n.z * sign), Float(distance * sign + max(sectionTolerance, 0)))
        }
        let values = Uniforms(
            x: SIMD4<Float>(right * Float(xScale), Float(2 * center.x / layout.viewportSize.width - 1)),
            y: SIMD4<Float>(-up * Float(yScale), Float(1 - 2 * center.y / layout.viewportSize.height)),
            depth: SIMD4<Float>(-view * Float(0.5 / radius), 0.5),
            view: SIMD4<Float>(view, 0), light: SIMD4<Float>(light, 0),
            clip: clip, color: SIMD4<Float>(repeating: 1)
        )
        for vector in [values.x, values.y, values.depth, values.view, values.light, values.clip] {
            guard (0..<4).allSatisfy({ vector[$0].isFinite }) else {
                throw Self.failure(.invalidTransform, "Surface projection contains an unrepresentable value.")
            }
        }
        return values
    }

    private static func product(_ lhs: Int, _ rhs: Int) throws -> Int {
        let value = lhs.multipliedReportingOverflow(by: rhs)
        guard !value.overflow else { throw failure(.sizeOverflow, "Surface buffer size overflow.") }
        return value.partialValue
    }

    private static func failure(
        _ code: MeshSourcePresentationRenderError.Code, _ message: String
    ) -> MeshSourcePresentationRenderError {
        MeshSourcePresentationRenderError(code: code, message: message)
    }

    private static let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct Uniforms { float4 x, y, depth, view, light, clip, color, options; };
        struct SurfaceVertex { float4 position [[position]]; float3 local; };
        vertex SurfaceVertex surfaceVertex(uint id [[vertex_id]],
            const device float4* positions [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
            float4 p = positions[id];
            float depth = dot(p, u.depth);
            if (u.options.y > 0.5) depth = nextafter(depth, 0.0f);
            return { float4(dot(p, u.x), dot(p, u.y), depth, 1), p.xyz };
        }
        fragment float4 surfaceLineFragment(SurfaceVertex p [[stage_in]], constant Uniforms& u [[buffer(1)]]) {
            if (dot(float4(p.local, 1), u.clip) < 0) discard_fragment();
            return u.color;
        }
        fragment float4 surfaceFragment(SurfaceVertex p [[stage_in]], bool front [[front_facing]], constant Uniforms& u [[buffer(1)]]) {
            if (dot(float4(p.local, 1), u.clip) < 0) discard_fragment();
            float3 derivative = cross(dfdx(p.local), dfdy(p.local));
            float lengthSquared = dot(derivative, derivative);
            float3 normal = lengthSquared > 0 ? derivative * rsqrt(lengthSquared) : u.view.xyz;
            if (dot(normal, u.view.xyz) < 0) normal = -normal;
            if (u.options.x > 0.5) {
                float3 sourceNormal = front ? normal : -normal;
                return float4(sourceNormal * 0.5 + 0.5, 1);
            }
            float diffuse = max(dot(normal, u.light.xyz), 0.0);
            float3 halfVector = normalize(u.light.xyz + u.view.xyz);
            float specular = 0.16 * pow(max(dot(normal, halfVector), 0.0), 36.0);
            float rim = mix(0.72, 1.0, smoothstep(0.0, 0.24, dot(normal, u.view.xyz)));
            float3 color = u.color.rgb * (0.24 + 0.76 * diffuse) * rim + specular;
            return float4(clamp(color, 0.0, 1.0), 1.0);
        }
        """
}
