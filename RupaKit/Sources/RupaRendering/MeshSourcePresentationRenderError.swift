import Foundation

public struct MeshSourcePresentationRenderError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case invalidSceneItem
        case invalidIdentifier
        case sourceAuthorityMismatch
        case invalidTransform
        case invalidFaceRange
        case invalidCornerReference
        case invalidVertexReference
        case degenerateFace
        case missingFace
        case nonPlanar
        case degenerate
        case failed
        case transformFailure
        case sizeOverflow
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
