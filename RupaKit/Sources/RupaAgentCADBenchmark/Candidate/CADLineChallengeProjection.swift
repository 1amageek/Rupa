import Foundation

/// Candidate-visible line values decoded from the public challenge text.
///
/// This projection deliberately contains no private catalog or oracle value.
/// The runner uses the same projection to recover the public plane anchor;
/// the private expectation remains confined to the runner/oracle boundary.
struct CADLineChallengeProjection: Sendable {
    let id: CADBenchmarkCaseID
    let orientation: CADSketchPlane
    let length: CADLength
    let start: CADPoint3D
    let end: CADPoint3D
    let anchor: CADPoint3D

    static func decode(_ challenge: CADChallenge) throws -> CADLineChallengeProjection {
        guard challenge.category == .line else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "A line projection requires a line challenge."
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
                reason: "The public line challenge has no supported plane orientation."
            )
        }

        let unit = try unit(in: challenge.instruction, caseID: challenge.id)
        guard let lengthRange = challenge.instruction.range(of: "length") else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public line challenge has no length clause."
            )
        }
        let values = numericValues(in: String(challenge.instruction[lengthRange.upperBound...]))
        guard values.count == 10 else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public line challenge must expose one length, two endpoints, and one plane anchor."
            )
        }

        let length = CADLength(value: values[0], unit: unit)
        let start = CADPoint3D(x: values[1], y: values[2], z: values[3], unit: unit)
        let end = CADPoint3D(x: values[4], y: values[5], z: values[6], unit: unit)
        let anchor = CADPoint3D(x: values[7], y: values[8], z: values[9], unit: unit)
        try length.validate(caseID: challenge.id, field: "line.length")
        try start.validate(caseID: challenge.id, field: "line.start")
        try end.validate(caseID: challenge.id, field: "line.end")
        try anchor.validate(caseID: challenge.id, field: "line.anchor")

        guard start.meters == anchor.meters else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public line plane anchor must equal the declared start point."
            )
        }
        return CADLineChallengeProjection(
            id: challenge.id,
            orientation: orientation,
            length: length,
            start: start,
            end: end,
            anchor: anchor
        )
    }

    private static func unit(
        in instruction: String,
        caseID: CADBenchmarkCaseID
    ) throws -> CADLengthUnit {
        if instruction.contains(" mm") {
            return .millimeter
        }
        if instruction.contains(" cm") {
            return .centimeter
        }
        if instruction.contains(" in") {
            return .inch
        }
        if instruction.contains(" m") {
            return .meter
        }
        throw CADBenchmarkError.invalidInput(
            caseID: caseID.rawValue,
            reason: "The public line challenge has no supported length unit."
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
