public struct SavedViewProjection: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Hashable, Sendable {
        case orthographic
        case perspective
    }

    public var mode: Mode
    public var orthographicHeightMeters: Double?
    public var fieldOfViewRadians: Double?

    public init(
        mode: Mode,
        orthographicHeightMeters: Double? = nil,
        fieldOfViewRadians: Double? = nil
    ) {
        self.mode = mode
        self.orthographicHeightMeters = orthographicHeightMeters
        self.fieldOfViewRadians = fieldOfViewRadians
    }

    public static func orthographic(heightMeters: Double) -> SavedViewProjection {
        SavedViewProjection(mode: .orthographic, orthographicHeightMeters: heightMeters)
    }

    public static func perspective(fieldOfViewRadians: Double) -> SavedViewProjection {
        SavedViewProjection(mode: .perspective, fieldOfViewRadians: fieldOfViewRadians)
    }

    public func validate() throws {
        switch mode {
        case .orthographic:
            guard fieldOfViewRadians == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Saved view orthographic projection must not store a perspective field of view."
                )
            }
            guard let orthographicHeightMeters,
                  orthographicHeightMeters.isFinite,
                  orthographicHeightMeters > 0.0 else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Saved view orthographic height must be finite and positive."
                )
            }
        case .perspective:
            guard orthographicHeightMeters == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Saved view perspective projection must not store an orthographic height."
                )
            }
            guard let fieldOfViewRadians,
                  fieldOfViewRadians.isFinite,
                  fieldOfViewRadians > 0.0,
                  fieldOfViewRadians < Double.pi else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Saved view perspective field of view must be between 0 and 180 degrees."
                )
            }
        }
    }
}
