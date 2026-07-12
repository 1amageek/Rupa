import Foundation

public struct GeometryAttributeDomainCounts: Codable, Equatable, Sendable {
    public var vertex: Int
    public var edge: Int
    public var face: Int
    public var corner: Int
    public var point: Int
    public var curve: Int
    public var instance: Int

    public init(
        vertex: Int,
        edge: Int,
        face: Int,
        corner: Int,
        point: Int = 0,
        curve: Int = 0,
        instance: Int = 0
    ) {
        self.vertex = vertex
        self.edge = edge
        self.face = face
        self.corner = corner
        self.point = point
        self.curve = curve
        self.instance = instance
    }

    public func count(for domain: GeometryAttributeDomain) -> Int {
        switch domain {
        case .vertex:
            vertex
        case .edge:
            edge
        case .face:
            face
        case .corner:
            corner
        case .point:
            point
        case .curve:
            curve
        case .instance:
            instance
        }
    }
}
