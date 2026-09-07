import Foundation

/// Selects the lens used by a viewport camera.
///
/// The projection is presentation state. It never changes the scene source,
/// evaluation, selection, or saved project data.
public enum ViewportCameraProjection: Equatable, Hashable, Sendable {
    case parallel
    case perspective(fieldOfViewRadians: Double)

    /// The default vertical field of view used by the Perspective control.
    public static let standardPerspective = ViewportCameraProjection.perspective(
        fieldOfViewRadians: .pi / 3.0
    )

    public var fieldOfViewRadians: Double? {
        guard case .perspective(let value) = self else {
            return nil
        }
        return value
    }

    public var isValid: Bool {
        switch self {
        case .parallel:
            true
        case .perspective(let fieldOfViewRadians):
            fieldOfViewRadians.isFinite
                && fieldOfViewRadians > 0.0
                && fieldOfViewRadians < .pi
        }
    }
}
