import Foundation
import RupaCoreTypes
import SwiftCAD

extension DesignDocument {
  @discardableResult
  public mutating func createAnalyticSphere(
    name: String,
    center: Point3D,
    radius: Double,
    objectRegistry: ObjectTypeRegistry = .builtIn
  ) throws -> FeatureID {
    let trimmedName = try normalizedMetadataName(name, owner: "Sphere")
    guard center.isFinite else {
      throw EditorError(
        code: .commandInvalid,
        message: "Sphere center must be finite."
      )
    }
    guard radius.isFinite,
      radius > modelingSettings.tolerance.distance
    else {
      throw EditorError(
        code: .commandInvalid,
        message: "Sphere radius must be finite and greater than the document tolerance."
      )
    }

    let primitive = SpherePrimitive(
      placement: PrimitivePlacement(
        origin: center,
        axis: .unitZ,
        referenceDirection: .unitX
      ),
      radius: .length(radius, .meter)
    )
    do {
      try primitive.validate(tolerance: modelingSettings.tolerance)
    } catch {
      throw EditorError(
        code: .commandInvalid,
        message: "Sphere source is invalid: \(error)."
      )
    }

    let featureID = FeatureID()
    let feature = FeatureNode(
      id: featureID,
      name: trimmedName,
      operation: .primitive(PrimitiveFeature(definition: .sphere(primitive))),
      outputs: [FeatureOutput(role: .body)]
    )
    let previousCADDocument = cadDocument
    let previousProductMetadata = productMetadata
    var didCommit = false
    defer {
      if didCommit == false {
        cadDocument = previousCADDocument
        productMetadata = previousProductMetadata
      }
    }

    try appendFeature(feature)
    _ = try productMetadata.appendSceneNodeToFirstRoot(
      name: trimmedName,
      reference: .body(featureID),
      object: .body(
        featureID: featureID,
        documentID: cadDocument.id,
        sourceSection: nil,
        typeID: .sphere,
        properties: ObjectPropertySet(values: [
          "radius": .length(radius)
        ]),
        objectRegistry: objectRegistry
      )
    )
    try productMetadata.validate(
      against: cadDocument,
      objectRegistry: objectRegistry
    )
    didCommit = true
    return featureID
  }

  @discardableResult
  public mutating func createSemanticSketch(
    name: String,
    plan: SketchCreationPlan,
    geometryRole: ObjectDescriptor.GeometryRole = .sketchProfile,
    objectRegistry: ObjectTypeRegistry = .builtIn
  ) throws -> FeatureID {
    _ = try normalizedMetadataName(name, owner: "Sketch")
    guard geometryRole == .sketchProfile || geometryRole == .curve else {
      throw EditorError(
        code: .commandInvalid,
        message: "Sketch geometry role must be sketchProfile or curve."
      )
    }
    guard plan.entities.isEmpty == false else {
      throw EditorError(
        code: .commandInvalid,
        message: "Semantic sketch must contain at least one entity."
      )
    }
    do {
      try ConstructionPlaneSource.validatePlane(plan.plane)
    } catch {
      throw EditorError(
        code: .commandInvalid,
        message: "Semantic sketch plane is invalid: \(error)."
      )
    }

    try validateSemanticSketchEntities(plan.entities)
    try validateSemanticSketchConstraints(
      plan.constraints,
      entities: plan.entities
    )

    let entityIDs = plan.entities.map { _ in SketchEntityID() }
    var entities: [SketchEntityID: SketchEntity] = [:]
    entities.reserveCapacity(plan.entities.count)
    for (index, entity) in plan.entities.enumerated() {
      entities[entityIDs[index]] = entity.materialized
    }
    let constraints = plan.constraints.map { constraint in
      constraint.materialized(using: entityIDs)
    }
    let sketch = Sketch(
      plane: plan.plane,
      entities: entities,
      entityOrder: entityIDs,
      constraints: constraints
    )
    return try createSketch(
      name: name,
      sketch: sketch,
      geometryRole: geometryRole,
      objectRegistry: objectRegistry
    )
  }

