import CoreGraphics
import RupaCore
import RupaViewportScene

@MainActor
public final class ViewportIdentityHitResolver {
    public typealias RendererFactory = () throws -> any ViewportIdentityBufferRendering

    public enum ResolutionStatus: String, Codable, Equatable, Sendable {
        case renderedIdentityBuffer
        case reusedIdentityBuffer
        case fellBackAfterBudgetRejection
        case fellBackAfterRendererUnavailable
        case fellBackAfterInvalidViewportSize
        case fellBackAfterInvalidRenderedBuffer
        case fellBackAfterRendererFailure
    }

    public enum RenderBudgetLimit: String, Codable, Equatable, Sendable {
        case pixelCount
        case drawItemCount
        case encodedPointCount
        case estimatedResidentByteCount
    }

    public enum RenderBudgetCalibration: String, Codable, Equatable, Sendable {
        case fixedStandard
        case lowPowerUnifiedMemory
        case unifiedMemory
        case discreteOrHighThroughput
        case unavailableDeviceFallback

        public var title: String {
            switch self {
            case .fixedStandard:
                "Fixed standard"
            case .lowPowerUnifiedMemory:
                "Low-power unified memory"
            case .unifiedMemory:
                "Unified memory"
            case .discreteOrHighThroughput:
                "Discrete or high-throughput"
            case .unavailableDeviceFallback:
                "Metal unavailable fallback"
            }
        }
    }

    public struct RenderCost: Codable, Equatable, Sendable {
        public static let identityTextureBytesPerPixel = 4
        public static let identityReadbackBytesPerPixel = 4
        public static let commandBufferBytesPerDrawItem = 32
        public static let pointBufferBytesPerEncodedPoint = 8
        public static let identityIndexBytesPerRecord = MemoryLayout<ViewportIdentityPickRecord>.stride * 2
        public static let parameterBufferByteCount = 16

        public var viewportWidth: Int
        public var viewportHeight: Int
        public var pixelCount: Int
        public var drawItemCount: Int
        public var encodedPointCount: Int
        public var identityRecordCount: Int

        public init(
            viewportWidth: Int,
            viewportHeight: Int,
            pixelCount: Int,
            drawItemCount: Int,
            encodedPointCount: Int,
            identityRecordCount: Int
        ) {
            self.viewportWidth = viewportWidth
            self.viewportHeight = viewportHeight
            self.pixelCount = pixelCount
            self.drawItemCount = drawItemCount
            self.encodedPointCount = encodedPointCount
            self.identityRecordCount = identityRecordCount
        }

        public var estimatedTextureByteCount: Int {
            Self.saturatedProduct(pixelCount, Self.identityTextureBytesPerPixel)
        }

        public var estimatedReadbackByteCount: Int {
            Self.saturatedProduct(pixelCount, Self.identityReadbackBytesPerPixel)
        }

        public var estimatedCommandBufferByteCount: Int {
            Self.saturatedProduct(drawItemCount, Self.commandBufferBytesPerDrawItem)
        }

        public var estimatedPointBufferByteCount: Int {
            Self.saturatedProduct(encodedPointCount, Self.pointBufferBytesPerEncodedPoint)
        }

        public var estimatedIdentityIndexByteCount: Int {
            Self.saturatedProduct(identityRecordCount, Self.identityIndexBytesPerRecord)
        }

        public var estimatedResidentByteCount: Int {
            let pixelBuffers = Self.saturatedAdd(
                estimatedTextureByteCount,
                estimatedReadbackByteCount
            )
            let encodedBuffers = Self.saturatedAdd(
                estimatedCommandBufferByteCount,
                estimatedPointBufferByteCount
            )
            let planBuffers = Self.saturatedAdd(
                encodedBuffers,
                estimatedIdentityIndexByteCount
            )
            return Self.saturatedAdd(
                Self.saturatedAdd(pixelBuffers, planBuffers),
                Self.parameterBufferByteCount
            )
        }

