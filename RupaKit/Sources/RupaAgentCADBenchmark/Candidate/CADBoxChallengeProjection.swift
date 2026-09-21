import Foundation

/// Candidate-visible box values decoded from the public challenge instruction.
struct CADBoxChallengeProjection: Sendable {
    let id: CADBenchmarkCaseID
    let origin: CADPoint3D
    let width: CADLength
    let depth: CADLength
    let height: CADLength

    static func decode(_ challenge: CADChallenge) throws -> CADBoxChallengeProjection {
        guard challenge.category == .box else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "A box projection requires a box challenge."
            )
        }
        try challenge.validate()
        guard let widthRange = challenge.instruction.range(of: "width") else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The box challenge has no width clause."
            )
        }
        let values = numericValues(in: String(challenge.instruction[widthRange.upperBound...]))
        guard values.count == 6 else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The box challenge must expose three dimensions and one origin."
            )
        }

        let unit = try unit(in: challenge.instruction, caseID: challenge.id)
        let projection = CADBoxChallengeProjection(
            id: challenge.id,
            origin: CADPoint3D(x: values[3], y: values[4], z: values[5], unit: unit),
            width: CADLength(value: values[0], unit: unit),
            depth: CADLength(value: values[1], unit: unit),
            height: CADLength(value: values[2], unit: unit)
        )
        try projection.origin.validate(caseID: challenge.id, field: "box.origin")
        try projection.width.validate(caseID: challenge.id, field: "box.width")
        try projection.depth.validate(caseID: challenge.id, field: "box.depth")
        try projection.height.validate(caseID: challenge.id, field: "box.height")
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
            reason: "The box challenge has no supported length unit."
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
