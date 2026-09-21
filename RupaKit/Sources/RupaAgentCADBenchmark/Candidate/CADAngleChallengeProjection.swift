import Foundation

/// Candidate-visible angle values decoded only from the public challenge text.
struct CADAngleChallengeProjection: Sendable {
    let id: CADBenchmarkCaseID
    let orientation: CADSketchPlane
    let intersection: CADPoint3D
    let firstDirection: CADDirection3D
    let secondDirection: CADDirection3D
    let firstLength: CADLength
    let secondLength: CADLength
    let includedAngle: CADAngle

    var firstEnd: CADPoint3D {
        endpoint(from: intersection, direction: firstDirection, length: firstLength)
    }

    var secondEnd: CADPoint3D {
        endpoint(from: intersection, direction: secondDirection, length: secondLength)
    }

    static func decode(_ challenge: CADChallenge) throws -> CADAngleChallengeProjection {
        guard challenge.category == .angle else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "An angle projection requires an angle challenge."
            )
        }
        try challenge.validate()

        let orientation: CADSketchPlane
        if challenge.instruction.contains("XY-oriented") {
            orientation = .xy
        } else if challenge.instruction.contains("XZ-oriented") {
            orientation = .xz
        } else if challenge.instruction.contains("YZ-oriented") {
            orientation = .yz
        } else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public angle challenge has no supported plane orientation."
            )
        }

        let unit = try lengthUnit(in: challenge.instruction, caseID: challenge.id)
        guard let intersectionRange = challenge.instruction.range(of: "intersection") else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public angle challenge has no intersection clause."
            )
        }
        let values = numericValues(in: String(challenge.instruction[intersectionRange.upperBound...]))
        guard values.count == 12 else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public angle challenge must expose an intersection, two lengths, two directions, and one angle."
            )
        }

        let intersection = CADPoint3D(x: values[0], y: values[1], z: values[2], unit: unit)
        let firstLength = CADLength(value: values[3], unit: unit)
        let firstDirection = CADDirection3D(x: values[4], y: values[5], z: values[6])
        let secondLength = CADLength(value: values[7], unit: unit)
        let secondDirection = CADDirection3D(x: values[8], y: values[9], z: values[10])
        let includedAngle = CADAngle(value: values[11], unit: .degree)

        try intersection.validate(caseID: challenge.id, field: "angle.intersection")
        try firstLength.validate(caseID: challenge.id, field: "angle.firstLength")
        try secondLength.validate(caseID: challenge.id, field: "angle.secondLength")
        try firstDirection.validate(caseID: challenge.id, field: "angle.firstDirection")
        try secondDirection.validate(caseID: challenge.id, field: "angle.secondDirection")
        try includedAngle.validate(caseID: challenge.id, field: "angle.includedAngle")
        guard includedAngle.radians < .pi else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public unsigned angle must be less than 180 degrees."
            )
        }
        return CADAngleChallengeProjection(
            id: challenge.id,
            orientation: orientation,
            intersection: intersection,
            firstDirection: firstDirection,
            secondDirection: secondDirection,
            firstLength: firstLength,
            secondLength: secondLength,
            includedAngle: includedAngle
        )
    }

    private func endpoint(
        from start: CADPoint3D,
        direction: CADDirection3D,
        length: CADLength
    ) -> CADPoint3D {
        let startMeters = start.meters
        let scale = length.meters / direction.length
        return CADPoint3D(
            x: startMeters.x + direction.x * scale,
            y: startMeters.y + direction.y * scale,
            z: startMeters.z + direction.z * scale,
            unit: .meter
        )
    }

    private static func lengthUnit(
        in instruction: String,
        caseID: CADBenchmarkCaseID
    ) throws -> CADLengthUnit {
        if instruction.contains(" mm") { return .millimeter }
        if instruction.contains(" cm") { return .centimeter }
        if instruction.contains(" in") { return .inch }
        if instruction.contains(" m") { return .meter }
        throw CADBenchmarkError.invalidInput(
            caseID: caseID.rawValue,
            reason: "The public angle challenge has no supported length unit."
        )
    }

    private static func numericValues(in text: String) -> [Double] {
        var values: [Double] = []
        var token = ""

        func flush() {
            guard token.isEmpty == false, let value = Double(token) else {
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
