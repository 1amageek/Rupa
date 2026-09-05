import CoreGraphics
import Darwin
import Foundation
import Metal
import RupaRendering
import RupaViewportScene
import SwiftCAD
import SwiftUI

/// Measures the production presentation path against the RupaRendering
/// performance acceptance table.
///
/// The runner executes the same public types as the production cache and native
/// surface encoder. It never re-implements triangulation, projection, or plan
/// construction, so a measured number describes production work rather than a
/// model of it.
@MainActor
public struct ResponsivenessBaselineRunner {
    public struct Configuration: Sendable {
        public var fixture: ResponsivenessFixture.Parameters
        public var warmupCount: Int
        public var iterationCount: Int
        public var viewportSize: CGSize
        public var footprintSamplingIntervalSeconds: Double
        public var environment: ResponsivenessEnvironment
        public var rupaKitRevision: String
        public var swiftCADRevision: String

        public init(
            fixture: ResponsivenessFixture.Parameters = .standard,
            warmupCount: Int = 1,
            iterationCount: Int = 10,
            viewportSize: CGSize = CGSize(width: 1440.0, height: 900.0),
            footprintSamplingIntervalSeconds: Double = 0.001,
            environment: ResponsivenessEnvironment,
            rupaKitRevision: String,
            swiftCADRevision: String
        ) {
            self.fixture = fixture
            self.warmupCount = warmupCount
            self.iterationCount = iterationCount
            self.viewportSize = viewportSize
            self.footprintSamplingIntervalSeconds = footprintSamplingIntervalSeconds
            self.environment = environment
            self.rupaKitRevision = rupaKitRevision
            self.swiftCADRevision = swiftCADRevision
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration) throws {
        guard configuration.warmupCount >= 1 else {
            throw ResponsivenessBaselineError(
                code: .invalidMeasurementRequest,
                message: "At least one warm-up iteration is required."
            )
        }
        guard configuration.iterationCount >= 1 else {
            throw ResponsivenessBaselineError(
                code: .invalidMeasurementRequest,
                message: "At least one measured iteration is required."
            )
        }
        guard configuration.viewportSize.width >= 1.0,
              configuration.viewportSize.height >= 1.0,
              configuration.viewportSize.width.isFinite,
              configuration.viewportSize.height.isFinite,
              configuration.viewportSize.width <= 16_384,
              configuration.viewportSize.height <= 16_384 else {
            throw ResponsivenessBaselineError(
                code: .invalidMeasurementRequest,
                message: "The viewport size must be at least one point in each dimension."
            )
        }
        guard configuration.footprintSamplingIntervalSeconds > 0.0,
              configuration.footprintSamplingIntervalSeconds.isFinite else {
            throw ResponsivenessBaselineError(
                code: .invalidMeasurementRequest,
                message: "The footprint sampling interval must be a positive number of seconds."
            )
        }
        guard configuration.rupaKitRevision.isEmpty == false,
              configuration.swiftCADRevision.isEmpty == false else {
            throw ResponsivenessBaselineError(
                code: .invalidMeasurementRequest,
                message: "Both repository revisions are required, because two reports are only comparable when they were taken from the same sources."
            )
        }
        self.configuration = configuration
    }

