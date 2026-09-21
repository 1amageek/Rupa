import Foundation

/// Candidate-visible compound members decoded from the canonical instruction.
struct CADCompoundChallengeProjection: Equatable, Sendable {
    struct Member: Equatable, Sendable {
        let role: String
        let primitive: CADPrimitiveKind
        let box: CADBoxChallengeInput?
        let cylinder: CADCylinderChallengeInput?

        init(role: String, box: CADBoxChallengeInput) {
            self.role = role
            primitive = .box
            self.box = box
            cylinder = nil
        }

        init(role: String, cylinder: CADCylinderChallengeInput) {
            self.role = role
            primitive = .cylinder
            box = nil
            self.cylinder = cylinder
        }
    }

    let id: CADBenchmarkCaseID
    let members: [Member]

    static func decode(_ challenge: CADChallenge) throws -> CADCompoundChallengeProjection {
        guard challenge.category == .compound else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "A compound projection requires a compound challenge."
            )
        }
        try challenge.validate()
        let roles = challenge.outputRoles.map(\.name)
        guard !roles.isEmpty else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "A compound challenge must declare output roles."
            )
        }

        let prefix = "Construct \(challenge.id) as a compound containing "
        guard challenge.instruction.hasPrefix(prefix),
              challenge.instruction.hasSuffix(".") else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The compound challenge instruction has an unsupported form."
            )
        }
        let bodyStart = challenge.instruction.index(
            challenge.instruction.startIndex,
            offsetBy: prefix.count
        )
        let bodyEnd = challenge.instruction.index(
            challenge.instruction.endIndex,
            offsetBy: -1
        )
        let body = String(challenge.instruction[bodyStart..<bodyEnd])

        var members: [Member] = []
        members.reserveCapacity(roles.count)
        var cursor = body.startIndex
        for (index, role) in roles.enumerated() {
            let marker = "\(role)="
            guard body[cursor...].hasPrefix(marker) else {
                throw CADBenchmarkError.invalidInput(
                    caseID: challenge.id.rawValue,
                    reason: "Compound member order or role \(role) is not public in the instruction."
                )
            }
            let valueStart = body.index(cursor, offsetBy: marker.count)
            let valueEnd: String.Index
            if index + 1 < roles.count {
                let nextMarker = ", \(roles[index + 1])="
                guard let range = body.range(of: nextMarker, range: valueStart..<body.endIndex) else {
                    throw CADBenchmarkError.invalidInput(
                        caseID: challenge.id.rawValue,
                        reason: "Compound member \(role) has no bounded public value."
                    )
                }
                valueEnd = range.lowerBound
                cursor = body.index(range.lowerBound, offsetBy: 2)
            } else {
                valueEnd = body.endIndex
                cursor = body.endIndex
            }
            let value = String(body[valueStart..<valueEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            members.append(try parseMember(role: role, value: value, caseID: challenge.id))
        }

        guard cursor == body.endIndex,
              members.map(\.role) == roles else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "Compound public member roles must preserve declared order."
            )
        }
        let projection = CADCompoundChallengeProjection(id: challenge.id, members: members)
        try projection.validate()
        return projection
    }

    func validate() throws {
        guard CADCompoundPreparedCase(rawValue: id.rawValue) != nil,
              !members.isEmpty else {
            throw CADBenchmarkError.invalidInput(
                caseID: id.rawValue,
                reason: "The compound projection is empty or unprepared."
            )
        }
        var roles = Set<String>()
        for member in members {
            guard roles.insert(member.role).inserted,
                  member.role.isEmpty == false,
                  member.role.trimmingCharacters(in: .whitespacesAndNewlines) == member.role else {
                throw CADBenchmarkError.duplicateRole(caseID: id.rawValue, role: member.role)
            }
            switch member.primitive {
            case .box:
                guard let box = member.box, member.cylinder == nil else {
                    throw CADBenchmarkError.invalidInput(
                        caseID: id.rawValue,
                        reason: "A projected box member must contain only box values."
                    )
                }
                try box.validate(caseID: id)
            case .cylinder:
                guard let cylinder = member.cylinder, member.box == nil else {
                    throw CADBenchmarkError.invalidInput(
                        caseID: id.rawValue,
                        reason: "A projected cylinder member must contain only cylinder values."
                    )
                }
                try cylinder.validate(caseID: id)
            }
        }
    }

    private static func parseMember(
        role: String,
        value: String,
        caseID: CADBenchmarkCaseID
    ) throws -> Member {
        let tokens = value.split(separator: " ").map(String.init)
        if tokens.first == "box" {
            guard tokens.count == 14,
                  tokens[3] == "x",
                  tokens[6] == "x",
                  tokens[9] == "at" else {
                throw malformedMember(role: role, caseID: caseID)
            }
            let unit = try parseUnit(tokens[13], role: role, caseID: caseID)
            let origin = try parsePoint(
                tokens[10...12].joined(separator: " "),
                unit: unit,
                role: role,
                caseID: caseID
            )
            let widthUnit = try parseUnit(tokens[2], role: role, caseID: caseID)
            let depthUnit = try parseUnit(tokens[5], role: role, caseID: caseID)
            let heightUnit = try parseUnit(tokens[8], role: role, caseID: caseID)
            guard widthUnit == unit,
                  depthUnit == unit,
                  heightUnit == unit,
                  let width = Double(tokens[1]),
                  let depth = Double(tokens[4]),
                  let height = Double(tokens[7]) else {
                throw malformedMember(role: role, caseID: caseID)
            }
            return Member(
                role: role,
                box: CADBoxChallengeInput(
                    origin: origin,
                    width: CADLength(value: width, unit: unit),
                    depth: CADLength(value: depth, unit: unit),
                    height: CADLength(value: height, unit: unit)
                )
            )
        }

        guard tokens.first == "cylinder",
              tokens.count == 17,
              tokens[1] == "radius",
              tokens[4] == "depth",
              tokens[7] == "at",
              tokens[12] == "along",
              tokens[13] == "axis" else {
            throw malformedMember(role: role, caseID: caseID)
        }
        let unit = try parseUnit(tokens[11], role: role, caseID: caseID)
        let radiusUnit = try parseUnit(tokens[3], role: role, caseID: caseID)
        let depthUnit = try parseUnit(tokens[6], role: role, caseID: caseID)
        guard radiusUnit == unit, depthUnit == unit,
              let radius = Double(tokens[2]),
              let depth = Double(tokens[5]) else {
            throw malformedMember(role: role, caseID: caseID)
        }
        let baseCenter = try parsePoint(
            tokens[8...10].joined(separator: " "),
            unit: unit,
            role: role,
            caseID: caseID
        )
        let axis = try parseDirection(
            tokens[14...16].joined(separator: " "),
            role: role,
            caseID: caseID
        )
        return Member(
            role: role,
            cylinder: CADCylinderChallengeInput(
                baseCenter: baseCenter,
                axis: axis,
                radius: CADLength(value: radius, unit: unit),
                depth: CADLength(value: depth, unit: unit)
            )
        )
    }

    private static func parseUnit(
        _ value: String,
        role: String,
        caseID: CADBenchmarkCaseID
    ) throws -> CADLengthUnit {
        switch value {
        case "mm": return .millimeter
        case "cm": return .centimeter
        case "m": return .meter
        case "in": return .inch
        default: throw malformedMember(role: role, caseID: caseID)
        }
    }

    private static func parsePoint(
        _ value: String,
        unit: CADLengthUnit,
        role: String,
        caseID: CADBenchmarkCaseID
    ) throws -> CADPoint3D {
        let values = try parseTriple(value, role: role, caseID: caseID)
        return CADPoint3D(x: values[0], y: values[1], z: values[2], unit: unit)
    }

    private static func parseDirection(
        _ value: String,
        role: String,
        caseID: CADBenchmarkCaseID
    ) throws -> CADDirection3D {
        let values = try parseTriple(value, role: role, caseID: caseID)
        return CADDirection3D(x: values[0], y: values[1], z: values[2])
    }

    private static func parseTriple(
        _ value: String,
        role: String,
        caseID: CADBenchmarkCaseID
    ) throws -> [Double] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "(", trimmed.last == ")" else {
            throw malformedMember(role: role, caseID: caseID)
        }
        let inner = trimmed.dropFirst().dropLast()
        let values = inner.split(separator: ",", omittingEmptySubsequences: false)
        guard values.count == 3,
              let x = Double(values[0].trimmingCharacters(in: .whitespaces)),
              let y = Double(values[1].trimmingCharacters(in: .whitespaces)),
              let z = Double(values[2].trimmingCharacters(in: .whitespaces)) else {
            throw malformedMember(role: role, caseID: caseID)
        }
        return [x, y, z]
    }

    private static func malformedMember(
        role: String,
        caseID: CADBenchmarkCaseID
    ) -> CADBenchmarkError {
        .invalidInput(
            caseID: caseID.rawValue,
            reason: "Public compound member \(role) is malformed."
        )
    }
}
