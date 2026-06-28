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
