struct CADTransformChallengeInput: Codable, Equatable, Hashable, Sendable {
    let source: CADTransformSource
    let translation: CADPoint3D
    let rotationAxis: CADDirection3D
    let rotation: CADAngle

    init(
        source: CADTransformSource,
        translation: CADPoint3D,
        rotationAxis: CADDirection3D,
        rotation: CADAngle
    ) {
        self.source = source
        self.translation = translation
        self.rotationAxis = rotationAxis
        self.rotation = rotation
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        try source.validate(caseID: caseID)
        try translation.validate(caseID: caseID, field: "transform.translation")
        try rotationAxis.validate(caseID: caseID, field: "transform.rotationAxis")
        try rotation.validate(caseID: caseID, field: "transform.rotation")
    }
}