    public func run() async throws -> ResponsivenessBaselineReport {
        let fixture = try ResponsivenessFixture.build(configuration.fixture)
        let layout = makeLayout(for: configuration.fixture)

        // Warm-up runs are discarded so first-touch page faults and lazily
        // initialized runtime state are not attributed to a measured iteration.
        var planTriangleCount = 0
        for _ in 0..<configuration.warmupCount {
            // The warm-up mirrors the measured shape, detached construction
            // included, so first-touch faults land where the measured
            // iterations will pay them rather than in a different context.
            let preparation = try await measurePreparation(scene: fixture.scene)
            planTriangleCount = preparation.plan.triangleCount
            _ = try await measureDrawWork(surface: preparation.surface, layout: layout)
        }

        var samples: [ResponsivenessIterationSample] = []
        samples.reserveCapacity(configuration.iterationCount)
        for index in 0..<configuration.iterationCount {
            // Construction runs off `MainActor` and publication is the state
            // assignment that follows it, so the two are timed separately and
            // only the publication is charged to a frame.
            let preparation = try await measurePreparation(scene: fixture.scene)
            let plan = preparation.plan
            let draw = try await measureDrawWork(surface: preparation.surface, layout: layout)

            planTriangleCount = plan.triangleCount
            samples.append(
                ResponsivenessIterationSample(
                    index: index,
                    constructionSeconds: preparation.constructionSeconds,
                    publicationSeconds: preparation.publicationSeconds,
                    readinessSeconds: preparation.readinessSeconds,
                    positionCount: plan.positionCount,
                    retainedByteCount: plan.retainedByteCount,
                    workingByteCount: plan.workingByteCount,
                    drawWorkSeconds: draw.seconds,
                    gpuCompletionSeconds: draw.gpuCompletionSeconds,
                    mainActorBlockedSeconds: preparation.publicationSeconds + draw.seconds,
                    triangleCount: plan.triangleCount,
                    projectedPointCount: draw.projectedPointCount,
                    pathCount: draw.pathCount,
                    fillCount: draw.fillCount,
                    strokeCount: draw.strokeCount
                )
            )
        }

        let footprint = try await measureFootprint(scene: fixture.scene)
        let rows = evaluateAcceptance(samples: samples, footprint: footprint)

        return ResponsivenessBaselineReport(
            fixture: fixture.parameters,
            contentDigest: fixture.contentDigest,
            sceneItemCount: fixture.scene.items.count,
            vertexCount: fixture.vertexCount,
            faceCount: fixture.faceCount,
            planTriangleCount: planTriangleCount,
            predictedTriangleCount: fixture.parameters.predictedTriangleCount,
            warmupCount: configuration.warmupCount,
            environment: configuration.environment,
            environmentDerivationRule: ResponsivenessEnvironment.derivationRule,
            samples: samples,
            footprint: footprint,
            rows: rows,
            context: Self.makeContext(
                rupaKitRevision: configuration.rupaKitRevision,
                swiftCADRevision: configuration.swiftCADRevision
            )
        )
    }

    // MARK: - Measurement

    private struct PreparationMeasurement {
        var plan: MeshSourcePresentationRenderPlan
        var surface: ViewportSurfaceRenderer
        var constructionSeconds: Double
        var publicationSeconds: Double
        var readinessSeconds: Double
    }

    /// Holds one published plan so the timed assignment stores the same enum
    /// payload the production cache stores, and so the store stays observable
    /// to the read that follows it.
    @MainActor
    private final class PublicationTarget {
        enum State {
            case idle
            case ready(MeshSourcePresentationRenderPlan, ViewportSurfaceRenderer)
        }

        var state: State = .idle
    }

    /// Reproduces the production preparation shape: the cache starts a detached
    /// task that constructs the plan off `MainActor`, then publishes the
    /// completed plan with one `MainActor` state assignment.
    ///
    /// Construction is timed inside the detached closure, so task scheduling is
    /// not charged to it. Readiness spans the request through the publication,
    /// so that scheduling is charged somewhere rather than nowhere. The
    /// publication measured here is a plain stored-property assignment; the
    /// production cache assigns an `@Observable` property inside a live
    /// observation scope, whose invalidation this process cannot drive, so the
    /// publication figure is a lower bound of the production interval.
    private func measurePreparation(
        scene: UniversalViewportScene
    ) async throws -> PreparationMeasurement {
        let clock = ContinuousClock()
        let requestStart = clock.now
        let construction = Task.detached(priority: .userInitiated) {
            let start = clock.now
            let plan = try MeshSourcePresentationRenderPlan(scene: scene)
            let surface = try ViewportSurfaceRenderer(plan: plan)
            return (plan: plan, surface: surface, duration: start.duration(to: clock.now))
        }
        let constructed: (plan: MeshSourcePresentationRenderPlan, surface: ViewportSurfaceRenderer, duration: Duration)
        do {
            constructed = try await construction.value
        } catch {
            throw ResponsivenessBaselineError(
                code: .planPreparationFailed,
                message: "Detached plan construction failed: \(error)"
            )
        }

        let target = PublicationTarget()
        let publicationStart = clock.now
        target.state = .ready(constructed.plan, constructed.surface)
        let publicationEnd = clock.now
        guard case let .ready(published, surface) = target.state else {
            throw ResponsivenessBaselineError(
                code: .planPreparationFailed,
                message: "The published state did not hold the constructed plan."
            )
        }

        return PreparationMeasurement(
            plan: published,
            surface: surface,
            constructionSeconds: seconds(constructed.duration),
            publicationSeconds: seconds(publicationStart.duration(to: publicationEnd)),
            readinessSeconds: seconds(requestStart.duration(to: publicationEnd))
        )
    }

