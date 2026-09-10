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
        case budgetExceeded
        case invalidLimit
        case resourceExhausted
        /// No frame has judged this query yet: nothing is prepared, a
        /// preparation is still in flight, the mounted frame belongs to another
        /// scene or snapshot, or the native surface has no live content, no
        /// RealityKit scene, or no applied camera revision. A caller that can
        /// ask again should, because the state resolves itself; every other
        /// code is an answer the caller must act on.
        case frameNotReady
        case failed
        case transformFailure
        case sizeOverflow
        case gpuUnavailable
        case gpuFailure
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
