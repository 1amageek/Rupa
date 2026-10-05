import Foundation

/// Caller-owned work and storage admission for one complete optical frame.
struct OpticalVolumeLimits: Sendable {
    let maxInteractionCount: UInt32
    let maxTraversalWork: UInt64
    let maxRetainedByteCount: Int

    init(maxInteractionCount: UInt32, maxTraversalWork: UInt64, maxRetainedByteCount: Int) throws {
        guard maxInteractionCount > 0, maxTraversalWork > 0, maxRetainedByteCount > 0 else {
            throw MeshSourcePresentationRenderError(code: .invalidLimit, message: "Optical limits must be positive.")
        }
        self.maxInteractionCount = maxInteractionCount
        self.maxTraversalWork = maxTraversalWork
        self.maxRetainedByteCount = maxRetainedByteCount
    }

    /// Derive addressable interface work from the already admitted source plan.
    /// This is a work ceiling, not a promise that every ray terminates within it.
    static func admitted(triangleCount: Int, remainingBytes: Int) throws -> Self {
        let (interfaces, overflow) = triangleCount.multipliedReportingOverflow(by: 2)
        guard !overflow, interfaces < Int(UInt32.max), remainingBytes > 0 else {
            throw MeshSourcePresentationRenderError(code: .resourceExhausted, message: "Optical source admission overflowed.")
        }
        return try Self(maxInteractionCount: UInt32(max(1, interfaces + 1)),
                        maxTraversalWork: UInt64(UInt32.max), maxRetainedByteCount: remainingBytes)
    }
}