    private struct DrawWorkMeasurement {
        var seconds: Double
        var gpuCompletionSeconds: Double
        var projectedPointCount: Int
        var pathCount: Int
        var fillCount: Int
        var strokeCount: Int
    }

    /// Executes the production raster pass. GPU completion suspends MainActor.
    private func measureDrawWork(
        surface: ViewportSurfaceRenderer,
        layout: ViewportLayout
    ) async throws -> DrawWorkMeasurement {
        let width = Int(configuration.viewportSize.width.rounded(.up))
        let height = Int(configuration.viewportSize.height.rounded(.up))
        _ = try ViewportSurfaceRenderer.attachmentByteCount(width: width, height: height)
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        colorDescriptor.usage = .renderTarget
        colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: width, height: height, mipmapped: false
        )
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        guard let color = surface.device.makeTexture(descriptor: colorDescriptor),
              let depth = surface.device.makeTexture(descriptor: depthDescriptor) else {
            throw ResponsivenessBaselineError(
                code: .planConsumptionFailed, message: "Metal could not allocate bounded measurement attachments."
            )
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        let clock = ContinuousClock()
        let start = clock.now
        let buffer = try surface.makeCommandBuffer()
        var fillCount = 0
        try surface.encode(into: buffer, pass: pass, layout: layout, state: { _ in
            fillCount += 1
            return .normal
        })
        // Install completion before commit, then record submission time without
        // charging the suspended wait to the calling actor.
        let completed = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        buffer.addCompletedHandler { _ in
            completed.continuation.yield(())
            completed.continuation.finish()
        }
        buffer.commit()
        let encoded = clock.now
        for await _ in completed.stream { break }
        let end = clock.now
        guard buffer.status == .completed else {
            throw ResponsivenessBaselineError(
                code: .planConsumptionFailed,
                message: buffer.error?.localizedDescription ?? "Native surface GPU execution failed."
            )
        }
        return DrawWorkMeasurement(
            seconds: seconds(start.duration(to: encoded)),
            gpuCompletionSeconds: seconds(start.duration(to: end)),
            projectedPointCount: 0, pathCount: 0, fillCount: fillCount, strokeCount: 0
        )
    }

    private func measureFootprint(
        scene: UniversalViewportScene
    ) async throws -> ResponsivenessFootprintSample {
        let baseline = try ResponsivenessFootprintProbe.physicalFootprintBytes()
        let sampler = ResponsivenessFootprintPeakSampler(
            intervalSeconds: configuration.footprintSamplingIntervalSeconds
        )
        sampler.start()
        // The footprint pass prepares through the same detached path the timed
        // iterations use, so the peak the sampler observes is the peak of the
        // allocation production actually performs. Its timings are discarded.
        let preparation = try await measurePreparation(scene: scene)
        await sampler.stop()
        let peak = try sampler.peakBytes()
        let retained = try ResponsivenessFootprintProbe.physicalFootprintBytes()
        withExtendedLifetime(preparation) {}
        return ResponsivenessFootprintSample(
            baselineBytes: baseline,
            planRetainedBytes: retained,
            preparationPeakBytes: peak.bytes,
            peakSamplingIntervalSeconds: configuration.footprintSamplingIntervalSeconds,
            peakSampleCount: peak.sampleCount
        )
    }

    // MARK: - Acceptance

