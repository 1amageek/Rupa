import CoreGraphics
import Foundation
import Metal
import RupaCore
import RupaViewportScene

public enum ViewportIdentityBufferRendererError: Error, Equatable, Sendable {
    case invalidViewportSize
    case deviceUnavailable
    case libraryCreationFailed(String)
    case functionUnavailable(String)
    case pipelineCreationFailed(String)
    case commandQueueCreationFailed
    case bufferCreationFailed
    case textureCreationFailed
    case commandBufferCreationFailed
    case computeEncoderCreationFailed
    case commandExecutionFailed(String)
    case unsupportedIdentityValue(UInt32)
}

public struct ViewportIdentityBufferSample: Equatable, Sendable {
    public var rawValue: UInt32
    public var identity: ViewportPickIdentity?
    public var hit: ViewportHit?

    public init(
        rawValue: UInt32,
        identity: ViewportPickIdentity?,
        hit: ViewportHit?
    ) {
        self.rawValue = rawValue
        self.identity = identity
        self.hit = hit
    }
}

public struct ViewportIdentityBufferRenderMetrics: Codable, Equatable, Sendable {
    public var viewportWidth: Int
    public var viewportHeight: Int
    public var encodedCommandCount: Int
    public var encodedPointCount: Int
    public var encodedMeshPrimitiveCacheHitCount: Int
    public var encodedMeshPrimitiveCacheMissCount: Int
    public var pixelCount: Int
    public var encodeDurationSeconds: Double
    public var gpuDurationSeconds: Double
    public var readbackDurationSeconds: Double
    public var totalDurationSeconds: Double

    public init(
        viewportWidth: Int,
        viewportHeight: Int,
        encodedCommandCount: Int,
        encodedPointCount: Int,
        encodedMeshPrimitiveCacheHitCount: Int = 0,
        encodedMeshPrimitiveCacheMissCount: Int = 0,
        pixelCount: Int,
        encodeDurationSeconds: Double,
        gpuDurationSeconds: Double,
        readbackDurationSeconds: Double,
        totalDurationSeconds: Double
    ) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.encodedCommandCount = encodedCommandCount
        self.encodedPointCount = encodedPointCount
        self.encodedMeshPrimitiveCacheHitCount = encodedMeshPrimitiveCacheHitCount
        self.encodedMeshPrimitiveCacheMissCount = encodedMeshPrimitiveCacheMissCount
        self.pixelCount = pixelCount
        self.encodeDurationSeconds = encodeDurationSeconds
        self.gpuDurationSeconds = gpuDurationSeconds
        self.readbackDurationSeconds = readbackDurationSeconds
        self.totalDurationSeconds = totalDurationSeconds
    }
}

