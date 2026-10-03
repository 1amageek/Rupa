import RupaCore

/// A value of the running dialog the viewport offers as a handle, as Plasticity's yellow dot: the
/// handle sits `valueMeters × worldMetresPerValue` from its anchor's origin along the anchor's
/// direction, on a guide line through the origin, and a drag along the guide sets the value. A
/// square marks a second value (a thickness) apart from the dot of the first.
public struct ViewportDialogValueHandle: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case dot
        case square
    }

    /// Where the value is measured from, and along which direction.
    public enum Anchor: Equatable, Sendable {
        case point(Point3D, direction: Vector3D)
        /// The start of a curve object or of a body's edge as the scene draws it, the guide square
        /// to the curve there, the origin `offsetMeters` out along the guide.
        case curveStart(SelectionTarget, offsetMeters: Double)
    }

    /// The dialog's name for the value, which a drag reports back.
    public var id: String
    public var anchor: Anchor
    public var valueMeters: Double
    /// World metres the handle moves per metre of value: 0.5 for a diameter measured from its centre.
    public var worldMetresPerValue: Double
    public var shape: Shape

    public init(id: String, anchor: Anchor, valueMeters: Double, worldMetresPerValue: Double = 1, shape: Shape = .dot) {
        self.id = id
        self.anchor = anchor
        self.valueMeters = valueMeters
        self.worldMetresPerValue = worldMetresPerValue
        self.shape = shape
    }
}

/// A dialog value a drag of its handle set.
public struct ViewportDialogValueDragTarget: Equatable, Sendable {
    public var id: String
    public var valueMeters: Double

    public init(id: String, valueMeters: Double) {
        self.id = id
        self.valueMeters = valueMeters
    }
}
