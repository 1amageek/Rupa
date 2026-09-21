struct CADSphereChallengeInput: Codable, Equatable, Hashable, Sendable {
    let center: CADPoint3D
    let radius: CADLength

    init(center: CADPoint3D, radius: CADLength) {
        self.center = center
        self.radius = radius
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        try center.validate(caseID: caseID, field: "sphere.center")
        try radius.validate(caseID: caseID, field: "sphere.radius")
    }
}
