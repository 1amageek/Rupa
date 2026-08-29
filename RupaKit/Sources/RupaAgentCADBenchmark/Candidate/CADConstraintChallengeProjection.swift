import Foundation

/// Candidate-visible constraint values decoded only from the public instruction.
struct CADConstraintChallengeProjection: Sendable {
    let id: CADBenchmarkCaseID
    let plane: CADSketchPlane
    let relation: CADConstraintRelation
    let first: CADConstraintGeometry
    let second: CADConstraintGeometry?

    static func decode(_ challenge: CADChallenge) throws -> CADConstraintChallengeProjection {
        guard challenge.category == .constraint else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "A constraint projection requires a constraint challenge."
            )
        }
        try challenge.validate()

        guard let relation = CADConstraintRelation.allCases.first(where: {
            challenge.instruction.contains("applying the \($0.rawValue) relation")
        }) else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public constraint instruction has no supported relation."
            )
        }
        // Constraint capability v1 is intentionally XY-only. A future plane-aware
        // constraint schema must version this candidate contract before expansion.
        let plane = CADSketchPlane.xy
        guard let geometryRange = challenge.instruction.range(of: " relation to ") else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public constraint instruction has no geometry clause."
            )
        }
        let geometryText = String(challenge.instruction[geometryRange.upperBound...].dropLast())
        let components = geometryText.components(separatedBy: " and ")
        guard components.count == 1 || components.count == 2 else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public constraint instruction has an invalid geometry count."
            )
        }
        let first = try geometry(
            from: components[0],
            caseID: challenge.id,
            field: "constraint.first"
        )
        let second = try components.dropFirst().first.map {
            try geometry(from: $0, caseID: challenge.id, field: "constraint.second")
        }
        return CADConstraintChallengeProjection(
            id: challenge.id,
            plane: plane,
            relation: relation,
            first: first,
            second: second
        )
    }

    private static func geometry(
        from text: String,
        caseID: CADBenchmarkCaseID,
        field: String
    ) throws -> CADConstraintGeometry {
        let unit = try unit(in: text, caseID: caseID)
        let values = numericValues(in: text)
        if text.hasPrefix("line "), values.count == 6 {
            let start = CADPoint3D(x: values[0], y: values[1], z: values[2], unit: unit)
            let end = CADPoint3D(x: values[3], y: values[4], z: values[5], unit: unit)
            try start.validate(caseID: caseID, field: "\(field).start")
            try end.validate(caseID: caseID, field: "\(field).end")
            return .line(start: start, end: end)
        }
        if text.hasPrefix("circle radius "), values.count == 4 {
            let radius = CADLength(value: values[0], unit: unit)
            let center = CADPoint3D(x: values[1], y: values[2], z: values[3], unit: unit)
            try radius.validate(caseID: caseID, field: "\(field).radius")
            try center.validate(caseID: caseID, field: "\(field).center")
            return .circle(center: center, radius: radius)
        }
        throw CADBenchmarkError.invalidInput(
            caseID: caseID.rawValue,
            reason: "The public \(field) geometry is unsupported."
        )
    }

    private static func unit(
        in text: String,
        caseID: CADBenchmarkCaseID
    ) throws -> CADLengthUnit {
        if text.contains(" mm") { return .millimeter }
        if text.contains(" cm") { return .centimeter }
        if text.contains(" in") { return .inch }
        if text.contains(" m") { return .meter }
        throw CADBenchmarkError.invalidInput(
            caseID: caseID.rawValue,
            reason: "The public constraint geometry has no supported unit."
        )
    }

    private static func numericValues(in text: String) -> [Double] {
        var values: [Double] = []
        var token = ""
        func flush() {
            defer { token.removeAll(keepingCapacity: true) }
            if let value = Double(token) {
                values.append(value)
            }
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
