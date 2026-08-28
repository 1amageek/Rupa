import Foundation

/// Deterministic control candidate used to exercise the production Agent route.
///
/// The candidate is deliberately limited to the public challenge projection.
/// It has no access to the private catalog, expected geometry, or oracle.
struct CADLIN001ReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    /// Derives the deterministic control action solely from the public
    /// challenge projection. Private expectation values never enter this path.
    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        guard challenge.id == "LIN-001", challenge.category == .line else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The LIN-001 reference candidate received an unrelated challenge."
            )
        }
        try challenge.validate()
        guard challenge.outputRoles.map(\.name) == ["segment"],
              challenge.instruction.contains("XY-oriented") else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public LIN-001 challenge does not describe one XY segment."
            )
        }

        guard let lengthRange = challenge.instruction.range(of: "length") else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public LIN-001 challenge has no length clause."
            )
        }
        let publicGeometryText = String(challenge.instruction[lengthRange.upperBound...])
        let values = numericValues(in: publicGeometryText)
        guard values.count == 10 else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public LIN-001 challenge must expose one length and two 3D endpoints."
            )
        }
        let unit: CADLengthUnit
        if publicGeometryText.contains(" mm") {
            unit = .millimeter
        } else if publicGeometryText.contains(" cm") {
            unit = .centimeter
        } else if publicGeometryText.contains(" in") {
            unit = .inch
        } else if publicGeometryText.contains(" m") {
            unit = .meter
        } else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public LIN-001 challenge has no supported length unit."
            )
        }
        let start = CADPoint3D(
            x: values[1],
            y: values[2],
            z: values[3],
            unit: unit
        )
        let end = CADPoint3D(
            x: values[4],
            y: values[5],
            z: values[6],
            unit: unit
        )
        return .automation(
            .sketch(
                .line(
                    name: "LIN-001",
                    plane: .xy,
                    start: start,
                    end: end
                )
            )
        )
    }

    private static func numericValues(in text: String) -> [Double] {
        var values: [Double] = []
        var token = ""

        func flush() {
            guard token.isEmpty == false,
                  let value = Double(token) else {
                token.removeAll(keepingCapacity: true)
                return
            }
            values.append(value)
            token.removeAll(keepingCapacity: true)
        }

        for character in text {
            if character.isNumber || character == "." || character == "-" || character == "+" {
                token.append(character)
            } else {
                flush()
            }
        }
        flush()
        return values
    }
}
