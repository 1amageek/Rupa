import Foundation

/// Candidate-visible rectangle values decoded only from challenge text.
struct CADRectangleChallengeProjection: Sendable {
    let id: CADBenchmarkCaseID
    let orientation: CADSketchPlane
    let center: CADPoint3D
    let width: CADLength
    let height: CADLength

    static func decode(_ challenge: CADChallenge) throws -> CADRectangleChallengeProjection {
        guard challenge.category == .rectangle else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "A rectangle projection requires a rectangle challenge."
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
                reason: "The rectangle challenge has no supported plane orientation."
            )
        }

        let unit = try unit(in: challenge.instruction, caseID: challenge.id)
        guard let widthRange = challenge.instruction.range(of: "width") else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The rectangle challenge has no width clause."
            )
        }
        let values = numericValues(in: String(challenge.instruction[widthRange.upperBound...]))
        guard values.count == 5 else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The rectangle challenge must expose width, height, and one center."
            )
        }

        let width = CADLength(value: values[0], unit: unit)
        let height = CADLength(value: values[1], unit: unit)
        let center = CADPoint3D(x: values[2], y: values[3], z: values[4], unit: unit)
        try width.validate(caseID: challenge.id, field: "rectangle.width")
        try height.validate(caseID: challenge.id, field: "rectangle.height")
        try center.validate(caseID: challenge.id, field: "rectangle.center")
        return CADRectangleChallengeProjection(
            id: challenge.id,
            orientation: orientation,
            center: center,
            width: width,
            height: height
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
            reason: "The rectangle challenge has no supported length unit."
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
