struct CADCylinderChallengeInput: Codable, Equatable, Hashable, Sendable {
    let baseCenter: CADPoint3D
    let axis: CADDirection3D
    let radius: CADLength
    let depth: CADLength

    init(baseCenter: CADPoint3D, axis: CADDirection3D, radius: CADLength, depth: CADLength) {
        self.baseCenter = baseCenter
        self.axis = axis
        self.radius = radius
        self.depth = depth
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        try baseCenter.validate(caseID: caseID, field: "cylinder.baseCenter")
        try axis.validate(caseID: caseID, field: "cylinder.axis")
        try radius.validate(caseID: caseID, field: "cylinder.radius")
        try depth.validate(caseID: caseID, field: "cylinder.depth")
    }
}
