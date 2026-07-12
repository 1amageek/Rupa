import Foundation

public struct MeshFaceLoop: Sendable, RandomAccessCollection {
    public typealias Element = MeshCornerID
    public typealias Index = Int

    public let faceID: MeshFaceID
    private let cornerView: GeometryBufferView<MeshCornerID>

    init(faceID: MeshFaceID, cornerView: GeometryBufferView<MeshCornerID>) {
        self.faceID = faceID
        self.cornerView = cornerView
    }

    public var startIndex: Int {
        cornerView.startIndex
    }

    public var endIndex: Int {
        cornerView.endIndex
    }

    public subscript(position: Int) -> MeshCornerID {
        cornerView[position]
    }
}
