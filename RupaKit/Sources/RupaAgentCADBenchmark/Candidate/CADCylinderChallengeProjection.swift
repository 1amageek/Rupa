import Foundation

/// Candidate-visible cylinder values decoded from the public challenge instruction.
struct CADCylinderChallengeProjection: Sendable {
    let id: CADBenchmarkCaseID
    let baseCenter: CADPoint3D
    let axis: CADDirection3D
    let radius: CADLength
    let depth: CADLength

    static func decode(_ challenge: CADChallenge) throws -> CADCylinderChallengeProjection {
        guard challenge.category == .cylinder else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "A cylinder projection requires a cylinder challenge."
            )
        }
        try challenge.validate()
        guard let radiusRange = challenge.instruction.range(of: "radius") else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The cylinder challenge has no radius clause."
            )
        }
        let values = numericValues(in: String(challenge.instruction[radiusRange.upperBound...]))
        guard values.count == 8 else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The cylinder challenge must expose radius, depth, base center, and axis."
            )
        }
        let unit = try unit(in: challenge.instruction, caseID: challenge.id)
        let projection = CADCylinderChallengeProjection(
            id: challenge.id,
            baseCenter: CADPoint3D(x: values[2], y: values[3], z: values[4], unit: unit),
            axis: CADDirection3D(x: values[5], y: values[6], z: values[7]),
            radius: CADLength(value: values[0], unit: unit),
            depth: CADLength(value: values[1], unit: unit)
        )
        try projection.baseCenter.validate(caseID: challenge.id, field: "cylinder.baseCenter")
        try projection.axis.validate(caseID: challenge.id, field: "cylinder.axis")
        try projection.radius.validate(caseID: challenge.id, field: "cylinder.radius")
        try projection.depth.validate(caseID: challenge.id, field: "cylinder.depth")
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
            reason: "The cylinder challenge has no supported length unit."
        )
    }

    private static func numericValues(in text: String) -> [Double] {
        var values: [Double] = []
        var token = ""
        func flush() {
            defer { token.removeAll(keepingCapacity: true) }
            guard token.isEmpty == false, let value = Double(token) else { return }
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
