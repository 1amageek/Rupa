import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD

@main
struct PerformanceBenchmark {
    static func main() async throws {
        let options = try BenchmarkOptions(arguments: Array(CommandLine.arguments.dropFirst()))
        let transaction = makeBoxTransaction(bodyCount: options.bodyCount)
        let benchmarkSettings = DocumentModelingSettings.standard
        let validatedCADDocument = try makeValidatedCADDocument(
            transaction: transaction,
            tolerance: benchmarkSettings.tolerance
        )
        let evaluator = DocumentEvaluator(
            tolerance: benchmarkSettings.tolerance,
            tessellationOptions: benchmarkSettings.tessellationOptions,
            artifactPolicy: .deferred
        )
        let primaryFeatureID = try requiredPrimaryFeatureID(in: transaction)
        let kernelEditBenchmark = try KernelEditBenchmark(
            source: validatedCADDocument,
            featureID: primaryFeatureID,
            evaluator: evaluator
        )
        let coreEditBenchmark = try CoreEditBenchmark(transaction: transaction)
        let availableTelemetryWorkloads: [(
            name: String,
            measure: () async throws -> TimedTelemetry
        )] = [
            (
                "kernel_create_bodies",
                { try measureKernelCreate(
                    source: validatedCADDocument,
                    evaluator: evaluator,
                    expectedBodyCount: options.bodyCount
                ) }
            ),
            (
                "core_create_bodies",
                { try measureCoreCreate(transaction: transaction) }
            ),
            (
                "kernel_edit_one_body",
                { try kernelEditBenchmark.measure() }
            ),
            (
                "core_edit_one_body",
                { try coreEditBenchmark.measure() }
            ),
        ]
        let telemetryWorkloads = availableTelemetryWorkloads.filter {
            options.includes(workload: $0.name)
        }
        guard !telemetryWorkloads.isEmpty else {
            throw BenchmarkError.invalidArguments
        }

        for _ in 0..<options.warmupCount {
            for workload in telemetryWorkloads {
                _ = try await workload.measure()
            }
        }

        var samplesByWorkload: [String: [Double]] = [:]
        var telemetryByWorkload: [String: BenchmarkTelemetry] = [:]
        for workload in telemetryWorkloads {
            samplesByWorkload[workload.name] = []
            samplesByWorkload[workload.name]?.reserveCapacity(options.iterationCount)
        }
        for _ in 0..<options.iterationCount {
            for workload in telemetryWorkloads {
                let measurement = try await workload.measure()
                samplesByWorkload[workload.name, default: []].append(measurement.seconds)
                telemetryByWorkload[workload.name] = measurement.telemetry
            }
        }

        let report = BenchmarkReport(
            schemaVersion: 2,
            engine: "rupa",
            unit: "seconds",
            bodyCount: options.bodyCount,
            iterationCount: options.iterationCount,
            workloads: telemetryWorkloads.map { workload in
                BenchmarkWorkload(
                    name: workload.name,
                    statistics: BenchmarkStatistics(
                        samples: samplesByWorkload[workload.name, default: []]
                    ),
                    telemetry: telemetryByWorkload[workload.name]
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        guard let output = String(data: data, encoding: .utf8) else {
            throw BenchmarkError.outputEncodingFailed
        }
        print(output)
    }

    private static func makeValidatedCADDocument(
        transaction: FeatureGraphTransaction,
        tolerance: ModelingTolerance
    ) throws -> ValidatedCADDocument {
        var document = CADDocument(units: .meters)
        try document.appendFeatures(transaction.features, tolerance: tolerance)
        return try ValidatedCADDocument(document, tolerance: tolerance)
    }

    private static func requiredPrimaryFeatureID(
        in transaction: FeatureGraphTransaction
    ) throws -> FeatureID {
        guard let featureID = transaction.primaryFeatureID else {
            throw BenchmarkError.missingPrimaryFeature
        }
        return featureID
    }

    private static func measureKernelCreate(
        source: ValidatedCADDocument,
        evaluator: DocumentEvaluator,
        expectedBodyCount: Int
    ) throws -> TimedTelemetry {
        let start = ContinuousClock.now
        let evaluated = try evaluator.evaluate(source)
        let duration = start.duration(to: ContinuousClock.now)
        guard evaluated.brep.bodies.count == expectedBodyCount,
              evaluated.meshes.isEmpty,
              evaluated.evaluationMetrics.tessellatedBodyCount == 0 else {
            throw BenchmarkError.unexpectedBodyCount
        }
        return TimedTelemetry(
            seconds: duration.seconds,
            telemetry: BenchmarkTelemetry(evaluated.evaluationMetrics)
        )
    }

    private static func measureCoreCreate(
        transaction: FeatureGraphTransaction
    ) throws -> TimedTelemetry {
        let session = EditorSession()
        let initialEvaluationCount = session.store.completedEvaluationPassCount
        let initialHistoryCount = session.commandStack.undoEntries.count
        let start = ContinuousClock.now
        _ = try session.execute(.appendFeatureGraph(transaction))
        let duration = start.duration(to: ContinuousClock.now)
        guard session.evaluatedBodyCount == transaction.presentations.count,
              let metrics = session.store.currentModelingEvaluationMetrics else {
            throw BenchmarkError.unexpectedBodyCount
        }
        return TimedTelemetry(
            seconds: duration.seconds,
            telemetry: BenchmarkTelemetry(
                metrics,
                evaluationPassCount: session.store.completedEvaluationPassCount
                    - initialEvaluationCount,
                historyEntryCount: session.commandStack.undoEntries.count
                    - initialHistoryCount
            )
        )
    }

    private static func makeBoxTransaction(bodyCount: Int) -> FeatureGraphTransaction {
        var features: [FeatureNode] = []
        var presentations: [FeaturePresentation] = []
        features.reserveCapacity(bodyCount * 2)
        presentations.reserveCapacity(bodyCount)
        var primaryFeatureID: FeatureID?

        for index in 0..<bodyCount {
            let sketchFeatureID = FeatureID()
            let bodyFeatureID = FeatureID()
            let profile = ProfileReference(featureID: sketchFeatureID)
            var builder = SketchBuilder(on: .xy)
            builder.rectangle(
                width: .length(20.0, .millimeter),
                height: .length(10.0, .millimeter)
            )
            features.append(
                FeatureNode(
                    id: sketchFeatureID,
                    name: "Profile \(index)",
                    operation: .sketch(builder.build()),
                    outputs: [FeatureOutput(role: .profile)]
                )
            )
            features.append(
                FeatureNode(
                    id: bodyFeatureID,
                    name: "Body \(index)",
                    operation: .extrude(ExtrudeFeature(
                        profile: profile,
                        distance: .length(10.0, .millimeter),
                        direction: .normal,
                        operation: .newBody
                    )),
                    inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                )
            )
            presentations.append(
                FeaturePresentation(
                    featureID: bodyFeatureID,
                    sceneNodeID: SceneNodeID(),
                    name: "Body \(index)",
                    kind: .body(
                        sourceSection: .profile(profile),
                        typeID: nil,
                        geometryRole: .solid,
                        properties: ObjectPropertySet()
                    )
                )
            )
            primaryFeatureID = bodyFeatureID
        }
        return FeatureGraphTransaction(
            features: features,
            presentations: presentations,
            primaryFeatureID: primaryFeatureID
        )
    }
}

private final class KernelEditBenchmark {
    private var source: ValidatedCADDocument
    private var evaluated: EvaluatedDocument
    private let featureID: FeatureID
    private let evaluator: DocumentEvaluator
    private var usesExpandedDistance = false

    init(
        source: ValidatedCADDocument,
        featureID: FeatureID,
        evaluator: DocumentEvaluator
    ) throws {
        self.source = source
        self.evaluated = try evaluator.evaluate(source)
        self.featureID = featureID
        self.evaluator = evaluator
    }

    func measure() throws -> TimedTelemetry {
        guard var replacement = source.document.designGraph.nodes[featureID],
              case var .extrude(extrude) = replacement.operation else {
            throw BenchmarkError.missingPrimaryFeature
        }
        let distance = usesExpandedDistance ? 10.0 : 12.0
        extrude.distance = .length(distance, .millimeter)
        replacement.operation = .extrude(extrude)

        let start = ContinuousClock.now
        let updatedSource = try source.replacingGraphStableFeature(replacement)
        let updatedEvaluation = try evaluator.evaluate(updatedSource, reusing: evaluated)
        let duration = start.duration(to: ContinuousClock.now)
        guard updatedEvaluation.evaluationMetrics.rebuiltFeatureCount == 1,
              updatedEvaluation.brep.bodies.count == evaluated.brep.bodies.count,
              updatedEvaluation.meshes.isEmpty,
              updatedEvaluation.evaluationMetrics.tessellatedBodyCount == 0 else {
            throw BenchmarkError.unexpectedIncrementalEvaluation
        }
        source = updatedSource
        evaluated = updatedEvaluation
        usesExpandedDistance.toggle()
        return TimedTelemetry(
            seconds: duration.seconds,
            telemetry: BenchmarkTelemetry(updatedEvaluation.evaluationMetrics)
        )
    }
}

private final class CoreEditBenchmark {
    private let session: EditorSession
    private let featureID: FeatureID
    private var usesExpandedDistance = false

    init(transaction: FeatureGraphTransaction) throws {
        guard let featureID = transaction.primaryFeatureID else {
            throw BenchmarkError.missingPrimaryFeature
        }
        let session = EditorSession()
        _ = try session.execute(.appendFeatureGraph(transaction))
        self.session = session
        self.featureID = featureID
    }

    func measure() throws -> TimedTelemetry {
        let initialEvaluationCount = session.store.completedEvaluationPassCount
        let initialHistoryCount = session.commandStack.undoEntries.count
        let distance = usesExpandedDistance ? 10.0 : 12.0
        let start = ContinuousClock.now
        _ = try session.execute(.setExtrudeDistance(
            featureID: featureID,
            distance: .length(distance, .millimeter)
        ))
        let duration = start.duration(to: ContinuousClock.now)
        guard let metrics = session.store.currentModelingEvaluationMetrics else {
            throw BenchmarkError.unexpectedIncrementalEvaluation
        }
        usesExpandedDistance.toggle()
        return TimedTelemetry(
            seconds: duration.seconds,
            telemetry: BenchmarkTelemetry(
                metrics,
                evaluationPassCount: session.store.completedEvaluationPassCount
                    - initialEvaluationCount,
                historyEntryCount: session.commandStack.undoEntries.count
                    - initialHistoryCount
            )
        )
    }
}

private struct BenchmarkOptions {
    var bodyCount = 100
    var iterationCount = 7
    var warmupCount = 2
    var workloadName: String?

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count else {
                throw BenchmarkError.invalidArguments
            }
            switch arguments[index] {
            case "--body-count":
                bodyCount = try Self.positiveInteger(arguments[index + 1])
            case "--iterations":
                iterationCount = try Self.positiveInteger(arguments[index + 1])
            case "--warmups":
                guard let value = Int(arguments[index + 1]), value >= 0 else {
                    throw BenchmarkError.invalidArguments
                }
                warmupCount = value
            case "--workload":
                workloadName = arguments[index + 1]
            default:
                throw BenchmarkError.invalidArguments
            }
            index += 2
        }
    }

    func includes(workload name: String) -> Bool {
        workloadName == nil || workloadName == name
    }

    private static func positiveInteger(_ argument: String) throws -> Int {
        guard let value = Int(argument), value > 0 else {
            throw BenchmarkError.invalidArguments
        }
        return value
    }
}

private struct BenchmarkReport: Codable {
    var schemaVersion: Int
    var engine: String
    var unit: String
    var bodyCount: Int
    var iterationCount: Int
    var workloads: [BenchmarkWorkload]
}

private struct BenchmarkWorkload: Codable {
    var name: String
    var statistics: BenchmarkStatistics
    var telemetry: BenchmarkTelemetry?

