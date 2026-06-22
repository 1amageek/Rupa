import Foundation

public struct ObjectTypeID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public extension ObjectTypeID {
    static let line: ObjectTypeID = "line"
    static let arc: ObjectTypeID = "arc"
    static let spline: ObjectTypeID = "spline"
    static let rectangle: ObjectTypeID = "rectangle"
    static let circle: ObjectTypeID = "circle"
    static let ellipse: ObjectTypeID = "ellipse"
    static let polygon: ObjectTypeID = "polygon"
    static let slot: ObjectTypeID = "slot"
    static let path: ObjectTypeID = "path"
    static let text: ObjectTypeID = "text"
    static let cube: ObjectTypeID = "cube"
    static let sphere: ObjectTypeID = "sphere"
    static let cylinder: ObjectTypeID = "cylinder"
    static let torus: ObjectTypeID = "torus"
    static let helix: ObjectTypeID = "helix"
    static let cone: ObjectTypeID = "cone"
    static let pyramid: ObjectTypeID = "pyramid"
    static let icosahedron: ObjectTypeID = "icosahedron"
    static let dodecahedron: ObjectTypeID = "dodecahedron"
    static let torusKnot: ObjectTypeID = "torusKnot"
    static let polySpline: ObjectTypeID = "polySpline"
}
