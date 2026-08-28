struct CADAngleChallengeInput: Codable, Equatable, Hashable, Sendable {
    let intersection: CADPoint3D
    let firstDirection: CADDirection3D
    let secondDirection: CADDirection3D
    let firstLength: CADLength
    let secondLength: CADLength
    let includedAngle: CADAngle
    let plane: CADSketchPlane

    init(
        intersection: CADPoint3D,
        firstDirection: CADDirection3D,
        secondDirection: CADDirection3D,
        firstLength: CADLength,
        secondLength: CADLength,
        includedAngle: CADAngle,
        plane: CADSketchPlane
    ) {
        self.intersection = intersection
        self.firstDirection = firstDirection
        self.secondDirection = secondDirection
        self.firstLength = firstLength
        self.secondLength = secondLength
        self.includedAngle = includedAngle
        self.plane = plane
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        try intersection.validate(caseID: caseID, field: "angle.intersection")
        try firstDirection.validate(caseID: caseID, field: "angle.firstDirection")
        try secondDirection.validate(caseID: caseID, field: "angle.secondDirection")
        try firstLength.validate(caseID: caseID, field: "angle.firstLength")
        try secondLength.validate(caseID: caseID, field: "angle.secondLength")
        try includedAngle.validate(caseID: caseID, field: "angle.includedAngle")
    }
}