    init(
        name: String,
        statistics: BenchmarkStatistics,
        telemetry: BenchmarkTelemetry? = nil
    ) {
        self.name = name
        self.statistics = statistics
        self.telemetry = telemetry
    }
}

private struct BenchmarkStatistics: Codable {
    var minimum: Double
    var median: Double
    var p95: Double
    var maximum: Double
    var samples: [Double]

    init(samples: [Double]) {
        let sorted = samples.sorted()
        self.minimum = sorted.first ?? 0.0
        self.median = Self.percentile(0.5, in: sorted)
        self.p95 = Self.percentile(0.95, in: sorted)
        self.maximum = sorted.last ?? 0.0
        self.samples = samples
    }

    private static func percentile(_ percentile: Double, in sorted: [Double]) -> Double {
        guard !sorted.isEmpty else {
            return 0.0
        }
        let rank = Int(ceil(percentile * Double(sorted.count))) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}

private struct BenchmarkTelemetry: Codable {
    var evaluationPassCount: UInt64
    var historyEntryCount: Int
    var totalFeatureCount: Int?
    var rebuiltFeatureCount: Int?
    var reusedFeatureCount: Int?
    var invalidatedFeatureCount: Int?
    var replayFallbackCount: Int?
    var tessellatedBodyCount: Int?
    var reusedMeshCount: Int?
    var scopedBodyReadCount: Int?
    var maximumScopedBodyReadCount: Int?
    var topologyMutationCount: Int?