        static func saturatedProduct(_ value: Int, _ multiplier: Int) -> Int {
            let lhs = Swift.max(value, 0)
            let rhs = Swift.max(multiplier, 0)
            let result = lhs.multipliedReportingOverflow(by: rhs)
            return result.overflow ? Int.max : result.partialValue
        }

        static func saturatedAdd(_ lhs: Int, _ rhs: Int) -> Int {
            let result = Swift.max(lhs, 0).addingReportingOverflow(Swift.max(rhs, 0))
            if result.overflow {
                return Int.max
            }
            return result.partialValue
        }
    }

    public struct RenderBudget: Codable, Equatable, Sendable {
        public static let megabyte = 1024 * 1024
        public static let standardMaximumEstimatedResidentByteCount = 96 * 1024 * 1024

        public var calibration: RenderBudgetCalibration
        public var maximumPixelCount: Int
        public var maximumDrawItemCount: Int
        public var maximumEncodedPointCount: Int
        public var maximumEstimatedResidentByteCount: Int

        public init(
            calibration: RenderBudgetCalibration = .fixedStandard,
            maximumPixelCount: Int = 8_294_400,
            maximumDrawItemCount: Int = 200_000,
            maximumEncodedPointCount: Int = 1_000_000,
            maximumEstimatedResidentByteCount: Int = Self.standardMaximumEstimatedResidentByteCount
        ) {
            self.calibration = calibration
            self.maximumPixelCount = maximumPixelCount
            self.maximumDrawItemCount = maximumDrawItemCount
            self.maximumEncodedPointCount = maximumEncodedPointCount
            self.maximumEstimatedResidentByteCount = maximumEstimatedResidentByteCount
        }

        public static let standard = RenderBudget()

        public static let lowPowerUnifiedMemory = RenderBudget(
            calibration: .lowPowerUnifiedMemory,
            maximumPixelCount: 4_147_200,
            maximumDrawItemCount: 120_000,
            maximumEncodedPointCount: 600_000,
            maximumEstimatedResidentByteCount: 64 * megabyte
        )

        public static let unifiedMemory = RenderBudget(
            calibration: .unifiedMemory,
            maximumPixelCount: 8_294_400,
            maximumDrawItemCount: 240_000,
            maximumEncodedPointCount: 1_200_000,
            maximumEstimatedResidentByteCount: 128 * megabyte
        )

        public static let discreteOrHighThroughput = RenderBudget(
            calibration: .discreteOrHighThroughput,
            maximumPixelCount: 14_745_600,
            maximumDrawItemCount: 480_000,
            maximumEncodedPointCount: 2_400_000,
            maximumEstimatedResidentByteCount: 256 * megabyte
        )

        public static let unavailableDeviceFallback = RenderBudget(
            calibration: .unavailableDeviceFallback,
            maximumPixelCount: 4_147_200,
            maximumDrawItemCount: 120_000,
            maximumEncodedPointCount: 600_000,
            maximumEstimatedResidentByteCount: 64 * megabyte
        )

        public static func deviceCalibrated(
            recommendedMaxWorkingSetSize: UInt64?,
            isLowPower: Bool,
            hasUnifiedMemory: Bool
        ) -> RenderBudget {
            let base: RenderBudget
            if isLowPower {
                base = .lowPowerUnifiedMemory
            } else if hasUnifiedMemory {
                base = .unifiedMemory
            } else {
                base = .discreteOrHighThroughput
            }
            return base.withResidentMemoryCeiling(
                recommendedMaxWorkingSetSize: recommendedMaxWorkingSetSize
            )
        }