public struct ViewportIdentityBuffer: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var rawValues: [UInt32]
    public var index: ViewportIdentityPickIndex
    public var renderMetrics: ViewportIdentityBufferRenderMetrics?

    public init(
        width: Int,
        height: Int,
        rawValues: [UInt32],
        index: ViewportIdentityPickIndex,
        renderMetrics: ViewportIdentityBufferRenderMetrics? = nil
    ) {
        self.width = width
        self.height = height
        self.rawValues = rawValues
        self.index = index
        self.renderMetrics = renderMetrics
    }

    public func rawValue(at point: CGPoint) -> UInt32 {
        let x = Int(floor(point.x))
        let y = Int(floor(point.y))
        guard x >= 0,
              y >= 0,
              x < width,
              y < height else {
            return ViewportPickIdentity.backgroundRawValue
        }
        return rawValues[y * width + x]
    }

    public func sample(at point: CGPoint) throws -> ViewportIdentityBufferSample {
        let rawValue = rawValue(at: point)
        guard rawValue != ViewportPickIdentity.backgroundRawValue else {
            return ViewportIdentityBufferSample(
                rawValue: rawValue,
                identity: nil,
                hit: nil
            )
        }
        guard let identity = ViewportPickIdentity(rawValue: rawValue) else {
            throw ViewportIdentityBufferRendererError.unsupportedIdentityValue(rawValue)
        }
        return ViewportIdentityBufferSample(
            rawValue: rawValue,
            identity: identity,
            hit: index.hit(for: identity)
        )
    }

    public func hits(in rect: CGRect) -> [ViewportHit] {
        let sampleRect = normalized(rect)
        guard sampleRect.isNull == false,
              sampleRect.isEmpty == false else {
            return []
        }
        let minX = max(Int(floor(sampleRect.minX)), 0)
        let minY = max(Int(floor(sampleRect.minY)), 0)
        let maxX = min(Int(ceil(sampleRect.maxX)), width)
        let maxY = min(Int(ceil(sampleRect.maxY)), height)
        guard minX < maxX,
              minY < maxY else {
            return []
        }

        var hits: [ViewportHit] = []
        var seenIdentities: Set<ViewportPickIdentity> = []
        for y in minY ..< maxY {
            for x in minX ..< maxX {
                let rawValue = rawValues[y * width + x]
                guard rawValue != ViewportPickIdentity.backgroundRawValue,
                      let identity = ViewportPickIdentity(rawValue: rawValue),
                      seenIdentities.insert(identity).inserted,
                      let hit = index.hit(for: identity) else {
                    continue
                }
                hits.append(hit)
            }
        }
        return hits
    }

    private func normalized(_ rect: CGRect) -> CGRect {
        CGRect(
            x: min(rect.minX, rect.maxX),
            y: min(rect.minY, rect.maxY),
            width: abs(rect.width),
            height: abs(rect.height)
        )
    }
}

public protocol ViewportIdentityBufferRendering: AnyObject {
    func render(
        plan: ViewportIdentityPickRenderPlan,
        viewportSize: CGSize
    ) throws -> ViewportIdentityBuffer
}

public final class ViewportIdentityBufferRenderer {
    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let pipelineState: any MTLComputePipelineState
    private var commandEncoder: ViewportIdentityBufferCommandEncoder

    public init(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()) throws {
        guard let device else {
            throw ViewportIdentityBufferRendererError.deviceUnavailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw ViewportIdentityBufferRendererError.commandQueueCreationFailed
        }
        let library: any MTLLibrary
        do {
            library = try device.makeLibrary(
                source: Self.shaderSource,
                options: nil
            )
        } catch {
            throw ViewportIdentityBufferRendererError.libraryCreationFailed(
                String(describing: error)
            )
        }
        let functionName = "viewportIdentityPickKernel"
        guard let function = library.makeFunction(name: functionName) else {
            throw ViewportIdentityBufferRendererError.functionUnavailable(functionName)
        }
        let pipelineState: any MTLComputePipelineState
        do {
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            throw ViewportIdentityBufferRendererError.pipelineCreationFailed(
                String(describing: error)
            )
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.commandEncoder = ViewportIdentityBufferCommandEncoder()
    }

    public func render(
        plan: ViewportIdentityPickRenderPlan,
        viewportSize: CGSize
    ) throws -> ViewportIdentityBuffer {
        let totalStart = Self.timestamp()
        let size = try renderSize(for: viewportSize)
        let encodeStart = Self.timestamp()
        let encodedPlan = try commandEncoder.encode(plan: plan)
        let encodeDurationSeconds = Self.duration(since: encodeStart)
        let commandBuffer = try makeCommandBuffer()
        let texture = try makeTexture(width: size.width, height: size.height)
        let commandBufferCommands = encodedPlan.commands.isEmpty
            ? [ViewportIdentityMetalCommand.empty]
            : encodedPlan.commands
        let commandBufferPoints = encodedPlan.points.isEmpty
            ? [ViewportIdentityMetalPoint.empty]
            : encodedPlan.points
        let commandsBuffer = try makeBuffer(from: commandBufferCommands)
        let pointsBuffer = try makeBuffer(from: commandBufferPoints)
        var parameters = ViewportIdentityMetalParameters(
            commandCount: UInt32(encodedPlan.commands.count),
            width: UInt32(size.width),
            height: UInt32(size.height),
            padding: 0
        )

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ViewportIdentityBufferRendererError.computeEncoderCreationFailed
        }
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(commandsBuffer, offset: 0, index: 0)
        encoder.setBuffer(pointsBuffer, offset: 0, index: 1)
        encoder.setBytes(
            &parameters,
            length: MemoryLayout<ViewportIdentityMetalParameters>.stride,
            index: 2
        )
        encoder.setTexture(texture, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: size.width, height: size.height, depth: 1),
            threadsPerThreadgroup: threadsPerThreadgroup()
        )
        encoder.endEncoding()

