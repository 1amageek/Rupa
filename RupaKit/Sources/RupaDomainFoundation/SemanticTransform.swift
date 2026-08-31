public struct SemanticTransform: Sendable, Equatable, Hashable {
    public let translation: SemanticPoint3D
    public let axisPoint: SemanticPoint3D
    public let rotationAxis: SemanticDirection3D
    public let rotation: SemanticAngle

    public init(
        translation: SemanticPoint3D,
        axisPoint: SemanticPoint3D,
        rotationAxis: SemanticDirection3D,
        rotation: SemanticAngle
    ) {
        self.translation = translation
        self.axisPoint = axisPoint
        self.rotationAxis = rotationAxis
        self.rotation = rotation
    }

    public var isFinite: Bool {
        translation.isFinite
            && axisPoint.isFinite
            && rotationAxis.isFinite
            && rotation.isFinite
            && translation.isValidUnit
            && axisPoint.isValidUnit
            && rotation.isValidUnit
    }
}
