import Foundation

/// Candidate-visible transform values decoded only from the public instruction.
struct CADTransformChallengeProjection: Sendable {
    enum Source: Sendable {
        case line(CADLineChallengeProjection)
        case rectangle(CADRectangleChallengeProjection)
        case circle(CADCircleChallengeProjection)
        case box(CADBoxChallengeProjection)
        case cylinder(CADCylinderChallengeProjection)
    }

    let id: CADBenchmarkCaseID
    let source: Source
    let translation: CADPoint3D
    let axisPoint: CADPoint3D
    let rotationAxis: CADDirection3D
    let rotation: CADAngle

    static func decode(_ challenge: CADChallenge) throws -> CADTransformChallengeProjection {
        guard challenge.category == .transform else {
            throw invalid(challenge.id, "A transform projection requires a transform challenge.")
        }
        try challenge.validate()
        guard let sourceStart = challenge.instruction.range(of: "first rotating ")?.upperBound,
              let sourceEnd = challenge.instruction.range(
                of: " by ",
                range: sourceStart..<challenge.instruction.endIndex
              )?.lowerBound else {
            throw invalid(challenge.id, "The public transform source clause is missing.")
        }

        let sourceText = String(challenge.instruction[sourceStart..<sourceEnd])
        let suffixText = String(challenge.instruction[sourceEnd...])
        let suffix = numericValues(in: suffixText)
        guard suffix.count == 10 else {
            throw invalid(
                challenge.id,
                "The transform clause must expose angle, axis point, axis direction, and translation."
            )
        }
        let unit = try lengthUnit(in: challenge.instruction, caseID: challenge.id)
        let angleUnit: CADAngleUnit = challenge.instruction.contains(" radian")
            ? .radian
            : .degree
        let projection = CADTransformChallengeProjection(
            id: challenge.id,
            source: try source(
                from: sourceText,
                unit: unit,
                caseID: challenge.id
            ),
            translation: CADPoint3D(
                x: suffix[7],
                y: suffix[8],
                z: suffix[9],
                unit: unit
            ),
            axisPoint: CADPoint3D(
                x: suffix[1],
                y: suffix[2],
                z: suffix[3],
                unit: unit
            ),
            rotationAxis: CADDirection3D(
                x: suffix[4],
                y: suffix[5],
                z: suffix[6]
            ),
            rotation: CADAngle(value: suffix[0], unit: angleUnit)
        )
        try projection.validate()
        return projection
    }

    func validate() throws {
        try translation.validate(caseID: id, field: "transform.translation")
        try axisPoint.validate(caseID: id, field: "transform.axisPoint")
        try rotationAxis.validate(caseID: id, field: "transform.rotationAxis")
        try rotation.validate(caseID: id, field: "transform.rotation")
    }

    private static func source(
        from text: String,
        unit: CADLengthUnit,
        caseID: CADBenchmarkCaseID
    ) throws -> Source {
        let values = numericValues(in: text)
        if text.hasPrefix("line ") {
            guard values.count == 6 else {
                throw invalid(caseID, "The transform line source is incomplete.")
            }
            let plane = try sketchPlane(in: text, caseID: caseID)
            let start = CADPoint3D(x: values[0], y: values[1], z: values[2], unit: unit)
            let end = CADPoint3D(x: values[3], y: values[4], z: values[5], unit: unit)
            let delta = end.meters
            let origin = start.meters
            let length = hypot(
                hypot(delta.x - origin.x, delta.y - origin.y),
                delta.z - origin.z
            )
            return .line(CADLineChallengeProjection(
                id: caseID,
                orientation: plane,
                length: CADLength(value: length, unit: .meter),
                start: start,
                end: end,
                anchor: start
            ))
        }
        if text.hasPrefix("rectangle ") {
            guard values.count == 5 else {
                throw invalid(caseID, "The transform rectangle source is incomplete.")
            }
            return .rectangle(CADRectangleChallengeProjection(
                id: caseID,
                orientation: try sketchPlane(in: text, caseID: caseID),
                center: CADPoint3D(x: values[2], y: values[3], z: values[4], unit: unit),
                width: CADLength(value: values[0], unit: unit),
                height: CADLength(value: values[1], unit: unit)
            ))
        }
        if text.hasPrefix("circle ") {
            guard values.count == 4 else {
                throw invalid(caseID, "The transform circle source is incomplete.")
            }
            return .circle(CADCircleChallengeProjection(
                id: caseID,
                orientation: try sketchPlane(in: text, caseID: caseID),
                center: CADPoint3D(x: values[1], y: values[2], z: values[3], unit: unit),
                radius: CADLength(value: values[0], unit: unit)
            ))
        }
        if text.hasPrefix("box ") {
            guard values.count == 6 else {
                throw invalid(caseID, "The transform box source is incomplete.")
            }
            return .box(CADBoxChallengeProjection(
                id: caseID,
                origin: CADPoint3D(x: values[3], y: values[4], z: values[5], unit: unit),
                width: CADLength(value: values[0], unit: unit),
                depth: CADLength(value: values[1], unit: unit),
                height: CADLength(value: values[2], unit: unit)
            ))
        }
        if text.hasPrefix("cylinder ") {
            guard values.count == 8 else {
                throw invalid(caseID, "The transform cylinder source is incomplete.")
            }
            return .cylinder(CADCylinderChallengeProjection(
                id: caseID,
                baseCenter: CADPoint3D(x: values[2], y: values[3], z: values[4], unit: unit),
                axis: CADDirection3D(x: values[5], y: values[6], z: values[7]),
                radius: CADLength(value: values[0], unit: unit),
                depth: CADLength(value: values[1], unit: unit)
            ))
        }
        throw invalid(caseID, "The public transform source kind is unsupported.")
    }

    private static func sketchPlane(
        in text: String,
        caseID: CADBenchmarkCaseID
    ) throws -> CADSketchPlane {
        if text.contains("on the xy plane") { return .xy }
        if text.contains("on the xz plane") { return .xz }
        if text.contains("on the yz plane") { return .yz }
        throw invalid(caseID, "The transform source has no supported sketch plane.")
    }

    private static func lengthUnit(
        in text: String,
        caseID: CADBenchmarkCaseID
    ) throws -> CADLengthUnit {
        if text.contains(" mm") { return .millimeter }
        if text.contains(" cm") { return .centimeter }
        if text.contains(" in") { return .inch }
        if text.contains(" m") { return .meter }
        throw invalid(caseID, "The transform challenge has no supported length unit.")
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

    private static func invalid(
        _ caseID: CADBenchmarkCaseID,
        _ reason: String
    ) -> CADBenchmarkError {
        CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: reason)
    }
}
