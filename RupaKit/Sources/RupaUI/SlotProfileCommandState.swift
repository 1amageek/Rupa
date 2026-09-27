/// Offset Planar Curve and Slot on one selected open sketch curve: O starts Offset, O again turns
/// it into Slot, D focuses the distance, and S makes an offset symmetric.
struct SlotProfileCommandState: Equatable {
    enum InputMode: Equatable {
        case inactive
        case width
    }

    /// What the command makes from the curve.
    enum Output: Equatable {
        /// Offset Planar Curve: a copy of the curve at the distance.
        case offset
        /// Slot: the curve offset symmetrically and closed by tangent arcs.
        case slot
    }

    var inputMode: InputMode
    var output: Output
    /// Offset Planar Curve's Symmetric option: copies on both sides.
    var isSymmetric: Bool

    init(inputMode: InputMode = .inactive, output: Output = .slot, isSymmetric: Bool = false) {
        self.inputMode = inputMode
        self.output = output
        self.isSymmetric = isSymmetric
    }

    static var inactive: SlotProfileCommandState {
        SlotProfileCommandState()
    }

    var isActive: Bool {
        inputMode != .inactive
    }

    var isCurveOffsetActive: Bool {
        isActive && output == .offset
    }

    var title: String {
        output == .offset ? "Offset" : "Slot"
    }

    var inputModeTitle: String {
        switch inputMode {
        case .inactive:
            return "Inactive"
        case .width:
            return output == .offset ? "Distance" : "Width"
        }
    }

    /// O: starts Offset, and turns a running Offset into Slot.
    mutating func pressOffsetKey() {
        if isCurveOffsetActive {
            output = .slot
        } else {
            output = .offset
            isSymmetric = false
        }
        inputMode = .width
    }

    mutating func activateWidthInput() {
        inputMode = .width
    }

    mutating func toggleSymmetric() {
        isSymmetric.toggle()
    }

    mutating func deactivate() {
        inputMode = .inactive
    }
}