        public func rejection(for cost: RenderCost) -> RenderBudgetRejection? {
            if cost.pixelCount > max(maximumPixelCount, 0) {
                return RenderBudgetRejection(
                    calibration: calibration,
                    limit: .pixelCount,
                    actual: cost.pixelCount,
                    maximum: max(maximumPixelCount, 0),
                    cost: cost
                )
            }
            if cost.drawItemCount > max(maximumDrawItemCount, 0) {
                return RenderBudgetRejection(
                    calibration: calibration,
                    limit: .drawItemCount,
                    actual: cost.drawItemCount,
                    maximum: max(maximumDrawItemCount, 0),
                    cost: cost
                )
            }
            if cost.encodedPointCount > max(maximumEncodedPointCount, 0) {
                return RenderBudgetRejection(
                    calibration: calibration,
                    limit: .encodedPointCount,
                    actual: cost.encodedPointCount,
                    maximum: max(maximumEncodedPointCount, 0),
                    cost: cost
                )
            }
            if cost.estimatedResidentByteCount > max(maximumEstimatedResidentByteCount, 0) {
                return RenderBudgetRejection(
                    calibration: calibration,
                    limit: .estimatedResidentByteCount,
                    actual: cost.estimatedResidentByteCount,
                    maximum: max(maximumEstimatedResidentByteCount, 0),
                    cost: cost
                )
            }
            return nil
        }

        private func withResidentMemoryCeiling(
            recommendedMaxWorkingSetSize: UInt64?
        ) -> RenderBudget {
            var adjusted = self
            guard let recommendedMaxWorkingSetSize,
                  recommendedMaxWorkingSetSize > 0 else {
                return adjusted
            }
            let estimatedWorkingSetBudget = recommendedMaxWorkingSetSize / 64
            let boundedWorkingSetBudget = min(
                UInt64(Int.max),
                max(UInt64(32 * Self.megabyte), estimatedWorkingSetBudget)
            )
            let residentBudget = min(
                UInt64(maximumEstimatedResidentByteCount),
                boundedWorkingSetBudget
            )
            adjusted.maximumEstimatedResidentByteCount = max(
                32 * Self.megabyte,
                Int(residentBudget)
            )
            return adjusted
        }
    }

    public struct RenderBudgetRejection: Codable, Equatable, Sendable {
        public var calibration: RenderBudgetCalibration
        public var limit: RenderBudgetLimit
        public var actual: Int
        public var maximum: Int
        public var cost: RenderCost

        public init(
            calibration: RenderBudgetCalibration = .fixedStandard,
            limit: RenderBudgetLimit,
            actual: Int,
            maximum: Int,
            cost: RenderCost
        ) {
            self.calibration = calibration
            self.limit = limit
            self.actual = actual
            self.maximum = maximum
            self.cost = cost
        }
    }

    public struct ResolutionSummary: Codable, Equatable, Sendable {
        public var status: ResolutionStatus
        public var renderBudgetCalibration: RenderBudgetCalibration
        public var renderCost: RenderCost?
        public var renderMetrics: ViewportIdentityBufferRenderMetrics?
        public var budgetRejection: RenderBudgetRejection?

        public init(
            status: ResolutionStatus,
            renderBudgetCalibration: RenderBudgetCalibration = .fixedStandard,
            renderCost: RenderCost? = nil,
            renderMetrics: ViewportIdentityBufferRenderMetrics? = nil,
            budgetRejection: RenderBudgetRejection? = nil
        ) {
            self.status = status
            self.renderBudgetCalibration = renderBudgetCalibration
            self.renderCost = renderCost
            self.renderMetrics = renderMetrics
            self.budgetRejection = budgetRejection
        }
    }

    private struct CacheKey: Equatable {
        var scene: ViewportScene
        var layout: ViewportLayout
        var sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy
        var selectionHitPolicy: ViewportSelectionHitPolicy
    }

    private struct Cache {
        var key: CacheKey
        var buffer: ViewportIdentityBuffer
        var cost: RenderCost
    }

    private enum ResolverError: Error {
        case budgetExceeded(RenderBudgetRejection)
        case invalidRenderedBuffer
    }