  private func validateSemanticSketchEntities(
    _ entities: [SketchCreationEntity]
  ) throws {
    for (index, entity) in entities.enumerated() {
      switch entity {
      case .line(let start, let end):
        let startX = try resolvedLengthValue(
          start.x,
          owner: "Semantic sketch line \(index) start x"
        )
        let startY = try resolvedLengthValue(
          start.y,
          owner: "Semantic sketch line \(index) start y"
        )
        let endX = try resolvedLengthValue(
          end.x,
          owner: "Semantic sketch line \(index) end x"
        )
        let endY = try resolvedLengthValue(
          end.y,
          owner: "Semantic sketch line \(index) end y"
        )
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > modelingSettings.tolerance.distance else {
          throw EditorError(
            code: .commandInvalid,
            message: "Semantic sketch line \(index) must be longer than the document tolerance."
          )
        }
      case .circle(let center, let radius):
        _ = try resolvedLengthValue(
          center.x,
          owner: "Semantic sketch circle \(index) center x"
        )
        _ = try resolvedLengthValue(
          center.y,
          owner: "Semantic sketch circle \(index) center y"
        )
        let resolvedRadius = try resolvedLengthValue(
          radius,
          owner: "Semantic sketch circle \(index) radius"
        )
        guard resolvedRadius > modelingSettings.tolerance.distance else {
          throw EditorError(
            code: .commandInvalid,
            message:
              "Semantic sketch circle \(index) radius must be greater than the document tolerance."
          )
        }
      }
    }
  }

  private func validateSemanticSketchConstraints(
    _ constraints: [SketchCreationConstraint],
    entities: [SketchCreationEntity]
  ) throws {
    guard Set(constraints.map(\.canonicalIdentity)).count == constraints.count else {
      throw EditorError(
        code: .commandInvalid,
        message: "Semantic sketch constraints must not contain duplicates."
      )
    }
    for constraint in constraints {
      switch constraint {
      case .coincident(let first, let second):
        try requireLineEntity(
          at: first.entityIndex,
          in: entities,
          owner: "Coincident first endpoint"
        )
        try requireLineEntity(
          at: second.entityIndex,
          in: entities,
          owner: "Coincident second endpoint"
        )
        guard first.entityIndex != second.entityIndex else {
          throw selfReferenceError(owner: "Coincident")
        }
      case .parallel(let first, let second):
        try requireDistinctLinePair(
          first,
          second,
          in: entities,
          owner: "Parallel"
        )
      case .perpendicular(let first, let second):
        try requireDistinctLinePair(
          first,
          second,
          in: entities,
          owner: "Perpendicular"
        )
      case .horizontal(let index):
        try requireLineEntity(at: index, in: entities, owner: "Horizontal")
      case .vertical(let index):
        try requireLineEntity(at: index, in: entities, owner: "Vertical")
      case .equalLength(let first, let second):
        try requireDistinctLinePair(
          first,
          second,
          in: entities,
          owner: "Equal-length"
        )
      case .concentric(let first, let second):
        try requireDistinctCirclePair(
          first,
          second,
          in: entities,
          owner: "Concentric"
        )
      case .equalRadius(let first, let second):
        try requireDistinctCirclePair(
          first,
          second,
          in: entities,
          owner: "Equal-radius"
        )
      }
    }
  }

  private func requireDistinctLinePair(
    _ first: Int,
    _ second: Int,
    in entities: [SketchCreationEntity],
    owner: String
  ) throws {
    try requireLineEntity(at: first, in: entities, owner: "\(owner) first entity")
    try requireLineEntity(at: second, in: entities, owner: "\(owner) second entity")
    guard first != second else {
      throw selfReferenceError(owner: owner)
    }
  }

  private func requireDistinctCirclePair(
    _ first: Int,
    _ second: Int,
    in entities: [SketchCreationEntity],
    owner: String
  ) throws {
    try requireCircleEntity(at: first, in: entities, owner: "\(owner) first entity")
    try requireCircleEntity(at: second, in: entities, owner: "\(owner) second entity")
    guard first != second else {
      throw selfReferenceError(owner: owner)
    }
  }

