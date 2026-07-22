public struct SurfaceFrameQuery: Codable, Hashable, Sendable {
    public var faceID: String?
    public var faceStableReference: StableSubshapeReference?
    public var selectionReference: SelectionReference?
    public var u: Double?
    public var v: Double?

    public init(
        faceID: String? = nil,
        faceStableReference: StableSubshapeReference? = nil,
        selectionReference: SelectionReference? = nil,
        u: Double? = nil,
        v: Double? = nil
    ) {
        self.faceID = faceID
        self.faceStableReference = faceStableReference
        self.selectionReference = selectionReference
        self.u = u
        self.v = v
    }
}
