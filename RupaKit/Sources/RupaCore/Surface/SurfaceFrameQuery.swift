public struct SurfaceFrameQuery: Codable, Hashable, Sendable {
    public var faceID: String?
    public var faceSubshapeID: String?
    public var selectionReference: SelectionReference?
    public var u: Double?
    public var v: Double?

    public init(
        faceID: String? = nil,
        faceSubshapeID: String? = nil,
        selectionReference: SelectionReference? = nil,
        u: Double? = nil,
        v: Double? = nil
    ) {
        self.faceID = faceID
        self.faceSubshapeID = faceSubshapeID
        self.selectionReference = selectionReference
        self.u = u
        self.v = v
    }
}
