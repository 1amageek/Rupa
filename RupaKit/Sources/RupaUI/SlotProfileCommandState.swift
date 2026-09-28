/// Offset Planar Curve and Slot on one selected open sketch curve, and Offset Vertex on one
/// selected curve end: O starts Offset (or Offset Vertex on an end), O again turns an Offset into
/// Slot, D focuses the distance, S makes an offset symmetric, and Return creates the result.
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
        /// Offset Vertex: new vertices on both sides of the selected curve end.
        case vertexOffset
    }

    var inputMode: InputMode
    var output: Output
    /// Offset Planar Curve's Symmetric option: copies on both sides.
    var isSymmetric: Bool
    /// Offset Planar Curve's Freestyle (F): a click sets the distance to where the offset passes.
    var isFreestyle = false

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
        switch output {
        case .offset: "Offset"
        case .slot: "Slot"
        case .vertexOffset: "Offset Vertex"
        }
    }

    var isVertexOffsetActive: Bool {
        isActive && output == .vertexOffset
    }

    var inputModeTitle: String {
        switch inputMode {
        case .inactive:
            return "Inactive"
        case .width:
            return output == .slot ? "Width" : "Distance"
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
        isFreestyle = false
        inputMode = .width
    }

    /// O with a curve end selected: Offset Vertex.
    mutating func beginVertexOffset() {
        output = .vertexOffset
        isSymmetric = false
        isFreestyle = false
        inputMode = .width
    }

    mutating func activateWidthInput() {
        inputMode = .width
    }

    mutating func toggleSymmetric() {
        isSymmetric.toggle()
    }

    /// F in Offset Planar Curve.
    mutating func toggleFreestyle() {
        isFreestyle.toggle()
    }

    mutating func deactivate() {
        inputMode = .inactive
        isFreestyle = false
    }
}
