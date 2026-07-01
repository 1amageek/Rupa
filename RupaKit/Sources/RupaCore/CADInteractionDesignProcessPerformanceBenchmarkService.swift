import Foundation

enum CADInteractionDesignProcessPerformanceBenchmarkService {
    static let agentPayloadBudgetBytes = 262_144.0

    private static let agentPayloadMetric = "encodedDesignProcessPacketPayloadBytes"
    private static let agentPayloadUnit = "bytes"
    private static let agentPayloadSource = "CADInteractionDesignProcessPerformanceBenchmarkService.agentPayloadBudgetBytes"
    private static let geometryFixtureMetric = "denseGeometryFixtureOperationUnits"
    private static let geometryFixtureUnit = "weightedOperationUnits"
    private static let wallClockFixtureMetric = "denseGeometryFixtureEstimatedWallClockMilliseconds"
    private static let wallClockFixtureUnit = "milliseconds"
    private static let residentMemoryFixtureMetric = "denseGeometryFixtureEstimatedResidentMemoryBytes"
    private static let residentMemoryFixtureUnit = "bytes"
    private static let maximumPayloadMeasurementPasses = 8

    static func recordBenchmarks(
        in packet: DesignProcessPacket,
        refreshingDerivedFields: (inout DesignProcessPacket) -> Void
    ) -> DesignProcessPacket {
        var measuredPacket = packet
        removeAgentPayloadMeasurement(from: &measuredPacket)
        removeDenseFixtureMeasurements(from: &measuredPacket)
        appendDenseFixtureMeasurements(to: &measuredPacket)
        replaceAgentPayloadMeasurement(
            in: &measuredPacket,
            measuredBytes: nil,
            errorDescription: nil
        )
        refreshingDerivedFields(&measuredPacket)

        do {
            for _ in 0..<maximumPayloadMeasurementPasses {
                let encodedByteCount = try encodedByteCount(for: measuredPacket)
                if agentPayloadMeasuredValue(in: measuredPacket) == Double(encodedByteCount) {
                    return measuredPacket
                }
                replaceAgentPayloadMeasurement(
                    in: &measuredPacket,
                    measuredBytes: Double(encodedByteCount),
                    errorDescription: nil
                )
                refreshingDerivedFields(&measuredPacket)
            }

            replaceAgentPayloadMeasurement(
                in: &measuredPacket,
                measuredBytes: nil,
                errorDescription: "Payload measurement did not converge within \(maximumPayloadMeasurementPasses) passes."
            )
            refreshingDerivedFields(&measuredPacket)
            return measuredPacket
        } catch {
            replaceAgentPayloadMeasurement(
                in: &measuredPacket,
                measuredBytes: nil,
                errorDescription: "Encoding failed: \(error.localizedDescription)"
            )
            refreshingDerivedFields(&measuredPacket)
            return measuredPacket
        }
    }

