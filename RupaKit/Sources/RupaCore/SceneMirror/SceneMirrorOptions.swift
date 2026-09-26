/// Mirror's command dialog options.
public struct SceneMirrorOptions: Codable, Hashable, Sendable {
    /// Cut each object at the plane and mirror only its material opposite the normal.
    public var cutsAtPlane: Bool
    /// Join each object's kept material and its reflection into one body.
    public var unionsHalves: Bool
    /// Show the reflection as a component instance of the object instead of an independent copy.
    public var makesInstances: Bool

    public init(cutsAtPlane: Bool = false, unionsHalves: Bool = false, makesInstances: Bool = false) {
        self.cutsAtPlane = cutsAtPlane
        self.unionsHalves = unionsHalves
        self.makesInstances = makesInstances
    }
}
