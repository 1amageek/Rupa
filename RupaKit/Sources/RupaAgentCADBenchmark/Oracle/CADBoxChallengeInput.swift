struct CADBoxChallengeInput: Codable, Equatable, Hashable, Sendable {
    let origin: CADPoint3D
    let width: CADLength
    let depth: CADLength
    let height: CADLength

    init(origin: CADPoint3D, width: CADLength, depth: CADLength, height: CADLength) {
        self.origin = origin
        self.width = width
        self.depth = depth
        self.height = height
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        try origin.validate(caseID: caseID, field: "box.origin")
        try width.validate(caseID: caseID, field: "box.width")
        try depth.validate(caseID: caseID, field: "box.depth")
        try height.validate(caseID: caseID, field: "box.height")
    }

    var isCube: Bool {
        width.meters == depth.meters && depth.meters == height.meters
    }
}
