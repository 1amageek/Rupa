import Foundation

enum CADChallengeGeometryValidator {
    static func validate(_ input: CADChallengeInput, caseID: CADBenchmarkCaseID) throws {
        let tolerance = try CADBenchmarkTolerancePolicy(modelingTolerance: .standard)
        switch input {
        case let .line(input):
            try validateLine(input, caseID: caseID, tolerance: tolerance)
        case let .rectangle(input):
            try validateRectangle(input, caseID: caseID, tolerance: tolerance)
        case let .circle(input):
            try validateCircle(input, caseID: caseID, tolerance: tolerance)
        case let .angle(input):
            try validateAngle(input, caseID: caseID, tolerance: tolerance)
        case let .box(input):
            try validateBox(input, caseID: caseID, tolerance: tolerance)
        case let .cylinder(input):
            try validateCylinder(input, caseID: caseID, tolerance: tolerance)
        case let .constraint(input):
            try validateConstraint(input, challengeID: caseID)
        case let .transform(input):
            try validateTransformSource(input.source, caseID: caseID, tolerance: tolerance)
            try input.translation.validate(caseID: caseID, field: "transform.translation")
            try input.rotationAxis.validate(caseID: caseID, field: "transform.rotationAxis")
            try input.rotation.validate(caseID: caseID, field: "transform.rotation")
        case let .compound(input):
            try input.validate(caseID: caseID)
        case let .sphere(input):
            try input.validate(caseID: caseID)
            guard tolerance.isNonDegenerate(input.radius.meters) else {
                throw CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: "Sphere radius is within the degeneracy boundary.")
            }
        }
    }

    private static func validateLine(
        _ input: CADLineChallengeInput,
        caseID: CADBenchmarkCaseID,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        try input.validate(caseID: caseID)
        let start = input.start.meters
        let end = input.end.meters
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dz = end.z - start.z
        let actual = hypot(hypot(dx, dy), dz)
        let frame = input.plane.frame(anchor: input.start)
        guard tolerance.isNonDegenerate(actual),
              tolerance.acceptsLinear(expected: input.length.meters, observed: actual),
              pointLiesInFrame(frame, input.end, tolerance: tolerance.modelingTolerance.distance),
              directionLiesInPlane(x: dx, y: dy, z: dz, plane: input.plane, tolerance: tolerance) else {
            throw CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: "Line length or plane does not match its endpoints.")
        }
    }

    private static func validateRectangle(
        _ input: CADRectangleChallengeInput,
        caseID: CADBenchmarkCaseID,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        try input.validate(caseID: caseID)
        guard tolerance.isNonDegenerate(input.width.meters),
              tolerance.isNonDegenerate(input.height.meters) else {
            throw CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: "Rectangle dimension is within the degeneracy boundary.")
        }
    }

    private static func validateCircle(
        _ input: CADCircleChallengeInput,
        caseID: CADBenchmarkCaseID,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        try input.validate(caseID: caseID)
        guard tolerance.isNonDegenerate(input.radius.meters) else {
            throw CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: "Circle radius is within the degeneracy boundary.")
        }
    }

    private static func validateAngle(
        _ input: CADAngleChallengeInput,
        caseID: CADBenchmarkCaseID,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        try input.validate(caseID: caseID)
        guard tolerance.isNonDegenerate(input.firstLength.meters),
              tolerance.isNonDegenerate(input.secondLength.meters),
              input.includedAngle.radians <= .pi + tolerance.modelingTolerance.angle else {
            throw CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: "Included angle is outside the unsigned planar-angle domain.")
        }
        let firstMagnitude = input.firstDirection.length
        let secondMagnitude = input.secondDirection.length
        let dot = (input.firstDirection.x * input.secondDirection.x
            + input.firstDirection.y * input.secondDirection.y
            + input.firstDirection.z * input.secondDirection.z)
            / (firstMagnitude * secondMagnitude)
        let includedAngle = acos(max(-1.0, min(1.0, dot)))
        let frame = input.plane.frame(anchor: input.intersection)
        let firstEndpoint = pointAlongDirection(
            from: input.intersection,
            direction: input.firstDirection,
            distance: input.firstLength.meters
        )
        let secondEndpoint = pointAlongDirection(
            from: input.intersection,
            direction: input.secondDirection,
            distance: input.secondLength.meters
        )
        guard directionLiesInPlane(
            x: input.firstDirection.x,
            y: input.firstDirection.y,
            z: input.firstDirection.z,
            plane: input.plane,
            tolerance: tolerance
        ),
        directionLiesInPlane(
            x: input.secondDirection.x,
            y: input.secondDirection.y,
            z: input.secondDirection.z,
            plane: input.plane,
            tolerance: tolerance
        ),
        pointLiesInFrame(frame, firstEndpoint, tolerance: tolerance.modelingTolerance.distance),
        pointLiesInFrame(frame, secondEndpoint, tolerance: tolerance.modelingTolerance.distance),
        tolerance.acceptsAngle(expected: input.includedAngle.radians, observed: includedAngle) else {
            throw CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: "Angle directions do not match the requested included angle.")
        }
    }

    private static func validateBox(
        _ input: CADBoxChallengeInput,
        caseID: CADBenchmarkCaseID,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        try input.validate(caseID: caseID)
        guard tolerance.isNonDegenerate(input.width.meters),
              tolerance.isNonDegenerate(input.depth.meters),
              tolerance.isNonDegenerate(input.height.meters) else {
            throw CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: "Box dimension is within the degeneracy boundary.")
        }
    }

    private static func validateCylinder(
        _ input: CADCylinderChallengeInput,
        caseID: CADBenchmarkCaseID,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        try input.validate(caseID: caseID)
        guard tolerance.isNonDegenerate(input.radius.meters),
              tolerance.isNonDegenerate(input.depth.meters) else {
            throw CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: "Cylinder dimension is within the degeneracy boundary.")
        }
    }

    private static func validateTransformSource(
        _ source: CADTransformSource,
        caseID: CADBenchmarkCaseID,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        switch source {
        case let .line(input):
            try validateLine(input, caseID: caseID, tolerance: tolerance)
        case let .rectangle(input):
            try validateRectangle(input, caseID: caseID, tolerance: tolerance)
        case let .circle(input):
            try validateCircle(input, caseID: caseID, tolerance: tolerance)
        case let .box(input):
            try validateBox(input, caseID: caseID, tolerance: tolerance)
        case let .cylinder(input):
            try validateCylinder(input, caseID: caseID, tolerance: tolerance)
        }
    }

    private static func validateConstraint(
        _ input: CADConstraintChallengeInput,
        challengeID: CADBenchmarkCaseID
    ) throws {
        try input.validate(caseID: challengeID)
        let tolerance = try CADBenchmarkTolerancePolicy(modelingTolerance: .standard)
        try validateConstraintGeometry(input.first, challengeID: challengeID, tolerance: tolerance)
        if let second = input.second {
            try validateConstraintGeometry(second, challengeID: challengeID, tolerance: tolerance)
        }
        switch input.relation {
        case .coincident:
            guard case let .line(first) = input.first,
                  case let .line(second) = input.second,
                  sameGeometricPlane(first, second, tolerance: tolerance),
                  pointsAreClose(first.end.meters, second.end.meters, tolerance: tolerance) else {
                throw CADBenchmarkError.invalidInput(caseID: challengeID.rawValue, reason: "Coincident relation inputs do not share a point.")
            }
        case .parallel:
            guard case let .line(first) = input.first,
                  case let .line(second) = input.second,
                  sameGeometricPlane(first, second, tolerance: tolerance),
                  directionsAreParallel(first, second, tolerance: tolerance) else {
                throw CADBenchmarkError.invalidInput(caseID: challengeID.rawValue, reason: "Parallel relation inputs are not parallel in the same plane.")
            }
        case .perpendicular:
            guard case let .line(first) = input.first,
                  case let .line(second) = input.second,
                  sameGeometricPlane(first, second, tolerance: tolerance),
                  directionsArePerpendicular(first, second, tolerance: tolerance) else {
                throw CADBenchmarkError.invalidInput(caseID: challengeID.rawValue, reason: "Perpendicular relation inputs are not perpendicular in the same plane.")
            }
        case .horizontal:
            guard case let .line(line) = input.first,
                  directionIsHorizontal(line, tolerance: tolerance) else {
                throw CADBenchmarkError.invalidInput(caseID: challengeID.rawValue, reason: "Horizontal relation input is not horizontal in its sketch plane.")
            }
        case .vertical:
            guard case let .line(line) = input.first,
                  directionIsVertical(line, tolerance: tolerance) else {
                throw CADBenchmarkError.invalidInput(caseID: challengeID.rawValue, reason: "Vertical relation input is not vertical in its sketch plane.")
            }
        case .equalLength:
            guard case let .line(first) = input.first,
                  case let .line(second) = input.second,
                  sameGeometricPlane(first, second, tolerance: tolerance),
                  lineLengthsAreEqual(first, second, tolerance: tolerance) else {
                throw CADBenchmarkError.invalidInput(caseID: challengeID.rawValue, reason: "Equal-length relation inputs have different lengths or planes.")
            }
        case .concentric:
            guard case let .circle(first) = input.first,
                  case let .circle(second) = input.second,
                  sameGeometricPlane(first, second, tolerance: tolerance),
                  pointsAreClose(first.center.meters, second.center.meters, tolerance: tolerance) else {
                throw CADBenchmarkError.invalidInput(caseID: challengeID.rawValue, reason: "Concentric relation inputs have different centers or planes.")
            }
        case .equalRadius:
            guard case let .circle(first) = input.first,
                  case let .circle(second) = input.second,
                  sameGeometricPlane(first, second, tolerance: tolerance),
                  tolerance.acceptsLinear(expected: first.radius.meters, observed: second.radius.meters) else {
                throw CADBenchmarkError.invalidInput(caseID: challengeID.rawValue, reason: "Equal-radius relation inputs have different radii or planes.")
            }
        }
    }

    private static func validateConstraintGeometry(
        _ geometry: CADConstraintGeometryInput,
        challengeID: CADBenchmarkCaseID,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        switch geometry {
        case let .line(line):
            try validateLine(line, caseID: challengeID, tolerance: tolerance)
        case let .circle(circle):
            try validateCircle(circle, caseID: challengeID, tolerance: tolerance)
        }
    }

    private static func sameGeometricPlane(
        _ first: CADLineChallengeInput,
        _ second: CADLineChallengeInput,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        guard first.plane == second.plane else { return false }
        return pointLiesInFrame(
            first.plane.frame(anchor: first.start),
            second.start,
            tolerance: tolerance.modelingTolerance.distance
        )
    }

    private static func sameGeometricPlane(
        _ first: CADCircleChallengeInput,
        _ second: CADCircleChallengeInput,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        guard first.plane == second.plane else { return false }
        return pointLiesInFrame(
            first.plane.frame(anchor: first.center),
            second.center,
            tolerance: tolerance.modelingTolerance.distance
        )
    }

    private static func pointsAreClose(
        _ first: CADPoint3D,
        _ second: CADPoint3D,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        let distance = hypot(hypot(first.x - second.x, first.y - second.y), first.z - second.z)
        return tolerance.acceptsLinear(expected: 0.0, observed: distance)
    }

    private static func lineVector(_ line: CADLineChallengeInput) -> CADDirection3D {
        let start = line.start.meters
        let end = line.end.meters
        return CADDirection3D(x: end.x - start.x, y: end.y - start.y, z: end.z - start.z)
    }

    private static func pointAlongDirection(
        from origin: CADPoint3D,
        direction: CADDirection3D,
        distance: Double
    ) -> CADPoint3D {
        let point = origin.meters
        let magnitude = direction.length
        let scale = distance / magnitude
        return CADPoint3D(
            x: point.x + direction.x * scale,
            y: point.y + direction.y * scale,
            z: point.z + direction.z * scale,
            unit: .meter
        )
    }

    private static func directionsAreParallel(
        _ first: CADLineChallengeInput,
        _ second: CADLineChallengeInput,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        let a = lineVector(first)
        let b = lineVector(second)
        let denominator = a.length * b.length
        guard denominator > 0.0 else { return false }
        let crossX = a.y * b.z - a.z * b.y
        let crossY = a.z * b.x - a.x * b.z
        let crossZ = a.x * b.y - a.y * b.x
        let normalizedCross = hypot(hypot(crossX, crossY), crossZ) / denominator
        return normalizedCross <= tolerance.modelingTolerance.angle
    }

    private static func directionsArePerpendicular(
        _ first: CADLineChallengeInput,
        _ second: CADLineChallengeInput,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        let a = lineVector(first)
        let b = lineVector(second)
        let denominator = a.length * b.length
        guard denominator > 0.0 else { return false }
        let normalizedDot = abs((a.x * b.x + a.y * b.y + a.z * b.z) / denominator)
        return normalizedDot <= tolerance.modelingTolerance.angle
    }

    private static func directionIsHorizontal(
        _ line: CADLineChallengeInput,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        let vector = lineVector(line)
        let (horizontal, vertical) = planarComponents(vector, plane: line.plane)
        return abs(vertical) <= vector.length * max(tolerance.modelingTolerance.angle, tolerance.modelingTolerance.relative)
            && abs(horizontal) > tolerance.modelingTolerance.distance
    }

    private static func directionIsVertical(
        _ line: CADLineChallengeInput,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        let vector = lineVector(line)
        let (horizontal, vertical) = planarComponents(vector, plane: line.plane)
        return abs(horizontal) <= vector.length * max(tolerance.modelingTolerance.angle, tolerance.modelingTolerance.relative)
            && abs(vertical) > tolerance.modelingTolerance.distance
    }

    private static func lineLengthsAreEqual(
        _ first: CADLineChallengeInput,
        _ second: CADLineChallengeInput,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        let firstLength = lineVector(first).length
        let secondLength = lineVector(second).length
        return tolerance.acceptsLinear(expected: firstLength, observed: secondLength)
    }

    private static func planarComponents(
        _ direction: CADDirection3D,
        plane: CADSketchPlane
    ) -> (horizontal: Double, vertical: Double) {
        switch plane {
        case .xy:
            (direction.x, direction.y)
        case .xz:
            (direction.x, direction.z)
        case .yz:
            (direction.y, direction.z)
        }
    }

    private static func directionLiesInPlane(
        x: Double,
        y: Double,
        z: Double,
        plane: CADSketchPlane,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        let normalComponent: Double
        switch plane {
        case .xy:
            normalComponent = z
        case .xz:
            normalComponent = y
        case .yz:
            normalComponent = x
        }
        let magnitude = hypot(hypot(x, y), z)
        return normalComponent.isFinite
            && magnitude.isFinite
            && magnitude > 0.0
            && abs(normalComponent) <= magnitude * max(tolerance.modelingTolerance.relative, tolerance.modelingTolerance.angle)
    }

    private static func pointLiesInFrame(
        _ frame: CADPlaneFrame,
        _ point: CADPoint3D,
        tolerance: Double
    ) -> Bool {
        let distance = frame.signedNormalDistance(to: point)
        return distance.isFinite && tolerance.isFinite && tolerance > 0.0 && abs(distance) <= tolerance
    }
}