        let gpuStart = Self.timestamp()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let gpuDurationSeconds = Self.duration(since: gpuStart)
        if let error = commandBuffer.error {
            throw ViewportIdentityBufferRendererError.commandExecutionFailed(
                String(describing: error)
            )
        }

        let readbackStart = Self.timestamp()
        let rawValues = readTexture(texture, width: size.width, height: size.height)
        let readbackDurationSeconds = Self.duration(since: readbackStart)
        let totalDurationSeconds = Self.duration(since: totalStart)
        let metrics = ViewportIdentityBufferRenderMetrics(
            viewportWidth: size.width,
            viewportHeight: size.height,
            encodedCommandCount: encodedPlan.commands.count,
            encodedPointCount: encodedPlan.points.count,
            encodedMeshPrimitiveCacheHitCount: encodedPlan.meshPrimitiveCacheHitCount,
            encodedMeshPrimitiveCacheMissCount: encodedPlan.meshPrimitiveCacheMissCount,
            pixelCount: size.width * size.height,
            encodeDurationSeconds: encodeDurationSeconds,
            gpuDurationSeconds: gpuDurationSeconds,
            readbackDurationSeconds: readbackDurationSeconds,
            totalDurationSeconds: totalDurationSeconds
        )
        return ViewportIdentityBuffer(
            width: size.width,
            height: size.height,
            rawValues: rawValues,
            index: plan.index,
            renderMetrics: metrics
        )
    }

    public func sample(
        point: CGPoint,
        plan: ViewportIdentityPickRenderPlan,
        viewportSize: CGSize
    ) throws -> ViewportIdentityBufferSample {
        let buffer = try render(plan: plan, viewportSize: viewportSize)
        return try buffer.sample(at: point)
    }

    private func renderSize(for viewportSize: CGSize) throws -> (width: Int, height: Int) {
        guard viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              viewportSize.width > 0.0,
              viewportSize.height > 0.0 else {
            throw ViewportIdentityBufferRendererError.invalidViewportSize
        }
        return (
            width: max(Int(ceil(viewportSize.width)), 1),
            height: max(Int(ceil(viewportSize.height)), 1)
        )
    }

    private static func timestamp() -> TimeInterval {
        Date.timeIntervalSinceReferenceDate
    }

    private static func duration(since start: TimeInterval) -> Double {
        max(timestamp() - start, 0.0)
    }

    private func makeCommandBuffer() throws -> any MTLCommandBuffer {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ViewportIdentityBufferRendererError.commandBufferCreationFailed
        }
        return commandBuffer
    }

    private func makeTexture(width: Int, height: Int) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Uint,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw ViewportIdentityBufferRendererError.textureCreationFailed
        }
        return texture
    }

    private func makeBuffer<T>(from values: [T]) throws -> any MTLBuffer {
        try values.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw ViewportIdentityBufferRendererError.bufferCreationFailed
            }
            guard let buffer = device.makeBuffer(
                bytes: baseAddress,
                length: rawBuffer.count,
                options: .storageModeShared
            ) else {
                throw ViewportIdentityBufferRendererError.bufferCreationFailed
            }
            return buffer
        }
    }

    private func threadsPerThreadgroup() -> MTLSize {
        let width = pipelineState.threadExecutionWidth
        let height = max(pipelineState.maxTotalThreadsPerThreadgroup / max(width, 1), 1)
        return MTLSize(width: width, height: height, depth: 1)
    }

    private func readTexture(
        _ texture: any MTLTexture,
        width: Int,
        height: Int
    ) -> [UInt32] {
        var rawValues = Array(
            repeating: ViewportPickIdentity.backgroundRawValue,
            count: width * height
        )
        let bytesPerRow = width * MemoryLayout<UInt32>.stride
        rawValues.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            texture.getBytes(
                baseAddress,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        return rawValues
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct PickCommand {
        uint kind;
        uint identity;
        uint pointStart;
        uint pointCount;
        float radius;
        float priority;
        float depth;
        float order;
    };

    struct PickPoint {
        float x;
        float y;
    };

    struct PickParameters {
        uint commandCount;
        uint width;
        uint height;
        uint padding;
    };

    static float2 pointAt(const device PickPoint *points, uint index) {
        PickPoint point = points[index];
        return float2(point.x, point.y);
    }

    static float distanceToSegment(float2 point, float2 start, float2 end) {
        float2 segment = end - start;
        float lengthSquared = dot(segment, segment);
        if (lengthSquared <= 1.0e-6) {
            return length(point - start);
        }
        float t = clamp(dot(point - start, segment) / lengthSquared, 0.0, 1.0);
        return length(point - (start + segment * t));
    }

    static bool containsPolygonPoint(
        float2 point,
        const device PickPoint *points,
        uint pointStart,
        uint pointCount
    ) {
        if (pointCount < 3) {
            return false;
        }
        bool inside = false;
        for (uint index = 0; index < pointCount; index += 1) {
            float2 current = pointAt(points, pointStart + index);
            float2 previous = pointAt(
                points,
                pointStart + ((index + pointCount - 1) % pointCount)
            );
            bool crossesY = (current.y > point.y) != (previous.y > point.y);
            if (!crossesY) {
                continue;
            }
            float crossingX = (previous.x - current.x) * (point.y - current.y)
                / (previous.y - current.y)
                + current.x;
            if (point.x < crossingX) {
                inside = !inside;
            }
        }
        return inside;
    }

    static bool hitsPolyline(
        float2 point,
        const device PickPoint *points,
        uint pointStart,
        uint pointCount,
        float radius,
        bool isClosed
    ) {
        if (pointCount < 2) {
            return false;
        }
        for (uint index = 0; index + 1 < pointCount; index += 1) {
            float2 start = pointAt(points, pointStart + index);
            float2 end = pointAt(points, pointStart + index + 1);
            if (distanceToSegment(point, start, end) <= radius) {
                return true;
            }
        }
        if (isClosed) {
            float2 start = pointAt(points, pointStart + pointCount - 1);
            float2 end = pointAt(points, pointStart);
            if (distanceToSegment(point, start, end) <= radius) {
                return true;
            }
        }
        return false;
    }

    kernel void viewportIdentityPickKernel(
        const device PickCommand *commands [[buffer(0)]],
        const device PickPoint *points [[buffer(1)]],
        constant PickParameters &parameters [[buffer(2)]],
        texture2d<uint, access::write> output [[texture(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= parameters.width || gid.y >= parameters.height) {
            return;
        }

        float2 point = float2(float(gid.x) + 0.5, float(gid.y) + 0.5);
        uint selectedIdentity = 0;
        float selectedPriority = -1.0;
        float selectedDepth = -INFINITY;
        float selectedOrder = -1.0;
        bool selectedHasDepth = false;
        for (uint commandIndex = 0; commandIndex < parameters.commandCount; commandIndex += 1) {
            PickCommand command = commands[commandIndex];
            bool hit = false;
            if (command.kind == 0) {
                hit = containsPolygonPoint(
                    point,
                    points,
                    command.pointStart,
                    command.pointCount
                );
            } else if (command.kind == 1) {
                hit = hitsPolyline(
                    point,
                    points,
                    command.pointStart,
                    command.pointCount,
                    command.radius,
                    false
                );
            } else if (command.kind == 2) {
                hit = hitsPolyline(
                    point,
                    points,
                    command.pointStart,
                    command.pointCount,
                    command.radius,
                    true
                );
            } else if (command.kind == 3 && command.pointCount >= 2) {
                hit = distanceToSegment(
                    point,
                    pointAt(points, command.pointStart),
                    pointAt(points, command.pointStart + 1)
                ) <= command.radius;
            } else if (command.kind == 4 && command.pointCount >= 1) {
                hit = length(point - pointAt(points, command.pointStart)) <= command.radius;
            }

            if (hit) {
                bool hasDepth = isfinite(command.depth);
                bool isBetter = false;
                if (command.priority > selectedPriority + 1.0e-6) {
                    isBetter = true;
                } else if (abs(command.priority - selectedPriority) <= 1.0e-6) {
                    if (hasDepth && selectedHasDepth && abs(command.depth - selectedDepth) > 1.0e-6) {
                        isBetter = command.depth > selectedDepth;
                    } else if (hasDepth && !selectedHasDepth) {
                        isBetter = true;
                    } else if (command.order > selectedOrder) {
                        isBetter = true;
                    }
                }
                if (isBetter) {
                    selectedIdentity = command.identity;
                    selectedPriority = command.priority;
                    selectedDepth = command.depth;
                    selectedOrder = command.order;
                    selectedHasDepth = hasDepth;
                }
            }
        }

        output.write(uint4(selectedIdentity, 0, 0, 0), gid);
    }
    """
}

private struct ViewportIdentityMetalPoint {
    var x: Float
    var y: Float

    static var empty: ViewportIdentityMetalPoint {
        ViewportIdentityMetalPoint(x: 0.0, y: 0.0)
    }
}

extension ViewportIdentityBufferRenderer: ViewportIdentityBufferRendering {}

public extension ViewportIdentityHitResolver.RenderBudget {
    static func deviceCalibrated(
        for device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()
    ) -> ViewportIdentityHitResolver.RenderBudget {
        guard let device else {
            return .unavailableDeviceFallback
        }
        return .deviceCalibrated(
            recommendedMaxWorkingSetSize: device.recommendedMaxWorkingSetSize,
            isLowPower: device.isLowPower,
            hasUnifiedMemory: device.hasUnifiedMemory
        )
    }
}

private struct ViewportIdentityMetalCommand {
    var kind: UInt32
    var identity: UInt32
    var pointStart: UInt32
    var pointCount: UInt32
    var radius: Float
    var priority: Float
    var depth: Float
    var order: Float

    static var empty: ViewportIdentityMetalCommand {
        ViewportIdentityMetalCommand(
            kind: 0,
            identity: ViewportPickIdentity.backgroundRawValue,
            pointStart: 0,
            pointCount: 0,
            radius: 0.0,
            priority: 0.0,
            depth: Float.nan,
            order: 0.0
        )
    }
}

private struct ViewportIdentityMetalParameters {
    var commandCount: UInt32
    var width: UInt32
    var height: UInt32
    var padding: UInt32
}

private struct ViewportIdentityEncodedPlan {
    var commands: [ViewportIdentityMetalCommand]
    var points: [ViewportIdentityMetalPoint]
    var meshPrimitiveCacheHitCount: Int
    var meshPrimitiveCacheMissCount: Int
}

private struct ViewportIdentityEncodedPrimitive {
    var kind: UInt32
    var points: [ViewportIdentityMetalPoint]
    var radius: Float
}

private struct ViewportIdentityMeshPrimitiveCacheKey: Hashable {
    var storageIdentity: ViewportBodyMesh.StorageIdentity
    var primitiveIndex: Int
    var fingerprint: ViewportIdentityProjectedTriangleFingerprint
}

private struct ViewportIdentityProjectedTriangleFingerprint: Hashable {
    var firstX: UInt64
    var firstY: UInt64
    var secondX: UInt64
    var secondY: UInt64
    var thirdX: UInt64
    var thirdY: UInt64

    init?(_ primitive: ViewportIdentityPickPrimitive) {
        guard case .polygon(let points) = primitive,
              points.count == 3 else {
            return nil
        }
        self.firstX = Self.bitPattern(points[0].x)
        self.firstY = Self.bitPattern(points[0].y)
        self.secondX = Self.bitPattern(points[1].x)
        self.secondY = Self.bitPattern(points[1].y)
        self.thirdX = Self.bitPattern(points[2].x)
        self.thirdY = Self.bitPattern(points[2].y)
    }

    private static func bitPattern(_ value: CGFloat) -> UInt64 {
        Double(value).bitPattern
    }
}

private struct ViewportIdentityEncodedPrimitiveCacheEntry {
    var primitive: ViewportIdentityEncodedPrimitive
    var lastUsedGeneration: UInt64
}

private struct ViewportIdentityBufferCommandEncoder {
    private var meshPrimitiveCache: [
        ViewportIdentityMeshPrimitiveCacheKey: ViewportIdentityEncodedPrimitiveCacheEntry
    ] = [:]
    private var cacheGeneration: UInt64 = 0
    private var maximumCachedMeshPrimitiveCount: Int = 16_384

    mutating func encode(plan: ViewportIdentityPickRenderPlan) throws -> ViewportIdentityEncodedPlan {
        advanceCacheGeneration()
        var commands: [ViewportIdentityMetalCommand] = []
        var points: [ViewportIdentityMetalPoint] = []
        var cacheHitCount = 0
        var cacheMissCount = 0
        commands.reserveCapacity(plan.drawItems.count)
        points.reserveCapacity(plan.encodedPointCount)

        for (order, item) in plan.drawItems.enumerated() {
            let pointStart = UInt32(points.count)
            let encoded = encodedPrimitive(
                for: item,
                cacheHitCount: &cacheHitCount,
                cacheMissCount: &cacheMissCount
            )
            points.append(contentsOf: encoded.points)
            commands.append(
                ViewportIdentityMetalCommand(
                    kind: encoded.kind,
                    identity: item.identity.rawValue,
                    pointStart: pointStart,
                    pointCount: UInt32(encoded.points.count),
                    radius: encoded.radius,
                    priority: priority(for: item.geometry),
                    depth: item.depth.map(Float.init) ?? Float.nan,
                    order: Float(order)
                )
            )
        }
        return ViewportIdentityEncodedPlan(
            commands: commands,
            points: points,
            meshPrimitiveCacheHitCount: cacheHitCount,
            meshPrimitiveCacheMissCount: cacheMissCount
        )
    }

    private mutating func advanceCacheGeneration() {
        guard cacheGeneration < UInt64.max else {
            cacheGeneration = 1
            meshPrimitiveCache.removeAll(keepingCapacity: true)
            return
        }
        cacheGeneration += 1
    }

    private mutating func encodedPrimitive(
        for item: ViewportIdentityPickDrawItem,
        cacheHitCount: inout Int,
        cacheMissCount: inout Int
    ) -> ViewportIdentityEncodedPrimitive {
        guard let key = meshPrimitiveCacheKey(for: item) else {
            return encodePrimitive(item.primitive)
        }

        if var entry = meshPrimitiveCache[key] {
            entry.lastUsedGeneration = cacheGeneration
            meshPrimitiveCache[key] = entry
            cacheHitCount += 1
            return entry.primitive
        }

        let encoded = encodePrimitive(item.primitive)
        cacheMissCount += 1
        store(encoded, for: key)
        return encoded
    }

    private func meshPrimitiveCacheKey(
        for item: ViewportIdentityPickDrawItem
    ) -> ViewportIdentityMeshPrimitiveCacheKey? {
        guard let storageIdentity = item.meshStorageIdentity,
              let primitiveIndex = item.meshPrimitiveIndex,
              let fingerprint = ViewportIdentityProjectedTriangleFingerprint(item.primitive) else {
            return nil
        }
        return ViewportIdentityMeshPrimitiveCacheKey(
            storageIdentity: storageIdentity,
            primitiveIndex: primitiveIndex,
            fingerprint: fingerprint
        )
    }

    private mutating func store(
        _ primitive: ViewportIdentityEncodedPrimitive,
        for key: ViewportIdentityMeshPrimitiveCacheKey
    ) {
        guard maximumCachedMeshPrimitiveCount > 0 else {
            return
        }
        if meshPrimitiveCache.count >= maximumCachedMeshPrimitiveCount {
            evictLeastRecentlyUsedMeshPrimitives()
        }
        meshPrimitiveCache[key] = ViewportIdentityEncodedPrimitiveCacheEntry(
            primitive: primitive,
            lastUsedGeneration: cacheGeneration
        )
    }

    private mutating func evictLeastRecentlyUsedMeshPrimitives() {
        let evictionCount = max(maximumCachedMeshPrimitiveCount / 4, 1)
        let targetCount = max(maximumCachedMeshPrimitiveCount - evictionCount, 0)
        let removeCount = max(meshPrimitiveCache.count - targetCount, 1)
        let keys = meshPrimitiveCache
            .sorted { lhs, rhs in
                lhs.value.lastUsedGeneration < rhs.value.lastUsedGeneration
            }
            .prefix(removeCount)
            .map(\.key)
        for key in keys {
            meshPrimitiveCache.removeValue(forKey: key)
        }
    }

    private func encodePrimitive(
        _ primitive: ViewportIdentityPickPrimitive
    ) -> ViewportIdentityEncodedPrimitive {
        switch primitive {
        case .polygon(let points):
            return ViewportIdentityEncodedPrimitive(
                kind: 0,
                points: points.map(metalPoint),
                radius: 0.0
            )
        case .polyline(let points, let radius, let isClosed):
            return ViewportIdentityEncodedPrimitive(
                kind: isClosed ? 2 : 1,
                points: points.map(metalPoint),
                radius: Float(radius)
            )
        case .segment(let start, let end, let radius):
            return ViewportIdentityEncodedPrimitive(
                kind: 3,
                points: [metalPoint(start), metalPoint(end)],
                radius: Float(radius)
            )
        case .point(let center, let radius):
            return ViewportIdentityEncodedPrimitive(
                kind: 4,
                points: [metalPoint(center)],
                radius: Float(radius)
            )
        }
    }

    private func metalPoint(_ point: CGPoint) -> ViewportIdentityMetalPoint {
        ViewportIdentityMetalPoint(
            x: Float(point.x),
            y: Float(point.y)
        )
    }

    private func priority(for geometry: ViewportIdentityPickGeometry) -> Float {
        switch geometry {
        case .body:
            return 0.0
        case .sketchRegion, .generatedFace, .projectedBodyFace:
            return 10.0
        case .sketchEntity, .generatedEdge, .projectedBodyEdge:
            return 20.0
        case .sketchControlPoint,
             .generatedVertex,
             .surfaceKnot,
             .surfaceSpan,
             .surfaceTrimKnot,
             .surfaceTrimSpan,
             .projectedBodyVertex:
            return 30.0
        }
    }
}
