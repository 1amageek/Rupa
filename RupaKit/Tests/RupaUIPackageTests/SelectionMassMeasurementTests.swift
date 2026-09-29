import Foundation
import RupaCore
import RupaCoreTypes
import SwiftCAD
import Testing
@testable import RupaUI

/// The selection's mass is measured off the main actor: of two requests made together only the
/// later one's mass arrives (one unweighed box, then both), and a cancelled request delivers
/// nothing.
@MainActor
@Suite struct SelectionMassMeasurementTests {
    private func request(for session: EditorSession, selecting names: [String]) throws -> SelectionMassMeasurement.Request {
        let nodes = try names.map { name in
            try #require(session.document.productMetadata.sceneNodes.values.first { $0.name.hasPrefix(name) && $0.reference?.kind == .body })
        }
        var selection = SelectionModel()
        try selection.selectTargets(nodes.map { SelectionTarget(sceneNodeID: $0.id) }, in: session.document)
        return SelectionMassMeasurement.Request(
            document: session.document, selection: selection, ruler: .standard(for: .meter),
            objectRegistry: .builtIn, evaluation: nil, generation: session.generation
        )
    }

    private func session() throws -> EditorSession {
        let session = EditorSession()
        for (name, side) in [("Small", 0.1), ("Large", 0.2)] {
            _ = try session.execute(.createExtrudedRectangle(
                name: name, plane: .xy,
                width: .length(side, .meter), height: .length(side, .meter),
                depth: .length(side, .meter), direction: .normal
            ))
        }
        return session
    }

    @Test(.timeLimit(.minutes(1)))
    func onlyTheLatestRequestsMassArrives() async throws {
        let session = try session()
        let measurement = SelectionMassMeasurement()
        let first = try request(for: session, selecting: ["Small"])
        let second = try request(for: session, selecting: ["Small", "Large"])
        var delivered: [SceneMass] = []
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let record: @MainActor (Result<SceneMass, any Error>) -> Void = { result in
                if case .success(let mass) = result { delivered.append(mass) }
                continuation.resume()
            }
            measurement.measure(first, deliver: record)
            measurement.measure(second, deliver: record)
        }
        #expect(delivered.map(\.unweighedSolidCount) == [2])
    }

    @Test(.timeLimit(.minutes(1)))
    func aCancelledRequestDeliversNothing() async throws {
        let session = try session()
        let measurement = SelectionMassMeasurement()
        var deliveries = 0
        measurement.measure(try request(for: session, selecting: ["Small"])) { _ in deliveries += 1 }
        measurement.cancel()
        // A later request's delivery shows the cancelled one has finished without delivering.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                measurement.measure(try request(for: session, selecting: ["Large"])) { _ in continuation.resume() }
            } catch {
                continuation.resume()
            }
        }
        #expect(deliveries == 0)
    }
}
