struct CADLineChallengeInput: Codable, Equatable, Hashable, Sendable {
    let start: CADPoint3D
    let end: CADPoint3D
    let length: CADLength
    let plane: CADSketchPlane

    init(start: CADPoint3D, end: CADPoint3D, length: CADLength, plane: CADSketchPlane) {
        self.start = start
        self.end = end
        self.length = length
        self.plane = plane
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        try start.validate(caseID: caseID, field: "line.start")
        try end.validate(caseID: caseID, field: "line.end")
        try length.validate(caseID: caseID, field: "line.length")
    }
}
