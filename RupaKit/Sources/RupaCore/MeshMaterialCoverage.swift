public enum MeshMaterialCoverage: String, Codable, Equatable, Sendable {
    case body
    case missing
    case partialFace
    case completeFace
    case mixedFace
}
