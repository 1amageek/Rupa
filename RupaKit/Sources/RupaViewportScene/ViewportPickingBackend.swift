public enum ViewportPickingBackend: String, Codable, Equatable, Sendable {
    case projectedCPU
    case identityBuffer
    /// The mounted RealityKit frame: native ray, native projection and the
    /// identity prepared by evaluation.
    case native

    public var title: String {
        switch self {
        case .projectedCPU:
            "CPU"
        case .identityBuffer:
            "Identity"
        case .native:
            "Native"
        }
    }

    /// Reports whether the hit came from an exact identity-backed query rather
    /// than a projected CPU approximation of the displayed frame.
    public var isExactIdentityBacked: Bool {
        self == .identityBuffer || self == .native
    }
}