    private static func encodedByteCount(
        for packet: DesignProcessPacket
    ) throws -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(packet).count
    }

    private static func removeAgentPayloadMeasurement(
        from packet: inout DesignProcessPacket
    ) {
        packet.confidence.performanceMeasurements.removeAll { measurement in
            measurement.metric == agentPayloadMetric
        }
    }

    private static func removeDenseFixtureMeasurements(
        from packet: inout DesignProcessPacket
    ) {
        packet.confidence.performanceMeasurements.removeAll { measurement in
            denseFixtureMetrics.contains(measurement.metric)
        }
    }

    private static func appendDenseFixtureMeasurements(
        to packet: inout DesignProcessPacket
    ) {
        let fixture = CADInteractionDesignProcessGeometryBenchmarkFixture.fixture(
            for: packet.intent.area
        )
        packet.confidence.performanceMeasurements.append(
            geometryFixtureMeasurement(fixture: fixture)
        )
        packet.confidence.performanceMeasurements.append(
            wallClockFixtureMeasurement(fixture: fixture)
        )
        packet.confidence.performanceMeasurements.append(
            residentMemoryFixtureMeasurement(fixture: fixture)
        )
    }

    private static func replaceAgentPayloadMeasurement(
        in packet: inout DesignProcessPacket,
        measuredBytes: Double?,
        errorDescription: String?
    ) {
        let measurement = agentPayloadMeasurement(
            capabilityID: packet.intent.capabilityID,
            measuredBytes: measuredBytes,
            errorDescription: errorDescription
        )
        if let index = packet.confidence.performanceMeasurements.firstIndex(where: { measurement in
            measurement.metric == agentPayloadMetric
        }) {
            packet.confidence.performanceMeasurements[index] = measurement
        } else {
            packet.confidence.performanceMeasurements.append(measurement)
        }
    }

    private static func agentPayloadMeasurement(
        capabilityID: String,
        measuredBytes: Double?,
        errorDescription: String?
    ) -> DesignProcessPerformanceMeasurement {
        DesignProcessPerformanceMeasurement(
            id: "\(capabilityID)-agent-payload-bytes",
            title: "Agent design packet payload size",
            metric: agentPayloadMetric,
            unit: agentPayloadUnit,
            measuredValue: measuredBytes,
            budgetValue: agentPayloadBudgetBytes,
            status: agentPayloadStatus(
                measuredBytes: measuredBytes,
                errorDescription: errorDescription
            ),
            source: agentPayloadSource,
            notes: agentPayloadNotes(errorDescription: errorDescription)
        )
    }

    private static func geometryFixtureMeasurement(
        fixture: CADInteractionDesignProcessGeometryBenchmarkFixture
    ) -> DesignProcessPerformanceMeasurement {
        let measuredUnits = fixture.operationUnits
        return DesignProcessPerformanceMeasurement(
            id: "\(fixture.area.rawValue)-dense-geometry-fixture",
            title: fixture.title,
            metric: geometryFixtureMetric,
            unit: geometryFixtureUnit,
            measuredValue: measuredUnits,
            budgetValue: fixture.operationBudgetUnits,
            status: measuredUnits <= fixture.operationBudgetUnits ? .withinBudget : .exceedsBudget,
            source: "CADInteractionDesignProcessGeometryBenchmarkFixture.\(fixture.area.rawValue)",
            notes: [
                "Deterministic dense-scene geometry fixture for \(fixture.area.rawValue).",
                "sourceEntities=\(fixture.sourceEntityCount), topologyElements=\(fixture.topologyElementCount).",
                "constraintsOrRelations=\(fixture.constraintOrRelationCount), samples=\(fixture.sampleCount), variants=\(fixture.variantCount).",
                "This is a regression-gating complexity metric shared by wall-clock and memory fixture estimates.",
            ]
        )
    }

    private static func wallClockFixtureMeasurement(
        fixture: CADInteractionDesignProcessGeometryBenchmarkFixture
    ) -> DesignProcessPerformanceMeasurement {
        let estimatedMilliseconds = fixture.estimatedWallClockMilliseconds
        return DesignProcessPerformanceMeasurement(
            id: "\(fixture.area.rawValue)-dense-fixture-wall-clock",
            title: "\(fixture.title) wall-clock fixture",
            metric: wallClockFixtureMetric,
            unit: wallClockFixtureUnit,
            measuredValue: estimatedMilliseconds,
            budgetValue: fixture.wallClockBudgetMilliseconds,
            status: estimatedMilliseconds <= fixture.wallClockBudgetMilliseconds
                ? .withinBudget
                : .exceedsBudget,
            source: "CADInteractionDesignProcessGeometryBenchmarkFixture.\(fixture.area.rawValue).wallClock",
            notes: [
                "Deterministic production-scene wall-clock regression fixture for \(fixture.area.rawValue).",
                "The value is derived from the dense fixture operation units so packets carry an enforceable latency budget before host-specific timing samples are available.",
                "Replace or supplement this estimate with measured wall-clock samples from the production performance harness when that harness is attached.",
            ]
        )
    }

    private static func residentMemoryFixtureMeasurement(
        fixture: CADInteractionDesignProcessGeometryBenchmarkFixture
    ) -> DesignProcessPerformanceMeasurement {
        let estimatedBytes = fixture.estimatedResidentMemoryBytes
        return DesignProcessPerformanceMeasurement(
            id: "\(fixture.area.rawValue)-dense-fixture-resident-memory",
            title: "\(fixture.title) resident memory fixture",
            metric: residentMemoryFixtureMetric,
            unit: residentMemoryFixtureUnit,
            measuredValue: estimatedBytes,
            budgetValue: fixture.residentMemoryBudgetBytes,
            status: estimatedBytes <= fixture.residentMemoryBudgetBytes
                ? .withinBudget
                : .exceedsBudget,
            source: "CADInteractionDesignProcessGeometryBenchmarkFixture.\(fixture.area.rawValue).residentMemory",
            notes: [
                "Deterministic production-scene resident-memory regression fixture for \(fixture.area.rawValue).",
                "The estimate accounts for source entities, topology elements, constraints or relations, samples, and variants.",
                "Replace or supplement this estimate with measured resident-memory samples from the production performance harness when that harness is attached.",
            ]
        )
    }

    private static func agentPayloadStatus(
        measuredBytes: Double?,
        errorDescription: String?
    ) -> DesignProcessPerformanceMeasurementStatus {
        if errorDescription != nil {
            return .unmeasured
        }
        guard let measuredBytes else {
            return .unmeasured
        }
        return measuredBytes <= agentPayloadBudgetBytes ? .withinBudget : .exceedsBudget
    }

    private static func agentPayloadNotes(
        errorDescription: String?
    ) -> [String] {
        var notes = [
            "Measures the final sorted-key JSON Agent design packet including this payload-size record.",
            "Budget keeps Agent-readable CAD design packets bounded alongside dense geometry fixture measurements.",
        ]
        if let errorDescription {
            notes.append(errorDescription)
        }
        return notes
    }

    private static func agentPayloadMeasuredValue(
        in packet: DesignProcessPacket
    ) -> Double? {
        packet.confidence.performanceMeasurements.first { measurement in
            measurement.metric == agentPayloadMetric
        }?.measuredValue
    }

    private static var denseFixtureMetrics: Set<String> {
        [
            geometryFixtureMetric,
            wallClockFixtureMetric,
            residentMemoryFixtureMetric,
        ]
    }
}
