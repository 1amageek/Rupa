/// Category-local submission used before transform is added to shared wire authority.
struct CADTransformSubmission: Codable, Equatable, Sendable {
    let translation: CADPoint3D
    let axisPoint: CADPoint3D
    let rotationAxis: CADDirection3D
    let rotation: CADAngle

    func validate(caseID: CADBenchmarkCaseID) throws {
        try translation.validate(caseID: caseID, field: "transform.translation")
        try axisPoint.validate(caseID: caseID, field: "transform.axisPoint")
        try rotationAxis.validate(caseID: caseID, field: "transform.rotationAxis")
        try rotation.validate(caseID: caseID, field: "transform.rotation")
    }
}
