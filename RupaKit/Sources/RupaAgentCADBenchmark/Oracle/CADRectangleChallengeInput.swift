struct CADRectangleChallengeInput: Codable, Equatable, Hashable, Sendable {
    let center: CADPoint3D
    let width: CADLength
    let height: CADLength
    let plane: CADSketchPlane

    init(center: CADPoint3D, width: CADLength, height: CADLength, plane: CADSketchPlane) {
        self.center = center
        self.width = width
        self.height = height
        self.plane = plane
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        try center.validate(caseID: caseID, field: "rectangle.center")
        try width.validate(caseID: caseID, field: "rectangle.width")
        try height.validate(caseID: caseID, field: "rectangle.height")
    }
}