    private func evaluateAcceptance(
        samples: [ResponsivenessIterationSample],
        footprint: ResponsivenessFootprintSample
    ) -> [ResponsivenessRowResult] {
        let frameInterval = configuration.environment.frameIntervalSeconds
        let worstPublication = samples.map(\.publicationSeconds).max() ?? 0.0
        let worstReadiness = samples.map(\.readinessSeconds).max() ?? 0.0
        let worstDraw = samples.map(\.drawWorkSeconds).max() ?? 0.0
        let byteCeiling = configuration.environment.planByteCeiling
        // The Canvas consumption and plan readiness rows are the two the
        // acceptance table defines over ten consecutive post-warm-up runs. A
        // shorter series can still observe an exceedance, so it can reject, but
        // it cannot establish acceptance for those two rows.
        let hasFullRunSeries = samples.count >= Self.requiredRunCount
        let seriesNote = hasFullRunSeries
            ? ""
            : """
                 Only \(samples.count) of the \(Self.requiredRunCount) consecutive \
                post-warm-up runs the acceptance table requires were measured, so \
                this row cannot be accepted.
                """

        var rows: [ResponsivenessRowResult] = []

        let publicationRejects = worstPublication > frameInterval / 2.0
        rows.append(
            ResponsivenessRowResult(
                row: .mainActorStatePublication,
                verdict: publicationRejects ? .rejects : .notMeasured,
                measured: Self.milliseconds(worstPublication),
                threshold: Self.milliseconds(frameInterval / 2.0),
                detail: publicationRejects
                    ? """
                        Worst of \(samples.count) measured iterations. Publication is \
                        the state assignment that stores one already-constructed plan; \
                        construction itself ran off MainActor and is reported \
                        separately. The measured interval excludes the observation \
                        invalidation a live SwiftUI scope adds, so it is a lower bound \
                        and the row rejects on the lower bound alone.
                        """
                    : """
                        Worst of \(samples.count) measured iterations, against a \
                        construction interval of \
                        \(Self.milliseconds(samples.map(\.constructionSeconds).max() ?? 0.0)) \
                        that no longer runs on MainActor. The measured interval \
                        excludes the observation invalidation a live SwiftUI scope \
                        adds, because no observation scope exists in this process. A \
                        lower bound below the threshold cannot establish acceptance; \
                        the signed-application PresentationPlanPublication signpost \
                        owns this row.
                        """
            )
        )

        let drawRejects = worstDraw > frameInterval
        rows.append(
            ResponsivenessRowResult(
                row: .canvasConsumption,
                verdict: drawRejects ? .rejects : .notMeasured,
                measured: Self.milliseconds(worstDraw),
                threshold: Self.milliseconds(frameInterval),
                detail: """
                    Native Metal encoding/submission measured on MainActor; actual GPU
                    completion is recorded separately in every sample. Canvas grid,
                    interaction overlay fill/stroke and window presentation are excluded.
                    The signed-application run owns the complete frame acceptance row.
                    """
            )
        )

        rows.append(
            ResponsivenessRowResult(
                row: .planReadiness,
                verdict: Self.verdict(
                    exceeds: worstReadiness > 2.0,
                    hasFullRunSeries: hasFullRunSeries
                ),
                measured: Self.milliseconds(worstReadiness),
                threshold: Self.milliseconds(2.0),
                detail: """
                    Readiness is measured from the request for a plan to its \
                    publication, spanning the detached construction and the \
                    scheduling around it. Unlike the two MainActor intervals it is \
                    a whole measured span rather than a lower bound of one, so this \
                    row can be established here.\(seriesNote)
                    """
            )
        )

        let cancellationThreshold = 6.0 * frameInterval
        rows.append(
            ResponsivenessRowResult(
                row: .cancellation,
                verdict: .notMeasured,
                measured: "not measured",
                threshold: Self.milliseconds(cancellationThreshold),
                detail: """
                    No cancellation was requested and no cancellation latency was \
                    observed. Construction now runs in a cancellable detached task, so \
                    the latency is a property of that task rather than of the \
                    preparation interval, and reporting the preparation interval in its \
                    place would let a run that cancels nothing accept. A dedicated \
                    cancellation experiment owns this row.
                    """
            )
        )

        rows.append(
            Self.byteRow(
                row: .planRetainedBytes,
                deltaBytes: footprint.planRetainedDeltaBytes,
                ceiling: byteCeiling,
                detail: """
                    Sampled phys_footprint with exactly one plan retained, minus the \
                    footprint before preparation. The value is a resident-memory proxy, \
                    not the plan's exact allocation.
                    """
            )
        )

        rows.append(
            Self.byteRow(
                row: .planWorkingBytes,
                deltaBytes: footprint.preparationPeakDeltaBytes,
                ceiling: byteCeiling,
                detail: """
                    Peak sampled phys_footprint during preparation from \
                    \(footprint.peakSampleCount) samples at \
                    \(Self.milliseconds(footprint.peakSamplingIntervalSeconds)) intervals, \
                    minus the footprint before preparation. The value is a \
                    resident-memory proxy, not the plan's exact working allocation.
                    """
            )
        )

        return rows
    }

