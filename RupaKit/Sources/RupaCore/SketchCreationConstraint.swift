/// An ID-free relation whose entity references are local indexes in a sketch plan.
public enum SketchCreationConstraint: Codable, Equatable, Hashable, Sendable {
  case coincident(SketchCreationEndpointReference, SketchCreationEndpointReference)
  case parallel(Int, Int)
  case perpendicular(Int, Int)
  case horizontal(Int)
  case vertical(Int)
  case equalLength(Int, Int)
  case concentric(Int, Int)
  case equalRadius(Int, Int)
}
