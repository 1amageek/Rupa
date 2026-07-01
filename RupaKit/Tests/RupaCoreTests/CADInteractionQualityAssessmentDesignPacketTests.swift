import Foundation
import Testing
import RupaCore

@Test func cadInteractionQualityAssessmentDesignPacketsAreAttachedToEveryEntry() throws {
    let result = CADInteractionQualityAssessmentService().assess()
    let packets = try encodedDesignProcessPackets(from: result)

    #expect(packets.count == result.entries.count)

    for (index, packet) in packets.enumerated() {
        let entry = result.entries[index]

        #expect(!packet.id.isEmpty)
        #expect(packet.intent.area == entry.area)
        #expect(!packet.intent.capabilityID.isEmpty)
        #expect(!packet.intent.title.isEmpty)
        #expect(!packet.intent.outcome.isEmpty)
        #expect(!packet.evaluation.successCriteria.isEmpty)
        #expect(
            !packet.domain.sourceEntities.isEmpty ||
            !packet.domain.targetEntities.isEmpty ||
            !packet.domain.generatedTopology.isEmpty
        )
        #expect(!packet.caseMatrix.cases.isEmpty)
        #expect(!packet.routeMatrix.requiredPorts.isEmpty)
        #expect(!packet.routeMatrix.routes.isEmpty)
        #expect(!packet.flowGraph.nodes.isEmpty)
        #expect(!packet.confidence.notes.isEmpty || packet.confidence.score > 0)
    }
}

@Test func cadInteractionQualityAssessmentDesignPacketsReflectOpenWorkAsCasesAndObservations() throws {
    let result = CADInteractionQualityAssessmentService().assess()
    let packets = try encodedDesignProcessPackets(from: result)

    for (index, packet) in packets.enumerated() where !result.entries[index].openWork.isEmpty {
        #expect(!packet.caseMatrix.missing.cases.isEmpty)
        #expect(!packet.observations.isEmpty)

        for observation in packet.observations {
            #expect(!observation.summary.isEmpty)
            #expect(!observation.requiredNextAction.isEmpty)
        }
    }
}

@Test func cadInteractionQualityAssessmentDesignPacketFlowGraphsExposePortsAndConnectionState() throws {
    let result = CADInteractionQualityAssessmentService().assess()
    let packets = try encodedDesignProcessPackets(from: result)

    for packet in packets {
        let flowGraph = packet.flowGraph
        let validation = flowGraph.validate()
        let ports = flowGraph.nodes.flatMap(\.ports)

        #expect(!flowGraph.nodes.isEmpty)
        #expect(!flowGraph.edges.isEmpty)
        #expect(!flowGraph.requiredPorts.isEmpty)
        #expect(ports.contains { $0.direction == .input || $0.direction == .bidirectional })
        #expect(ports.contains { $0.direction == .output || $0.direction == .bidirectional })
        #expect(validation.isValid)
    }
}

@Test func cadInteractionQualityAssessmentDesignPacketsUseCapabilitySpecificSpecs() throws {
    let result = CADInteractionQualityAssessmentService().assess()
    let packets = try encodedDesignProcessPackets(from: result)

    for packet in packets {
        let routeIDs = Set(packet.routeMatrix.routes.map(\.id))
        let decisionRouteIDs = Set(packet.resolution.decisions.map(\.selectedRouteID))

        #expect(packet.routeMatrix.missingRequiredPortKinds().isEmpty)
        #expect(!packet.caseMatrix.supported.cases.isEmpty)
        #expect(!packet.caseMatrix.boundary.cases.isEmpty)
        #expect(!packet.caseMatrix.degenerate.cases.isEmpty)
        #expect(!packet.caseMatrix.rejected.cases.isEmpty)
        #expect(!packet.caseMatrix.performance.cases.isEmpty)
        #expect(packet.constraintBinding.invariants.count >= 2)
        #expect(!packet.resolution.selectedRouteIDs.isEmpty)
        #expect(packet.resolution.selectedRouteIDs.allSatisfy { routeIDs.contains($0) })
        #expect(decisionRouteIDs.allSatisfy { routeIDs.contains($0) })
        #expect(packet.routeMatrix.routes.allSatisfy { route in
            route.source.identifier != route.source.kind.rawValue
                && route.target.identifier != route.target.kind.rawValue
        })
        #expect(packet.flowGraph.nodes.contains { $0.layer == .documentation })
    }
}