    /// The acceptance table is evaluated over a fixed series of consecutive
    /// post-warm-up runs.
    private static let requiredRunCount = 10

    private static func verdict(
        exceeds: Bool,
        hasFullRunSeries: Bool
    ) -> ResponsivenessVerdict {
        if exceeds {
            return .rejects
        }
        return hasFullRunSeries ? .accepts : .notMeasured
    }

    private static func byteRow(
        row: ResponsivenessAcceptanceRow,
        deltaBytes: Int64,
        ceiling: Double,
        detail: String
    ) -> ResponsivenessRowResult {
        guard deltaBytes > 0 else {
            return ResponsivenessRowResult(
                row: row,
                verdict: .notMeasured,
                measured: "\(deltaBytes) B",
                threshold: megabytes(ceiling),
                detail: """
                    \(detail) The sampled delta is not positive, so the sampler did not \
                    resolve this value and the row is not measured.
                    """
            )
        }
        // The delta is taken after a warm-up that already built and released an
        // identical plan, so the allocator can satisfy the new allocation from
        // pages it already holds. The delta is therefore a lower bound on the
        // plan's bytes: it can exceed the ceiling and reject, but it cannot
        // establish that the plan stays under it.
        let exceeds = Double(deltaBytes) > ceiling
        return ResponsivenessRowResult(
            row: row,
            verdict: exceeds ? .rejects : .notMeasured,
            measured: megabytes(Double(deltaBytes)),
            threshold: megabytes(ceiling),
            detail: exceeds
                ? """
                    \(detail) The delta is a lower bound and the row rejects on \
                    the lower bound alone.
                    """
                : """
                    \(detail) The warm-up already built and released an identical \
                    plan, so the allocator can satisfy this allocation from pages it \
                    already holds and the delta is a lower bound. A lower bound below \
                    the ceiling cannot establish acceptance; the signed-application \
                    footprint run owns this row.
                    """
        )
    }

    // MARK: - Support

    private func makeLayout(for parameters: ResponsivenessFixture.Parameters) -> ViewportLayout {
        var minimumX = Double.greatestFiniteMagnitude
        var maximumX = -Double.greatestFiniteMagnitude
        var maximumRadius = 0.0
        for index in 0..<parameters.bodyCount {
            let radius = parameters.baseRadiusMeters
                + parameters.radiusStepMeters * Double(index)
            let center = Double(index) * parameters.bodySpacingMeters
            minimumX = min(minimumX, center - radius)
            maximumX = max(maximumX, center + radius)
            maximumRadius = max(maximumRadius, radius)
        }
        let bounds = CGRect(
            x: minimumX,
            y: 0.0,
            width: maximumX - minimumX,
            height: parameters.lengthMeters
        )
        return ViewportLayout(
            modelBounds: bounds,
            size: configuration.viewportSize,
            verticalBounds: (-maximumRadius)...maximumRadius
        )
    }

    private func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1.0e18
    }

    private static func milliseconds(_ value: Double) -> String {
        String(format: "%.3f ms", value * 1000.0)
    }

    private static func megabytes(_ value: Double) -> String {
        String(format: "%.2f MB", value / (1024.0 * 1024.0))
    }

    private static func makeContext(
        rupaKitRevision: String,
        swiftCADRevision: String
    ) -> ResponsivenessReportContext {
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let processInfo = ProcessInfo.processInfo
        let formatter = ISO8601DateFormatter()
        return ResponsivenessReportContext(
            buildConfiguration: configuration,
            operatingSystemVersion: processInfo.operatingSystemVersionString,
            hostModel: hostModel(),
            physicalMemoryBytes: processInfo.physicalMemory,
            processorCount: processInfo.processorCount,
            recordedAt: formatter.string(from: Date()),
            rupaKitRevision: rupaKitRevision,
            swiftCADRevision: swiftCADRevision
        )
    }

    private static func hostModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return "unknown"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return "unknown"
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
