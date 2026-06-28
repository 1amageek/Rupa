import RupaCore

struct SurfaceFrameInspectorState: Equatable, Sendable {
    var positionTitle: String
    var uAxisTitle: String
    var vAxisTitle: String
    var normalTitle: String
    var handednessTitle: String
    var normalCurvatureTitle: String
    var principalCurvatureTitle: String
    var gaussianCurvatureTitle: String

    init(frame: SurfaceFrameResult.Frame) {
        self.positionTitle = formattedPoint(frame.position)
        self.uAxisTitle = formattedVector(frame.uAxis)
        self.vAxisTitle = formattedVector(frame.vAxis)
        self.normalTitle = formattedVector(frame.normal)
        self.handednessTitle = shortNumber(frame.handedness)
        self.normalCurvatureTitle = "U \(formattedCurvature(frame.normalCurvatureU)), V \(formattedCurvature(frame.normalCurvatureV))"
        self.principalCurvatureTitle = "Min \(formattedCurvature(frame.minimumPrincipalCurvature)), Max \(formattedCurvature(frame.maximumPrincipalCurvature))"
        self.gaussianCurvatureTitle = formattedGaussianCurvature(frame.gaussianCurvature)
    }
}

private func formattedPoint(_ point: SurfaceAnalysisResult.Point) -> String {
    "(\(shortNumber(point.x)), \(shortNumber(point.y)), \(shortNumber(point.z)))"
}

private func formattedVector(_ vector: SurfaceAnalysisResult.Vector) -> String {
    "(\(shortNumber(vector.x)), \(shortNumber(vector.y)), \(shortNumber(vector.z)))"
}

private func formattedCurvature(_ value: Double) -> String {
    "\(shortNumber(value)) 1/m"
}

private func formattedGaussianCurvature(_ value: Double) -> String {
    "\(shortNumber(value)) 1/m2"
}

private func shortNumber(_ value: Double) -> String {
    let normalizedValue = abs(value) < 1.0e-12 ? 0.0 : value
    return normalizedValue.formatted(.number.precision(.fractionLength(0...6)))
}
