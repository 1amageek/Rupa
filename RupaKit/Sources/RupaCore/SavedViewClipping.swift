public struct SavedViewClipping: Codable, Hashable, Sendable {
    public var nearDistanceMeters: Double?
    public var farDistanceMeters: Double?

    public init(
        nearDistanceMeters: Double? = nil,
        farDistanceMeters: Double? = nil
    ) {
        self.nearDistanceMeters = nearDistanceMeters
        self.farDistanceMeters = farDistanceMeters
    }

    public func validate() throws {
        if let nearDistanceMeters {
            guard nearDistanceMeters.isFinite,
                  nearDistanceMeters >= 0.0 else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Saved view near clipping distance must be finite and non-negative."
                )
            }
        }
        if let farDistanceMeters {
            guard farDistanceMeters.isFinite,
                  farDistanceMeters > 0.0 else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Saved view far clipping distance must be finite and positive."
                )
            }
        }
        if let nearDistanceMeters,
           let farDistanceMeters,
           farDistanceMeters <= nearDistanceMeters {
            throw DocumentValidationError.invalidProductMetadata(
                "Saved view far clipping distance must be greater than near clipping distance."
            )
        }
    }
}
