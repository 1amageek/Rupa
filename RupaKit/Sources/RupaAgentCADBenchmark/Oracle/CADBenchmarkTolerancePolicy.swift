import Foundation
import SwiftCAD

struct CADBenchmarkTolerancePolicy: Sendable {
    static let version = CADBenchmarkManifest.tolerancePolicyVersion

    let modelingTolerance: ModelingTolerance

    init(modelingTolerance: ModelingTolerance) throws {
        try modelingTolerance.validate()
        self.modelingTolerance = modelingTolerance
    }

    func acceptsLinear(expected: Double, observed: Double) -> Bool {
        guard expected.isFinite, observed.isFinite else {
            return false
        }
        let limit = max(
            modelingTolerance.distance,
            modelingTolerance.relative * max(1.0, abs(expected), abs(observed))
        )
        return abs(expected - observed) <= limit
    }

    func acceptsAngle(expected: Double, observed: Double) -> Bool {
        guard expected.isFinite, observed.isFinite else {
            return false
        }
        let difference = abs((expected - observed).truncatingRemainder(dividingBy: 2.0 * .pi))
        let normalizedDifference = min(difference, 2.0 * .pi - difference)
        return normalizedDifference <= max(modelingTolerance.angle, modelingTolerance.relative)
    }

    func isNonDegenerate(_ length: Double) -> Bool {
        length.isFinite && length > modelingTolerance.distance
    }
}
