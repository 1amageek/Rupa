import CoreGraphics
import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

/// Attributes the latency a hover or press pays inside the legacy identity
/// picking backend to the four intervals it actually spends time in: pick index
/// and render plan construction on the main actor, GPU command encoding, GPU
/// execution including the synchronous wait, and the full-frame readback.
///
/// The measurement drives the production `ViewportIdentityHitResolver` against
/// scenes produced by `ViewportSceneBuilder`, so the encoded draw command count
/// matches what placed CAD bodies actually produce. Every sample asserts the
/// resolution status, because a budget rejection or renderer failure silently
/// substitutes the CPU hit tester and would otherwise be timed as if it were the
/// identity path.
///
/// Reported numbers are lower bounds for the application: this harness pays no
/// SwiftUI update, no AppKit tracking-area dispatch, and no competing GPU work.
/// A rejection here stays valid for the application; an acceptance does not.
@Suite(.serialized)
@MainActor
struct ViewportIdentityHitResolverLatencyMeasurements {
    /// Matches the viewport size the responsiveness acceptance table is stated
    /// against, so pixel-count-driven cost is comparable with it.
    private static let viewportSize = CGSize(width: 1512.0, height: 900.0)

    /// Each reported interval is the median of this many independent runs. A
    /// single run mixes first-touch allocation and GPU warm-up into the sample.
    private static let repeatCount = 7

    struct Sample {
        var label: String
        var status: ViewportIdentityHitResolver.ResolutionStatus?
        var drawItemCount: Int
        var encodedCommandCount: Int
        var pixelCount: Int
        var resolverSeconds: Double
        /// Everything the run spent outside `render(plan:viewportSize:)`: pick
        /// index construction, cost estimation, and render plan building. Held
        /// per run rather than derived from reduced intervals, because a
        /// difference of independent medians is not a measurement of anything.
        var planSeconds: Double
        var encodeSeconds: Double
        var gpuSeconds: Double
        var readbackSeconds: Double

        var description: String {
            String(
                format: """
                %@ | status=%@ commands=%d pixels=%d \
                total=%.2fms plan=%.2fms encode=%.2fms gpu=%.2fms readback=%.2fms
                """,
                label,
                status.map(\.rawValue) ?? "none",
                encodedCommandCount,
                pixelCount,
                resolverSeconds * 1000.0,
                planSeconds * 1000.0,
                encodeSeconds * 1000.0,
                gpuSeconds * 1000.0,
                readbackSeconds * 1000.0
            )
        }
    }