    init(_ metrics: AutomationBatchMetrics) {
        evaluationPassCount = metrics.evaluationPassCount
        historyEntryCount = metrics.historyEntryCount
        totalFeatureCount = metrics.modelingEvaluation?.totalFeatureCount
        rebuiltFeatureCount = metrics.modelingEvaluation?.rebuiltFeatureCount
        reusedFeatureCount = metrics.modelingEvaluation?.reusedFeatureCount
        invalidatedFeatureCount = metrics.modelingEvaluation?.invalidatedFeatureCount
        replayFallbackCount = metrics.modelingEvaluation?.replayFallbackCount
        tessellatedBodyCount = metrics.modelingEvaluation?.tessellatedBodyCount
        reusedMeshCount = metrics.modelingEvaluation?.reusedMeshCount
        scopedBodyReadCount = metrics.modelingEvaluation?.scopedBodyReadCount
        maximumScopedBodyReadCount = metrics.modelingEvaluation?.maximumScopedBodyReadCount
        topologyMutationCount = metrics.modelingEvaluation?.topologyMutationCount
    }

    init(_ metrics: DocumentEvaluationMetrics) {
        evaluationPassCount = 1
        historyEntryCount = 0
        totalFeatureCount = metrics.totalFeatureCount
        rebuiltFeatureCount = metrics.rebuiltFeatureCount
        reusedFeatureCount = metrics.reusedFeatureCount
        invalidatedFeatureCount = metrics.invalidatedFeatureCount
        replayFallbackCount = metrics.replayFallbackCount
        tessellatedBodyCount = metrics.tessellatedBodyCount
        reusedMeshCount = metrics.reusedMeshCount
        scopedBodyReadCount = metrics.scopedBodyReadCount
        maximumScopedBodyReadCount = metrics.maximumScopedBodyReadCount
        topologyMutationCount = metrics.topologyMutationCount
    }

