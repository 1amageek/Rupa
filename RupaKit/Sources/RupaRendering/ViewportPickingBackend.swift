public enum ViewportPickingBackend: String, Codable, Equatable, Sendable {
    case projectedCPU
    case identityBuffer

    public var title: String {
        switch self {
        case .projectedCPU:
            "CPU"
        case .identityBuffer:
            "Identity"
        }
    }

    public var isExactIdentityBacked: Bool {
        self == .identityBuffer
    }
}