    private var renderer: (any ViewportIdentityBufferRendering)?
    private var cached: Cache?
    private let rendererFactory: RendererFactory
    private let renderBudget: RenderBudget
    public private(set) var lastRenderMetrics: ViewportIdentityBufferRenderMetrics?
    public private(set) var lastRenderCost: RenderCost?
    public private(set) var lastBudgetRejection: RenderBudgetRejection?
    public private(set) var lastResolutionSummary: ResolutionSummary?

    public var lastResolutionStatus: ResolutionStatus? {
        lastResolutionSummary?.status
    }

    public init(
        rendererFactory: @escaping RendererFactory = { try ViewportIdentityBufferRenderer() },
        renderBudget: RenderBudget = .standard
    ) {
        self.rendererFactory = rendererFactory
        self.renderBudget = renderBudget
    }

    public func hitTest(
        point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all
    ) -> ViewportHit? {
        do {
            return try identityHit(
                point: point,
                in: scene,
                layout: layout,
                selectionHitPolicy: selectionHitPolicy
            )
        } catch {
            recordFallback(from: error)
            return ViewportHitTester().hitTest(
                point: point,
                in: scene,
                layout: layout,
                selectionHitPolicy: selectionHitPolicy
            )
        }
    }

    public func selectionHits(
        in rect: CGRect,
        scene: ViewportScene,
        layout: ViewportLayout,
        sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy = .all,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all
    ) -> [ViewportHit] {
        do {
            let buffer = try identityBuffer(
                for: scene,
                layout: layout,
                sketchControlPointHitPolicy: sketchControlPointHitPolicy,
                selectionHitPolicy: selectionHitPolicy
            )
            return buffer.hits(in: rect)
        } catch {
            recordFallback(from: error)
            return ViewportSelectionRectangleHitTester().hits(
                in: rect,
                scene: scene,
                layout: layout,
                sketchControlPointHitPolicy: sketchControlPointHitPolicy,
                selectionHitPolicy: selectionHitPolicy
            )
        }
    }

    public func invalidate() {
        cached = nil
        lastRenderMetrics = nil
        lastRenderCost = nil
        lastBudgetRejection = nil
        lastResolutionSummary = nil
    }

    private func identityHit(
        point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout,
        selectionHitPolicy: ViewportSelectionHitPolicy
    ) throws -> ViewportHit? {
        let buffer = try identityBuffer(
            for: scene,
            layout: layout,
            sketchControlPointHitPolicy: .all,
            selectionHitPolicy: selectionHitPolicy
        )
        return try buffer.sample(at: point).hit
    }

    private func identityBuffer(
        for scene: ViewportScene,
        layout: ViewportLayout,
        sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy,
        selectionHitPolicy: ViewportSelectionHitPolicy
    ) throws -> ViewportIdentityBuffer {
        let renderSize = try Self.renderSize(for: layout.viewportSize)
        let key = CacheKey(
            scene: scene,
            layout: layout,
            sketchControlPointHitPolicy: sketchControlPointHitPolicy,
            selectionHitPolicy: selectionHitPolicy
        )
        if let cached,
           cached.key == key,
           reusable(cached, renderSize: renderSize) {
            recordResolution(
                .reusedIdentityBuffer,
                renderCost: cached.cost,
                renderMetrics: cached.buffer.renderMetrics
            )
            return cached.buffer
        }

        let index = ViewportIdentityPickIndexBuilder(
            sketchControlPointHitPolicy: sketchControlPointHitPolicy,
            selectionHitPolicy: selectionHitPolicy
        )
        .build(scene: scene)
        let planBuilder = ViewportIdentityPickRenderPlanBuilder()
        let planEstimate = planBuilder.estimate(
            scene: scene,
            layout: layout,
            index: index,
            selectionHitPolicy: selectionHitPolicy
        )
        let cost = RenderCost(
            viewportWidth: renderSize.width,
            viewportHeight: renderSize.height,
            pixelCount: RenderCost.saturatedProduct(renderSize.width, renderSize.height),
            drawItemCount: planEstimate.drawItemCount,
            encodedPointCount: planEstimate.encodedPointCount,
            identityRecordCount: index.count
        )
        lastRenderCost = cost
        lastRenderMetrics = nil
        lastBudgetRejection = nil
        lastResolutionSummary = nil
        if let rejection = renderBudget.rejection(for: cost) {
            recordResolution(
                .fellBackAfterBudgetRejection,
                renderCost: cost,
                budgetRejection: rejection
            )
            throw ResolverError.budgetExceeded(rejection)
        }
        let plan = planBuilder.build(
            scene: scene,
            layout: layout,
            index: index,
            selectionHitPolicy: selectionHitPolicy
        )
        let buffer = try identityRenderer().render(
            plan: plan,
            viewportSize: layout.viewportSize
        )
        guard renderedBufferMatches(buffer, cost: cost) else {
            recordResolution(.fellBackAfterInvalidRenderedBuffer, renderCost: cost)
            throw ResolverError.invalidRenderedBuffer
        }
        recordResolution(
            .renderedIdentityBuffer,
            renderCost: cost,
            renderMetrics: buffer.renderMetrics
        )
        cached = Cache(key: key, buffer: buffer, cost: cost)
        return buffer
    }

