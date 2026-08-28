import Foundation

/// Candidate-visible circle values decoded only from the public challenge text.
struct CADCircleChallengeProjection: Sendable {
    let id: CADBenchmarkCaseID
    let orientation: CADSketchPlane
    let center: CADPoint3D
    let radius: CADLength

    static func decode(_ challenge: CADChallenge) throws -> CADCircleChallengeProjection {
        guard challenge.category == .circle else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "A circle projection requires a circle challenge."
            )
        }
        try challenge.validate()

        let orientation: CADSketchPlane
        if challenge.instruction.contains("on the xy plane") {
            orientation = .xy
        } else if challenge.instruction.contains("on the xz plane") {
            orientation = .xz
        } else if challenge.instruction.contains("on the yz plane") {
            orientation = .yz
        } else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The circle challenge has no supported plane orientation."
            )
        }

        let unit = try unit(in: challenge.instruction, caseID: challenge.id)
        guard let radiusRange = challenge.instruction.range(of: "radius") else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The circle challenge has no radius clause."
            )
        }
        let values = numericValues(in: String(challenge.instruction[radiusRange.upperBound...]))
        guard values.count == 4 else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The circle challenge must expose one radius and one center."
            )
        }

        let radius = CADLength(value: values[0], unit: unit)
        let center = CADPoint3D(x: values[1], y: values[2], z: values[3], unit: unit)
        try radius.validate(caseID: challenge.id, field: "circle.radius")
        try center.validate(caseID: challenge.id, field: "circle.center")
        return CADCircleChallengeProjection(
            id: challenge.id,
            orientation: orientation,
            center: center,
            radius: radius
        )
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
            reason: "The circle challenge has no supported length unit."
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
