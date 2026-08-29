struct CADTransformChallengeInput: Codable, Equatable, Hashable, Sendable {
    let source: CADTransformSource
    let translation: CADPoint3D
    let axisPoint: CADPoint3D
    let rotationAxis: CADDirection3D
    let rotation: CADAngle

    init(
        source: CADTransformSource,
        translation: CADPoint3D,
        axisPoint: CADPoint3D,
        rotationAxis: CADDirection3D,
        rotation: CADAngle
    ) {
        self.source = source
        self.translation = translation
        self.axisPoint = axisPoint
        self.rotationAxis = rotationAxis
        self.rotation = rotation
    }

    func validate(caseID: CADBenchmarkCaseID) throws {
        try source.validate(caseID: caseID)
        try translation.validate(caseID: caseID, field: "transform.translation")
        try axisPoint.validate(caseID: caseID, field: "transform.axisPoint")
        try rotationAxis.validate(caseID: caseID, field: "transform.rotationAxis")
        try rotation.validate(caseID: caseID, field: "transform.rotation")
    }
}
