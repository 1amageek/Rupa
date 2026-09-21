struct CADCircleChallengeInput: Codable, Equatable, Hashable, Sendable {
    let center: CADPoint3D
    let radius: CADLength
    let plane: CADSketchPlane

    init(center: CADPoint3D, radius: CADLength, plane: CADSketchPlane) {
        self.center = center
        self.radius = radius
        self.plane = plane
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        try center.validate(caseID: caseID, field: "circle.center")
        try radius.validate(caseID: caseID, field: "circle.radius")
    }
}
