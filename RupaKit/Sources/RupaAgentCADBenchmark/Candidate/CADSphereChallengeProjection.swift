import Foundation

/// Candidate-visible sphere values decoded from the public challenge instruction.
struct CADSphereChallengeProjection: Sendable {
    let center: CADPoint3D
    let radius: CADLength

    static func decode(_ challenge: CADChallenge) throws -> CADSphereChallengeProjection {
        guard challenge.category == .sphere else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "A sphere projection requires a sphere challenge."
            )
        }
        try challenge.validate()
        guard let radiusRange = challenge.instruction.range(of: "radius") else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The sphere challenge has no radius clause."
            )
        }
        let values = numericValues(in: String(challenge.instruction[radiusRange.upperBound...]))
        guard values.count == 4 else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The sphere challenge must expose one radius and one center."
            )
        }
        let unit = try unit(in: challenge.instruction, caseID: challenge.id)
        let projection = CADSphereChallengeProjection(
            center: CADPoint3D(x: values[1], y: values[2], z: values[3], unit: unit),
            radius: CADLength(value: values[0], unit: unit)
        )
        try projection.center.validate(caseID: challenge.id, field: "sphere.center")
        try projection.radius.validate(caseID: challenge.id, field: "sphere.radius")
        return projection
    }

    private static func unit(
        in instruction: String,
        caseID: CADBenchmarkCaseID
    ) throws -> CADLengthUnit {
        if instruction.contains(" mm") { return .millimeter }
        if instruction.contains(" cm") { return .centimeter }
        if instruction.contains(" in") { return .inch }
        if instruction.contains(" m") { return .meter }
        throw CADBenchmarkError.invalidInput(
            caseID: caseID.rawValue,
            reason: "The sphere challenge has no supported length unit."
        )
    }

    private static func numericValues(in text: String) -> [Double] {
        var values: [Double] = []
        var token = ""
        func flush() {
            defer { token.removeAll(keepingCapacity: true) }
            guard let value = Double(token) else { return }
            values.append(value)
        }
        for character in text {
            if character.isNumber || character == "." || character == "-" || character == "+"
                || character == "e" || character == "E" {
                token.append(character)
            } else {
                flush()
            }
        }
        flush()
        return values
    }
}