    @Test(.timeLimit(.minutes(5)))
    func identityPickingLatencySplitsAcrossPlanBuildGPUAndReadback() throws {
        let placed = try Self.makeScene(boxCount: 24)
        let layout = try #require(
            ViewportLayout(scene: placed.scene, size: Self.viewportSize)
        )
        let enlargedScene = try Self.appendBox(to: placed.session, index: 24)
        let enlargedLayout = try #require(
            ViewportLayout(scene: enlargedScene, size: Self.viewportSize)
        )
        // Identical scene, different camera: the orbit and zoom case, where the
        // model is untouched but `ViewportLayout` still changes the cache key.
        let movedLayout = try #require(
            ViewportLayout(
                scene: placed.scene,
                size: Self.viewportSize,
                camera: ViewportCamera(zoom: 1.4, pan: CGSize(width: 24.0, height: -18.0))
            )
        )
        let probePoint = CGPoint(
            x: Self.viewportSize.width / 2.0,
            y: Self.viewportSize.height / 2.0
        )

        // An invalidated cache on a warmed resolver: this is the interval a
        // hover pays the first time a camera or model change drops the key.
        let coldMiss = Self.measureColdMiss(
            label: "cold-miss",
            point: probePoint,
            scene: placed.scene,
            layout: layout
        )
        let cameraChange = Self.measureColdMiss(
            label: "camera-change",
            point: probePoint,
            scene: placed.scene,
            layout: movedLayout
        )
        // One more body, so both the scene items and the layout's `modelBounds`
        // change and the encoded command count grows.
        let afterPlacement = Self.measureColdMiss(
            label: "after-placement",
            point: probePoint,
            scene: enlargedScene,
            layout: enlargedLayout
        )
        // The same key on a warmed resolver: only the `CacheKey` structural
        // compare and the buffer sample remain.
        let warmReuse = Self.measureWarmReuse(
            label: "warm-reuse",
            point: probePoint,
            scene: placed.scene,
            layout: layout
        )

        for sample in [coldMiss, cameraChange, afterPlacement, warmReuse] {
            print("IDENTITY-LATENCY \(sample.description)")
        }

        // The measurement is only meaningful if the identity backend actually
        // ran. A fallback would time `ViewportHitTester` instead.
        #expect(coldMiss.status == .renderedIdentityBuffer)
        #expect(cameraChange.status == .renderedIdentityBuffer)
        #expect(afterPlacement.status == .renderedIdentityBuffer)
        #expect(warmReuse.status == .reusedIdentityBuffer)
        #expect(afterPlacement.encodedCommandCount > coldMiss.encodedCommandCount)
    }

    @Test(.timeLimit(.minutes(10)))
    func identityPickingLatencyScalesWithSceneAndViewportSize() throws {
        let probeSizes: [CGSize] = [
            CGSize(width: 756.0, height: 450.0),
            Self.viewportSize,
            CGSize(width: 3024.0, height: 1800.0)
        ]
        var samples: [Sample] = []

        for boxCount in [1, 8, 32] {
            let placed = try Self.makeScene(boxCount: boxCount)
            for size in probeSizes {
                let layout = try #require(ViewportLayout(scene: placed.scene, size: size))
                samples.append(
                    Self.measureColdMiss(
                        label: "boxes=\(boxCount) size=\(Int(size.width))x\(Int(size.height))",
                        point: CGPoint(x: size.width / 2.0, y: size.height / 2.0),
                        scene: placed.scene,
                        layout: layout
                    )
                )
            }
        }

        for sample in samples {
            print("IDENTITY-SCALING \(sample.description)")
        }

        // Every sample must have exercised the identity backend; a silent budget
        // rejection would make the scaling curve describe the CPU tester.
        #expect(samples.allSatisfy { $0.status == .renderedIdentityBuffer })
    }

    // MARK: - Measurement

    /// Times a cache miss on a resolver that has already built its renderer,
    /// which is what the application pays: the resolver is view state, so the
    /// `MTLDevice`, library, and pipeline are created once and every later
    /// camera or model change invalidates only the cached buffer. A fresh
    /// resolver per run would charge Metal object creation to plan building.
    private static func measureColdMiss(
        label: String,
        point: CGPoint,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> Sample {
        let resolver = ViewportIdentityHitResolver(renderBudget: .deviceCalibrated())
        _ = run(resolver: resolver, point: point, scene: scene, layout: layout)
        let runs = (0..<repeatCount).map { _ -> Sample in
            resolver.invalidate()
            return run(resolver: resolver, point: point, scene: scene, layout: layout)
        }
        return median(label: label, runs: runs)
    }

    /// Times repeated queries against one warmed resolver, where the cache key
    /// matches and no render happens. The cached buffer still carries the render
    /// metrics of the run that produced it, so the render intervals are reported
    /// as zero: no GPU work is performed on a reuse.
    private static func measureWarmReuse(
        label: String,
        point: CGPoint,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> Sample {
        let resolver = ViewportIdentityHitResolver(renderBudget: .deviceCalibrated())
        _ = run(resolver: resolver, point: point, scene: scene, layout: layout)
        let runs = (0..<repeatCount).map { _ in
            var sample = run(resolver: resolver, point: point, scene: scene, layout: layout)
            sample.planSeconds = sample.resolverSeconds
            sample.encodeSeconds = 0.0
            sample.gpuSeconds = 0.0
            sample.readbackSeconds = 0.0
            return sample
        }
        return median(label: label, runs: runs)
    }

    private static func run(
        resolver: ViewportIdentityHitResolver,
        point: CGPoint,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> Sample {
        let clock = ContinuousClock()
        let start = clock.now
        _ = resolver.hitTest(point: point, in: scene, layout: layout)
        let elapsed = clock.now - start
        let summary = resolver.lastResolutionSummary
        let metrics = summary?.renderMetrics
        let resolverSeconds = seconds(elapsed)
        let renderSeconds = (metrics?.encodeDurationSeconds ?? 0.0)
            + (metrics?.gpuDurationSeconds ?? 0.0)
            + (metrics?.readbackDurationSeconds ?? 0.0)
        return Sample(
            label: "",
            status: summary?.status,
            drawItemCount: summary?.renderCost?.drawItemCount ?? 0,
            encodedCommandCount: metrics?.encodedCommandCount ?? 0,
            pixelCount: summary?.renderCost?.pixelCount ?? 0,
            resolverSeconds: resolverSeconds,
            planSeconds: max(resolverSeconds - renderSeconds, 0.0),
            encodeSeconds: metrics?.encodeDurationSeconds ?? 0.0,
            gpuSeconds: metrics?.gpuDurationSeconds ?? 0.0,
            readbackSeconds: metrics?.readbackDurationSeconds ?? 0.0
        )
    }

    /// Each interval is reduced independently, so the reported intervals come
    /// from different runs and are not expected to sum to the reported total.
    /// Plan time is reduced as a per-run measurement rather than derived from
    /// the other medians, so it stays a real interval of a real run.
    private static func median(label: String, runs: [Sample]) -> Sample {
        precondition(runs.isEmpty == false)
        let representative = runs[runs.count / 2]
        return Sample(
            label: label,
            status: representative.status,
            drawItemCount: representative.drawItemCount,
            encodedCommandCount: representative.encodedCommandCount,
            pixelCount: representative.pixelCount,
            resolverSeconds: median(runs.map(\.resolverSeconds)),
            planSeconds: median(runs.map(\.planSeconds)),
            encodeSeconds: median(runs.map(\.encodeSeconds)),
            gpuSeconds: median(runs.map(\.gpuSeconds)),
            readbackSeconds: median(runs.map(\.readbackSeconds))
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) * 1.0e-18
    }

    // MARK: - Fixtures

    private struct PlacedScene {
        var session: EditorSession
        var scene: ViewportScene
    }

    /// Places `boxCount` solids through the same command the canvas placement
    /// tool uses, then builds the scene with the production builder.
    private static func makeScene(boxCount: Int) throws -> PlacedScene {
        let session = EditorSession()
        for index in 0..<boxCount {
            _ = try placeBox(in: session, index: index)
        }
        return PlacedScene(session: session, scene: buildScene(for: session))
    }

    private static func appendBox(to session: EditorSession, index: Int) throws -> ViewportScene {
        _ = try placeBox(in: session, index: index)
        return buildScene(for: session)
    }

    @discardableResult
    private static func placeBox(in session: EditorSession, index: Int) throws -> CommandExecutionResult {
        let column = Double(index % 8)
        let row = Double(index / 8)
        return try #require(
            session.createExtrudedRectangleFromCanvasClick(
                centerModelPoint: Point2D(x: column * 0.05, y: row * 0.05),
                sketchPlane: .xy
            )
        )
    }

    private static func buildScene(for session: EditorSession) -> ViewportScene {
        ViewportSceneBuilder().build(
            document: session.document,
            ruler: session.workspaceState.ruler
        )
    }
}