  private func requireLineEntity(
    at index: Int,
    in entities: [SketchCreationEntity],
    owner: String
  ) throws {
    guard entities.indices.contains(index) else {
      throw outOfRangeError(index: index, owner: owner)
    }
    guard case .line = entities[index] else {
      throw EditorError(
        code: .commandInvalid,
        message: "\(owner) must reference a line entity."
      )
    }
  }

  private func requireCircleEntity(
    at index: Int,
    in entities: [SketchCreationEntity],
    owner: String
  ) throws {
    guard entities.indices.contains(index) else {
      throw outOfRangeError(index: index, owner: owner)
    }
    guard case .circle = entities[index] else {
      throw EditorError(
        code: .commandInvalid,
        message: "\(owner) must reference a circle entity."
      )
    }
  }

  private func outOfRangeError(index: Int, owner: String) -> EditorError {
    EditorError(
      code: .commandInvalid,
      message: "\(owner) index \(index) is outside the semantic sketch entity list."
    )
  }

  private func selfReferenceError(owner: String) -> EditorError {
    EditorError(
      code: .commandInvalid,
      message: "\(owner) requires two distinct entity references."
    )
  }
}

extension SketchCreationEntity {
  fileprivate var materialized: SketchEntity {
    switch self {
    case .line(let start, let end):
      .line(SketchLine(start: start, end: end))
    case .circle(let center, let radius):
      .circle(SketchCircle(center: center, radius: radius))
    }
  }
}

extension SketchCreationConstraint {
  fileprivate var canonicalIdentity: String {
    switch self {
    case .coincident(let first, let second):
      let references = [first.canonicalIdentity, second.canonicalIdentity].sorted()
      return "coincident:\(references[0]):\(references[1])"
    case .parallel(let first, let second):
      return canonicalPairIdentity(kind: "parallel", first: first, second: second)
    case .perpendicular(let first, let second):
      return canonicalPairIdentity(kind: "perpendicular", first: first, second: second)
    case .horizontal(let index):
      return "horizontal:\(index)"
    case .vertical(let index):
      return "vertical:\(index)"
    case .equalLength(let first, let second):
      return canonicalPairIdentity(kind: "equalLength", first: first, second: second)
    case .concentric(let first, let second):
      return canonicalPairIdentity(kind: "concentric", first: first, second: second)
    case .equalRadius(let first, let second):
      return canonicalPairIdentity(kind: "equalRadius", first: first, second: second)
    }
  }

  private func canonicalPairIdentity(
    kind: String,
    first: Int,
    second: Int
  ) -> String {
    "\(kind):\(min(first, second)):\(max(first, second))"
  }

  fileprivate func materialized(using entityIDs: [SketchEntityID]) -> SketchConstraint {
    switch self {
    case .coincident(let first, let second):
      .coincident(
        first.materialized(using: entityIDs),
        second.materialized(using: entityIDs)
      )
    case .parallel(let first, let second):
      .parallel(entityIDs[first], entityIDs[second])
    case .perpendicular(let first, let second):
      .perpendicular(entityIDs[first], entityIDs[second])
    case .horizontal(let index):
      .horizontal(entityIDs[index])
    case .vertical(let index):
      .vertical(entityIDs[index])
    case .equalLength(let first, let second):
      .equalLength(entityIDs[first], entityIDs[second])
    case .concentric(let first, let second):
      .concentric(entityIDs[first], entityIDs[second])
    case .equalRadius(let first, let second):
      .equalRadius(entityIDs[first], entityIDs[second])
    }
  }
}

extension SketchCreationEndpointReference {
  fileprivate var canonicalIdentity: String {
    "\(entityIndex):\(endpoint.rawValue)"
  }

  fileprivate func materialized(using entityIDs: [SketchEntityID]) -> SketchReference {
    switch endpoint {
    case .start:
      .lineStart(entityIDs[entityIndex])
    case .end:
      .lineEnd(entityIDs[entityIndex])
    }
  }
}