    init(
        _ metrics: ModelingEvaluationMetrics,
        evaluationPassCount: UInt64,
        historyEntryCount: Int
    ) {
        self.evaluationPassCount = evaluationPassCount
        self.historyEntryCount = historyEntryCount
        totalFeatureCount = metrics.totalFeatureCount
        rebuiltFeatureCount = metrics.rebuiltFeatureCount
        reusedFeatureCount = metrics.reusedFeatureCount
        invalidatedFeatureCount = metrics.invalidatedFeatureCount
        replayFallbackCount = metrics.replayFallbackCount
        tessellatedBodyCount = metrics.tessellatedBodyCount
        reusedMeshCount = metrics.reusedMeshCount
        scopedBodyReadCount = metrics.scopedBodyReadCount
        maximumScopedBodyReadCount = metrics.maximumScopedBodyReadCount
        topologyMutationCount = metrics.topologyMutationCount
    }
}

private struct TimedTelemetry {
    var seconds: Double
    var telemetry: BenchmarkTelemetry?
}

private enum BenchmarkError: Error {
    case invalidArguments
    case missingPrimaryFeature
    case outputEncodingFailed
    case unexpectedBodyCount
    case unexpectedIncrementalEvaluation
}

private extension Duration {
    var seconds: Double {
        let value = components
        return Double(value.seconds) + Double(value.attoseconds) / 1.0e18
    }
}
