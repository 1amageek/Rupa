import Foundation
import RupaCoreTypes

struct CADBenchmarkEnvironmentFingerprint: Codable, Equatable, Sendable {
    static let aggregateContractVersion = "t12.aggregate.v1"
    static let swiftToolchainIdentifier = "org.swift.64202608141a"
    static let swiftCompilerCommit = "424cae54c1a10da"
    static let agentRouteVersion = "project-agent-command-controller.v1"
    static let evaluatorVersion = "rupa-source-brep-oracle.v1"

    let aggregateContractVersion: String
    let swiftToolchainIdentifier: String
    let swiftCompilerCommit: String
    let agentRouteVersion: String
    let evaluatorVersion: String
    let manifestDigest: String
    let expectationDigest: String
    let capabilityAvailabilityDigest: String
    let digest: String

    init(
        manifestDigest: String,
        expectationDigest: String,
        capabilityAvailabilityDigest: String,
        aggregateContractVersion: String = Self.aggregateContractVersion,
        swiftToolchainIdentifier: String = Self.swiftToolchainIdentifier,
        swiftCompilerCommit: String = Self.swiftCompilerCommit,
        agentRouteVersion: String = Self.agentRouteVersion,
        evaluatorVersion: String = Self.evaluatorVersion
    ) throws {
        self.aggregateContractVersion = aggregateContractVersion
        self.swiftToolchainIdentifier = swiftToolchainIdentifier
        self.swiftCompilerCommit = swiftCompilerCommit
        self.agentRouteVersion = agentRouteVersion
        self.evaluatorVersion = evaluatorVersion
        self.manifestDigest = manifestDigest
        self.expectationDigest = expectationDigest
        self.capabilityAvailabilityDigest = capabilityAvailabilityDigest
        self.digest = try Self.computeDigest(Payload(
            aggregateContractVersion: aggregateContractVersion,
            swiftToolchainIdentifier: swiftToolchainIdentifier,
            swiftCompilerCommit: swiftCompilerCommit,
            agentRouteVersion: agentRouteVersion,
            evaluatorVersion: evaluatorVersion,
            manifestDigest: manifestDigest,
            expectationDigest: expectationDigest,
            capabilityAvailabilityDigest: capabilityAvailabilityDigest
        ))
        try validate()
    }

    func validate() throws {
        guard [aggregateContractVersion, swiftToolchainIdentifier,
               swiftCompilerCommit, agentRouteVersion, evaluatorVersion]
                .allSatisfy({ !$0.isEmpty && $0.trimmingCharacters(in: .whitespacesAndNewlines) == $0 }),
              [manifestDigest, expectationDigest, capabilityAvailabilityDigest, digest]
                .allSatisfy(Self.isDigest) else {
            throw CADBenchmarkBaselineError.invalidEnvironmentFingerprint
        }
        let recomputed = try Self.computeDigest(Payload(
            aggregateContractVersion: aggregateContractVersion,
            swiftToolchainIdentifier: swiftToolchainIdentifier,
            swiftCompilerCommit: swiftCompilerCommit,
            agentRouteVersion: agentRouteVersion,
            evaluatorVersion: evaluatorVersion,
            manifestDigest: manifestDigest,
            expectationDigest: expectationDigest,
            capabilityAvailabilityDigest: capabilityAvailabilityDigest
        ))
        guard digest == recomputed else {
            throw CADBenchmarkBaselineError.invalidEnvironmentFingerprint
        }
    }

    func differences(from expected: Self) -> [CADBenchmarkBaselineDrift] {
        var differences: [CADBenchmarkBaselineDrift] = []
        if aggregateContractVersion != expected.aggregateContractVersion {
            differences.append(.aggregateContract)
        }
        if swiftToolchainIdentifier != expected.swiftToolchainIdentifier
            || swiftCompilerCommit != expected.swiftCompilerCommit {
            differences.append(.toolchain)
        }
        if agentRouteVersion != expected.agentRouteVersion {
            differences.append(.agentRoute)
        }
        if evaluatorVersion != expected.evaluatorVersion {
            differences.append(.evaluator)
        }
        if manifestDigest != expected.manifestDigest {
            differences.append(.manifest)
        }
        if expectationDigest != expected.expectationDigest {
            differences.append(.expectation)
        }
        if capabilityAvailabilityDigest != expected.capabilityAvailabilityDigest {
            differences.append(.capabilityAvailability)
        }
        return differences
    }

    private struct Payload: Codable {
        let aggregateContractVersion: String
        let swiftToolchainIdentifier: String
        let swiftCompilerCommit: String
        let agentRouteVersion: String
        let evaluatorVersion: String
        let manifestDigest: String
        let expectationDigest: String
        let capabilityAvailabilityDigest: String
    }

    private static func computeDigest(_ payload: Payload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return StableDigest.sha256Hex(for: try encoder.encode(payload))
    }

    private static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isNumber || ("a"..."f").contains($0) }
    }
}
