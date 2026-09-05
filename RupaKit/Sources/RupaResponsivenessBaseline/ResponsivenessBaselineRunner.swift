import CoreGraphics
import Darwin
import Foundation
import RupaRendering
import RupaViewportScene
import SwiftCAD
import SwiftUI

/// Measures the production presentation path against the RupaRendering
/// performance acceptance table.
///
/// The runner executes the same public types the production cache and Canvas
/// closure execute. It never re-implements triangulation, projection, or plan
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
              configuration.viewportSize.height >= 1.0 else {
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
            let plan = try preparePlan(scene: fixture.scene)
            planTriangleCount = plan.triangleCount
            _ = try measureDrawWork(plan: plan, layout: layout)
        }

        var samples: [ResponsivenessIterationSample] = []
        samples.reserveCapacity(configuration.iterationCount)
        for index in 0..<configuration.iterationCount {
            let clock = ContinuousClock()
            // Publication is exactly one construction. Construction validates
            // every range, transform, and index while it transforms each source
            // vertex once, so the cache publishes the result without a second
            // traversal to measure.
            let constructionStart = clock.now
            let plan = try MeshSourcePresentationRenderPlan(scene: fixture.scene)
            let constructionEnd = clock.now
            let draw = try measureDrawWork(plan: plan, layout: layout)

            let preparation = seconds(constructionStart.duration(to: constructionEnd))
            planTriangleCount = plan.triangleCount
            samples.append(
                ResponsivenessIterationSample(
                    index: index,
                    preparationSeconds: preparation,
                    positionCount: plan.positionCount,
                    retainedByteCount: plan.retainedByteCount,
                    drawWorkSeconds: draw.seconds,
                    mainActorBlockedSeconds: preparation + draw.seconds,
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

    private func preparePlan(
        scene: UniversalViewportScene
    ) throws -> MeshSourcePresentationRenderPlan {
        try MeshSourcePresentationRenderPlan(scene: scene)
    }

    private struct DrawWorkMeasurement {
        var seconds: Double
        var projectedPointCount: Int
        var pathCount: Int
        var fillCount: Int
        var strokeCount: Int
    }

    /// Reproduces the Canvas closure's per-triangle work.
    ///
    /// `GraphicsContext` exists only inside a live `Canvas`, so the fill and
    /// stroke submissions are counted rather than issued. The reported duration
    /// is therefore a lower bound on the production Canvas interval.
    private func measureDrawWork(
        plan: MeshSourcePresentationRenderPlan,
        layout: ViewportLayout
    ) throws -> DrawWorkMeasurement {
        var projectedPointCount = 0
        var pathCount = 0
        var fillCount = 0
        var strokeCount = 0
        var boundsChecksum = 0.0
        let clock = ContinuousClock()
        let start = clock.now
        try MeshSourcePresentationRenderer().render(plan: plan) { triangle in
            let first = Point3D(
                x: triangle.firstPosition.x,
                y: triangle.firstPosition.y,
                z: triangle.firstPosition.z
            )
            let second = Point3D(
                x: triangle.secondPosition.x,
                y: triangle.secondPosition.y,
                z: triangle.secondPosition.z
            )
            let third = Point3D(
                x: triangle.thirdPosition.x,
                y: triangle.thirdPosition.y,
                z: triangle.thirdPosition.z
            )
            var path = Path()
            path.move(to: layout.project(first))
            path.addLine(to: layout.project(second))
            path.addLine(to: layout.project(third))
            path.closeSubpath()
            projectedPointCount += 3
            pathCount += 1
            // The production closure submits one fill and one stroke per
            // triangle. Both are counted here.
            fillCount += 1
            strokeCount += 1
            // Consuming the path keeps the construction observable so it is not
            // eliminated as dead work.
            boundsChecksum += path.boundingRect.width
        }
        let end = clock.now
        guard boundsChecksum.isFinite else {
            throw ResponsivenessBaselineError(
                code: .planConsumptionFailed,
                message: "Projected triangle bounds were not finite."
            )
        }
        return DrawWorkMeasurement(
            seconds: seconds(start.duration(to: end)),
            projectedPointCount: projectedPointCount,
            pathCount: pathCount,
            fillCount: fillCount,
            strokeCount: strokeCount
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
        let plan = try preparePlan(scene: scene)
        await sampler.stop()
        let peak = try sampler.peakBytes()
        let retained = try ResponsivenessFootprintProbe.physicalFootprintBytes()
        withExtendedLifetime(plan) {}
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
        let worstPreparation = samples.map(\.preparationSeconds).max() ?? 0.0
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

        rows.append(
            ResponsivenessRowResult(
                row: .mainActorStatePublication,
                verdict: worstPreparation > frameInterval / 2.0 ? .rejects : .accepts,
                measured: Self.milliseconds(worstPreparation),
                threshold: Self.milliseconds(frameInterval / 2.0),
                detail: """
                    Worst of \(samples.count) measured iterations. Publication is the \
                    single synchronous plan construction the cache performs before \
                    it returns a result. The row is defined over one uninterrupted \
                    publication, so a single measured iteration decides it.
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
                detail: drawRejects
                    ? """
                        Worst of \(samples.count) measured iterations. The measured \
                        interval excludes the counted fill and stroke submissions, so \
                        it is a lower bound and the row rejects on the lower bound \
                        alone.
                        """
                    : """
                        The measured interval excludes the \(samples.last?.fillCount ?? 0) \
                        fill and \(samples.last?.strokeCount ?? 0) stroke submissions per \
                        frame, because GraphicsContext exists only inside a live Canvas. \
                        A lower bound below the threshold cannot establish acceptance; \
                        the signed-application run owns this row.
                        """
            )
        )

        rows.append(
            ResponsivenessRowResult(
                row: .planReadiness,
                verdict: Self.verdict(
                    exceeds: worstPreparation > 2.0,
                    hasFullRunSeries: hasFullRunSeries
                ),
                measured: Self.milliseconds(worstPreparation),
                threshold: Self.milliseconds(2.0),
                detail: """
                    Readiness is measured from the first request for a plan to its \
                    availability. The production cache prepares synchronously, so \
                    readiness equals the preparation interval.\(seriesNote)
                    """
            )
        )

        let cancellationThreshold = 6.0 * frameInterval
        rows.append(
            ResponsivenessRowResult(
                row: .cancellation,
                verdict: worstPreparation > cancellationThreshold ? .rejects : .accepts,
                measured: Self.milliseconds(worstPreparation),
                threshold: Self.milliseconds(cancellationThreshold),
                detail: """
                    The production preparation is a synchronous MainActor call with no \
                    cancellation point, so the earliest a cancellation request can take \
                    effect is when that call returns. The measured value is therefore \
                    the preparation interval itself, not a separately observed \
                    cancellation latency.
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
