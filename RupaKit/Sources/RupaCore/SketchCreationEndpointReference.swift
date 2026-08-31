public struct SketchCreationEndpointReference: Codable, Equatable, Hashable, Sendable {
  public let entityIndex: Int
  public let endpoint: SketchCreationLineEndpoint

  public init(
    entityIndex: Int,
    endpoint: SketchCreationLineEndpoint
  ) {
    self.entityIndex = entityIndex
    self.endpoint = endpoint
  }
}