@Test func cadInteractionQualityAssessmentDesignPacketsIngestObservationChannelsIntoConfidence() throws {
    let result = CADInteractionQualityAssessmentService().assess()
    let packets = try encodedDesignProcessPackets(from: result)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    for packet in packets {
        let observationIDs = packet.observations.map(\.id)
        let channels = Set(packet.observations.map { $0.channel.rawValue })
        let encodedPacket = try encoder.encode(packet)
        let payloadMeasurements = packet.confidence.performanceMeasurements.filter { measurement in
            measurement.metric == "encodedDesignProcessPacketPayloadBytes"
        }
        let geometryMeasurements = packet.confidence.performanceMeasurements.filter { measurement in
            measurement.metric == "denseGeometryFixtureOperationUnits"
        }
        let wallClockMeasurements = packet.confidence.performanceMeasurements.filter { measurement in
            measurement.metric == "denseGeometryFixtureEstimatedWallClockMilliseconds"
        }
        let residentMemoryMeasurements = packet.confidence.performanceMeasurements.filter { measurement in
            measurement.metric == "denseGeometryFixtureEstimatedResidentMemoryBytes"
        }
        let payloadMeasurement = try #require(packet.confidence.performanceMeasurements.first { measurement in
            measurement.metric == "encodedDesignProcessPacketPayloadBytes"
        })
        let geometryMeasurement = try #require(packet.confidence.performanceMeasurements.first { measurement in
            measurement.metric == "denseGeometryFixtureOperationUnits"
        })
        let wallClockMeasurement = try #require(packet.confidence.performanceMeasurements.first { measurement in
            measurement.metric == "denseGeometryFixtureEstimatedWallClockMilliseconds"
        })
        let residentMemoryMeasurement = try #require(packet.confidence.performanceMeasurements.first { measurement in
            measurement.metric == "denseGeometryFixtureEstimatedResidentMemoryBytes"
        })
        let measuredPerformanceCount = packet.confidence.performanceMeasurements.filter { measurement in
            measurement.status == .withinBudget || measurement.status == .exceedsBudget
        }.count
        let hasPenaltyObservation = packet.observations.contains { observation in
            observation.severity == .warning
                || observation.severity == .error
                || observation.severity == .blocking
        }

        #expect(!packet.observations.isEmpty)
        #expect(observationIDs.count == Set(observationIDs).count)
        #expect(channels.contains(DesignProcessObservationChannel.automatedTest.rawValue))
        #expect(channels.contains(DesignProcessObservationChannel.performanceMeasurement.rawValue))
        #expect(channels.contains(DesignProcessObservationChannel.runtimeDiagnostic.rawValue))
        #expect(packet.observations.allSatisfy { !$0.summary.isEmpty && !$0.requiredNextAction.isEmpty })
        #expect(packet.confidence.notes.contains { $0.contains("ObservationSet") })
        #expect(packet.confidence.notes.contains { $0.contains("Calibration uses") })
        #expect(!packet.confidence.calibrationAnchors.isEmpty)
        #expect(!packet.confidence.performanceMeasurements.isEmpty)
        #expect(packet.confidence.calibrationAnchors.allSatisfy { anchor in
            !anchor.id.isEmpty && !anchor.title.isEmpty && !anchor.summary.isEmpty
        })
        #expect(packet.confidence.performanceMeasurements.allSatisfy { measurement in
            !measurement.id.isEmpty
                && !measurement.title.isEmpty
                && !measurement.metric.isEmpty
                && !measurement.unit.isEmpty
                && !measurement.source.isEmpty
        })
        #expect(packet.confidence.performanceMeasurements.allSatisfy { measurement in
            measurement.status != .withinBudget || measurement.measuredValue != nil
        })
        #expect(payloadMeasurements.count == 1)
        #expect(geometryMeasurements.count == 1)
        #expect(wallClockMeasurements.count == 1)
        #expect(residentMemoryMeasurements.count == 1)
        #expect(payloadMeasurement.status == .withinBudget)
        #expect(payloadMeasurement.measuredValue == Double(encodedPacket.count))
        #expect((payloadMeasurement.budgetValue ?? 0) >= Double(encodedPacket.count))
        #expect(payloadMeasurement.source == "CADInteractionDesignProcessPerformanceBenchmarkService.agentPayloadBudgetBytes")
        #expect(geometryMeasurement.status == .withinBudget)
        #expect((geometryMeasurement.measuredValue ?? 0) > 0)
        #expect((geometryMeasurement.budgetValue ?? 0) >= (geometryMeasurement.measuredValue ?? 0))
        #expect(geometryMeasurement.unit == "weightedOperationUnits")
        #expect(geometryMeasurement.source == "CADInteractionDesignProcessGeometryBenchmarkFixture.\(packet.intent.area.rawValue)")
        #expect(geometryMeasurement.notes.contains { note in
            note.contains("Deterministic dense-scene geometry fixture")
        })
        #expect(wallClockMeasurement.status == .withinBudget)
        #expect((wallClockMeasurement.measuredValue ?? 0) > 0)
        #expect((wallClockMeasurement.budgetValue ?? 0) >= (wallClockMeasurement.measuredValue ?? 0))
        #expect(wallClockMeasurement.unit == "milliseconds")
        #expect(wallClockMeasurement.source == "CADInteractionDesignProcessGeometryBenchmarkFixture.\(packet.intent.area.rawValue).wallClock")
        #expect(wallClockMeasurement.notes.contains { note in
            note.contains("production-scene wall-clock regression fixture")
        })
        #expect(residentMemoryMeasurement.status == .withinBudget)
        #expect((residentMemoryMeasurement.measuredValue ?? 0) > 0)
        #expect((residentMemoryMeasurement.budgetValue ?? 0) >= (residentMemoryMeasurement.measuredValue ?? 0))
        #expect(residentMemoryMeasurement.unit == "bytes")
        #expect(residentMemoryMeasurement.source == "CADInteractionDesignProcessGeometryBenchmarkFixture.\(packet.intent.area.rawValue).residentMemory")
        #expect(residentMemoryMeasurement.notes.contains { note in
            note.contains("resident-memory regression fixture")
        })
        #expect(packet.confidence.notes.contains(
            "Calibration uses \(packet.confidence.calibrationAnchors.count) anchors and \(measuredPerformanceCount)/\(packet.confidence.performanceMeasurements.count) measured performance records."
        ))
        #expect(packet.confidence.calibrationState != .uncalibrated)
        if hasPenaltyObservation {
            #expect(packet.confidence.missingChannelPenalty > 0)
        } else {
            #expect(packet.confidence.missingChannelPenalty == 0)
        }
    }
}

