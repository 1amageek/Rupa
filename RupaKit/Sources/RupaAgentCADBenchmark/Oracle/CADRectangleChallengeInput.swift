struct CADRectangleChallengeInput: Codable, Equatable, Hashable, Sendable {
    let origin: CADPoint3D
    let width: CADLength
    let height: CADLength
    let plane: CADSketchPlane

    init(origin: CADPoint3D, width: CADLength, height: CADLength, plane: CADSketchPlane) {
        self.origin = origin
        self.width = width
        self.height = height
        self.plane = plane
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        try origin.validate(caseID: caseID, field: "rectangle.origin")
        try width.validate(caseID: caseID, field: "rectangle.width")
        try height.validate(caseID: caseID, field: "rectangle.height")
    }
}