    private func recordResolution(
        _ status: ResolutionStatus,
        renderCost: RenderCost? = nil,
        renderMetrics: ViewportIdentityBufferRenderMetrics? = nil,
        budgetRejection: RenderBudgetRejection? = nil
    ) {
        lastRenderCost = renderCost
        lastRenderMetrics = renderMetrics
        lastBudgetRejection = budgetRejection
        lastResolutionSummary = ResolutionSummary(
            status: status,
            renderBudgetCalibration: renderBudget.calibration,
            renderCost: renderCost,
            renderMetrics: renderMetrics,
            budgetRejection: budgetRejection
        )
    }

    private func recordFallback(from error: Error) {
        if let resolverError = error as? ResolverError {
            switch resolverError {
            case .budgetExceeded(let rejection):
                recordResolution(
                    .fellBackAfterBudgetRejection,
                    renderCost: rejection.cost,
                    budgetRejection: rejection
                )
            case .invalidRenderedBuffer:
                recordResolution(.fellBackAfterInvalidRenderedBuffer, renderCost: lastRenderCost)
            }
            return
        }

        guard let rendererError = error as? ViewportIdentityBufferRendererError else {
            recordResolution(.fellBackAfterRendererFailure, renderCost: lastRenderCost)
            return
        }
        switch rendererError {
        case .invalidViewportSize:
            recordResolution(.fellBackAfterInvalidViewportSize, renderCost: lastRenderCost)
        case .deviceUnavailable:
            recordResolution(.fellBackAfterRendererUnavailable, renderCost: lastRenderCost)
        default:
            recordResolution(.fellBackAfterRendererFailure, renderCost: lastRenderCost)
        }
    }

    private func identityRenderer() throws -> any ViewportIdentityBufferRendering {
        if let renderer {
            return renderer
        }
        let renderer = try rendererFactory()
        self.renderer = renderer
        return renderer
    }

    private func reusable(
        _ cache: Cache,
        renderSize: (width: Int, height: Int)
    ) -> Bool {
        guard cache.cost.viewportWidth == renderSize.width,
              cache.cost.viewportHeight == renderSize.height,
              cache.cost.pixelCount == renderSize.width * renderSize.height,
              cache.cost.identityRecordCount == cache.buffer.index.count,
              renderBudget.rejection(for: cache.cost) == nil else {
            return false
        }
        return renderedBufferMatches(cache.buffer, cost: cache.cost)
    }

    private func renderedBufferMatches(
        _ buffer: ViewportIdentityBuffer,
        cost: RenderCost
    ) -> Bool {
        buffer.width == cost.viewportWidth
            && buffer.height == cost.viewportHeight
            && buffer.rawValues.count == cost.pixelCount
    }

    private static func renderSize(for viewportSize: CGSize) throws -> (width: Int, height: Int) {
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
}