@Test func cadInteractionQualityAssessmentDesignPacketsSurviveCodableRoundTrip() throws {
    let result = CADInteractionQualityAssessmentService().assess()
    let packets = try encodedDesignProcessPackets(from: result)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(result)
    let decoded = try JSONDecoder().decode(CADInteractionQualityAssessmentResult.self, from: encoded)

    #expect(decoded == result)

    let encodedAgain = try encoder.encode(decoded)

    #expect(encoded == encodedAgain)

    for packet in packets {
        let encodedPacket = try encoder.encode(packet)
        let decodedPacket = try JSONDecoder().decode(DesignProcessPacket.self, from: encodedPacket)

        #expect(decodedPacket == packet)
    }
}

private func encodedAssessmentEntries(
    from result: CADInteractionQualityAssessmentResult
) throws -> [[String: Any]] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(result)
    let root = try #require(try jsonObject(from: encoded) as? [String: Any])
    return try #require(root["entries"] as? [[String: Any]])
}

private func encodedDesignProcessPackets(
    from result: CADInteractionQualityAssessmentResult
) throws -> [DesignProcessPacket] {
    let encodedEntries = try encodedAssessmentEntries(from: result)
    return try encodedEntries.map { encodedEntry in
        let packetObject = try #require(encodedEntry["designProcessPacket"])
        let packetData = try JSONSerialization.data(withJSONObject: packetObject)
        return try JSONDecoder().decode(DesignProcessPacket.self, from: packetData)
    }
}

private func jsonObject(from data: Data) throws -> Any {
    try JSONSerialization.jsonObject(with: data)
}
