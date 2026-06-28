import Foundation

enum CADInteractionDesignProcessPerformanceBenchmarkService {
    static let agentPayloadBudgetBytes = 262_144.0

    private static let agentPayloadMetric = "encodedDesignProcessPacketPayloadBytes"
    private static let agentPayloadUnit = "bytes"
    private static let agentPayloadSource = "CADInteractionDesignProcessPerformanceBenchmarkService.agentPayloadBudgetBytes"
    private static let maximumPayloadMeasurementPasses = 8

    static func recordBenchmarks(
        in packet: DesignProcessPacket,
        refreshingDerivedFields: (inout DesignProcessPacket) -> Void
    ) -> DesignProcessPacket {
        var measuredPacket = packet
        removeAgentPayloadMeasurement(from: &measuredPacket)
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
            "Budget keeps Agent-readable CAD design packets bounded before dense-scene geometry benchmarks are attached.",
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
}
