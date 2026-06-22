import Foundation

public struct ViewportProjectionRequest: Equatable, Sendable {
    public var id: UUID
    public var basis: ViewportProjectionBasis

    public init(
        id: UUID = UUID(),
        basis: ViewportProjectionBasis
    ) {
        self.id = id
        self.basis = basis
    }
}
