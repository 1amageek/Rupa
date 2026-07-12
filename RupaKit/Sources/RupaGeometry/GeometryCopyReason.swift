public enum GeometryCopyReason: String, Codable, Equatable, Sendable {
    case sourceEdit
    case bufferMaterialization
    case codecEncode
    case codecDecode
}
