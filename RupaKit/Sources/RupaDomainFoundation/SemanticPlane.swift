public struct SemanticPlane: Sendable, Equatable, Hashable {
    public let origin: SemanticPoint3D
    public let normal: SemanticDirection3D

    public init(origin: SemanticPoint3D, normal: SemanticDirection3D) {
        self.origin = origin
        self.normal = normal
    }

    public var isFinite: Bool {
        origin.isFinite && origin.isValidUnit && normal.isFinite
    }
}
