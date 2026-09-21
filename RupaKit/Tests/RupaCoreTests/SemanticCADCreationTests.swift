import Foundation
import SwiftCAD
import Testing

@testable import RupaCore

@Suite("Semantic CAD creation")
@MainActor
struct SemanticCADCreationTests {
  @Test(.timeLimit(.minutes(1)))
  func analyticSphereRetainsExactSourceProductAndBRep() throws {
    for center in [
      Point3D.origin,
      Point3D(x: 2.5, y: -1.25, z: 4.0),
    ] {
      let session = EditorSession()
      let radius = 0.75

      let result = try session.execute(
        .createAnalyticSphere(
          name: "Exact Sphere",
          center: center,
          radius: radius
        )
      )

      let featureID = try #require(result.primaryFeatureID)
      let feature = try #require(
        session.document.cadDocument.designGraph.nodes[featureID]
      )
      guard case .primitive(let primitive) = feature.operation,
        case .sphere(let sphere) = primitive.definition
      else {
        Issue.record("Analytic sphere command must retain a sphere primitive source.")
        return
      }
      let resolvedRadius = try session.document.cadDocument.parameters
        .resolvedValue(for: sphere.radius)
      let sceneNode = try #require(
        session.document.productMetadata.sceneNodes.values.first {
          $0.reference == .body(featureID)
        }
      )
      let object = try #require(sceneNode.object)
      let evaluation = try #require(session.currentEvaluation)
      let evaluated = evaluation.evaluatedDocument
      let measuredVolume = try evaluated.brep.volume(
        tolerance: session.document.modelingSettings.tolerance
      )
      let expectedVolume = 4.0 * Double.pi * radius * radius * radius / 3.0
      let stableReferences = try evaluated.subshapes.entries.map {
        try evaluated.stableSubshapeReference(for: $0.key)
      }
      let measurement = try MeasurementService().measure(
        document: session.document,
        ruler: .standard(for: .millimeter),
        currentEvaluation: evaluation,
        currentGeneration: session.generation
      )
      let measuredSolid = try #require(measurement.solids.first)

      #expect(sphere.placement.origin == center)
      #expect(sphere.placement.axis == .unitZ)
      #expect(sphere.placement.referenceDirection == .unitX)
      #expect(resolvedRadius == .length(radius, unit: .meter))
      #expect(feature.outputs == [FeatureOutput(role: .body)])
      #expect(object.typeID == .sphere)
      #expect(object.geometryRole == .solid)
      #expect(object.properties["radius"] == .length(radius))
      let sphereDefinition = try #require(ObjectTypeCatalog.definition(for: .sphere))
      let radiusDefinition = try #require(
        sphereDefinition.property(for: PropertyID(rawValue: "radius"))
      )
      #expect(radiusDefinition.inspectorControl == .readOnly)
      #expect(radiusDefinition.isEditable == false)
      #expect(radiusDefinition.renderBinding == nil)
      #expect(sceneNode.localTransform == .identity)
      #expect(result.generatedIdentities.featureIDs == [featureID])
      #expect(
        result.generatedIdentities.sourceBodyOutputs == [
          try GeneratedSourceBodyOutputIdentity(
            featureID: featureID,
            sourcePort: .body
          )
        ])
      #expect(result.generatedIdentities.sceneNodeIDs == [sceneNode.id])
      #expect(evaluated.brep.bodies.count == 1)
      #expect(evaluated.brep.faces.count == 8)
      #expect(evaluated.brep.edges.count == 12)
      #expect(evaluated.brep.vertices.count == 6)
      #expect(evaluated.subshapes.entries.count == 27)
      #expect(stableReferences.count == 27)
      #expect(measurement.counts.solids == 1)
      #expect(measuredSolid.featureID == featureID.description)
      #expect(measuredSolid.sourceFeatureID == featureID.description)
      #expect(measuredSolid.volumeMethod == .exactBRep)
      #expect(measuredSolid.surfaceAreaMethod == .tessellatedMesh)
      #expect(measuredSolid.boundsMethod == .tessellatedMesh)
      #expect(
        evaluated.brep.faces.values.allSatisfy { face in
          guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
            case .analytic(.sphere(let surfaceCenter, let surfaceRadius)) = surface
          else {
            return false
          }
          return surfaceCenter == center && surfaceRadius == radius
        })
      #expect(
        abs(measuredVolume - expectedVolume) <= max(
          expectedVolume * 1.0e-10,
          1.0e-18
        )
      )
      #expect(
        abs(measurement.totals.solidVolumeCubicMeters - expectedVolume) <= max(
          expectedVolume * 1.0e-10,
          1.0e-18
        )
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func analyticSphereRejectsInvalidDimensionsWithoutMutation() throws {
    let invalidRadii = [
      0.0,
      -1.0,
      ModelingTolerance.standard.distance,
      Double.nan,
      Double.infinity,
    ]
    for radius in invalidRadii {
      let session = EditorSession()
      #expect(throws: EditorError.self) {
        try session.execute(
          .createAnalyticSphere(
            name: "Invalid Sphere",
            center: .origin,
            radius: radius
          )
        )
      }
      assertUnchangedEmptySession(session)
    }

    for center in [
      Point3D(x: .nan, y: 0, z: 0),
      Point3D(x: 0, y: .infinity, z: 0),
    ] {
      let session = EditorSession()
      #expect(throws: EditorError.self) {
        try session.execute(
          .createAnalyticSphere(
            name: "Invalid Sphere",
            center: center,
            radius: 1.0
          )
        )
      }
      assertUnchangedEmptySession(session)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func analyticSphereRespectsExplicitMeshConstraintsAndRollsBackExhaustion() throws {
    var document = DesignDocument.empty()
    document.modelingSettings.tessellationOptions.maxEdgeLength = 1.0e-5
    let session = EditorSession(document: document)
    do {
      _ = try session.execute(.createAnalyticSphere(name: "Constrained Sphere", center: .origin, radius: 0.75))
      Issue.record("An exhausted mesh request must not publish a sphere or silently reduce fidelity.")
    } catch let error as EditorError {
      #expect(error.code == .evaluationFailed)
      #expect(error.message.contains("resourceExhausted"))
    }
    assertUnchangedEmptySession(session)
    #expect(session.document.modelingSettings == document.modelingSettings)
  }

  @Test(.timeLimit(.minutes(1)))
  func analyticSphereRollsBackCADWhenProductSynchronizationFails() throws {
    let definitions = ObjectTypeCatalog.builtInDefinitions.filter {
      $0.id != .sphere
    }
    let registry = try ObjectTypeRegistry(definitions: definitions)
    var document = DesignDocument.empty()
    let originalCADFingerprint = try document.cadDocument.sourceFingerprint(
      tolerance: document.modelingSettings.tolerance
    )
    let originalProduct = document.productMetadata

    #expect(throws: DocumentValidationError.self) {
      try document.createAnalyticSphere(
        name: "Unregistered Sphere",
        center: .origin,
        radius: 1.0,
        objectRegistry: registry
      )
    }

    #expect(
      try document.cadDocument.sourceFingerprint(
        tolerance: document.modelingSettings.tolerance
      ) == originalCADFingerprint
    )
    #expect(document.productMetadata == originalProduct)
  }

  @Test(.timeLimit(.minutes(1)))
  func analyticSphereRejectsDivergentProductRadiusAtomically() throws {
    let session = EditorSession()
    let result = try session.execute(
      .createAnalyticSphere(
        name: "Authoritative Sphere",
        center: .origin,
        radius: 1.0
      )
    )
    let featureID = try #require(result.primaryFeatureID)
    let sceneNodeID = try #require(
      session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(featureID)
      }?.id
    )
    let originalCADFingerprint = try session.document.cadDocument.sourceFingerprint(
      tolerance: session.document.modelingSettings.tolerance
    )
    let originalProduct = session.document.productMetadata
    var divergentProduct = originalProduct
    var sceneNode = try #require(divergentProduct.sceneNodes[sceneNodeID])
    var object = try #require(sceneNode.object)
    object.properties["radius"] = .length(2.0)
    sceneNode.object = object
    divergentProduct.sceneNodes[sceneNodeID] = sceneNode

    #expect(throws: EditorError.self) {
      try session.execute(.replaceProductMetadata(divergentProduct))
    }
    #expect(
      try session.document.cadDocument.sourceFingerprint(
        tolerance: session.document.modelingSettings.tolerance
      ) == originalCADFingerprint
    )
    #expect(session.document.productMetadata == originalProduct)
    #expect(session.evaluationStatus == .valid)
  }

  @Test(.timeLimit(.minutes(1)))
  func sphereProductTypeRejectsNonSphereCADSourceAtomically() throws {
    let session = EditorSession()
    let sphereResult = try session.execute(
      .createAnalyticSphere(
        name: "Sphere",
        center: .origin,
        radius: 1.0
      )
    )
    let boxResult = try session.execute(
      .createExtrudedRectangleFromCorners(
        name: "Box",
        plane: .xy,
        firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
        oppositeCorner: SketchPoint(x: .length(1, .meter), y: .length(1, .meter)),
        depth: .length(1, .meter),
        direction: .normal
      )
    )
    let sphereFeatureID = try #require(sphereResult.primaryFeatureID)
    let boxFeatureID = try #require(boxResult.primaryFeatureID)
    let sphereSceneNodeID = try #require(
      session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(sphereFeatureID)
      }?.id
    )
    let originalCADFingerprint = try session.document.cadDocument.sourceFingerprint(
      tolerance: session.document.modelingSettings.tolerance
    )
    let originalProduct = session.document.productMetadata
    var divergentProduct = originalProduct
    var sceneNode = try #require(divergentProduct.sceneNodes[sphereSceneNodeID])
    sceneNode.reference = .body(boxFeatureID)
    sceneNode.object = .body(
      featureID: boxFeatureID,
      documentID: session.document.id,
      sourceSection: nil,
      typeID: .sphere,
      properties: ObjectPropertySet(values: ["radius": .length(1.0)])
    )
    divergentProduct.sceneNodes[sphereSceneNodeID] = sceneNode

    #expect(throws: EditorError.self) {
      try session.execute(.replaceProductMetadata(divergentProduct))
    }
    #expect(
      try session.document.cadDocument.sourceFingerprint(
        tolerance: session.document.modelingSettings.tolerance
      ) == originalCADFingerprint
    )
    #expect(session.document.productMetadata == originalProduct)
    #expect(session.evaluationStatus == .valid)
  }

  @Test(.timeLimit(.minutes(1)))
  func semanticSketchMaterializesAllRelationFamiliesInInputOrder() throws {
    let plan = completeRelationPlan()
    let session = EditorSession()

    let result = try session.execute(
      .createSemanticSketch(
        name: "Constrained Sketch",
        plan: plan,
        geometryRole: .sketchProfile
      )
    )

    let featureID = try #require(result.primaryFeatureID)
    let feature = try #require(
      session.document.cadDocument.designGraph.nodes[featureID]
    )
    guard case .sketch(let sketch) = feature.operation else {
      Issue.record("Semantic sketch command must materialize an ordinary sketch feature.")
      return
    }
    let ids = sketch.entityOrder

    #expect(ids.count == plan.entities.count)
    #expect(Set(ids).count == ids.count)
    #expect(sketch.orderedEntities.map(\.id) == ids)
    #expect(
      sketch.constraints == [
        .coincident(.lineStart(ids[0]), .lineStart(ids[2])),
        .parallel(ids[0], ids[1]),
        .perpendicular(ids[0], ids[2]),
        .horizontal(ids[0]),
        .vertical(ids[2]),
        .equalLength(ids[0], ids[1]),
        .concentric(ids[3], ids[4]),
        .equalRadius(ids[3], ids[4]),
      ])
    #expect(result.generatedIdentities.featureIDs == [featureID])
    #expect(result.generatedIdentities.sceneNodeIDs.count == 1)
    #expect(session.evaluationStatus == .valid)
  }

  @Test(.timeLimit(.minutes(1)))
  func repeatedSemanticPlanReceivesDistinctCoreOwnedEntityIDs() throws {
    let plan = completeRelationPlan()
    let session = EditorSession()

    let first = try session.execute(
      .createSemanticSketch(
        name: "First Sketch",
        plan: plan,
        geometryRole: .sketchProfile
      )
    )
    let second = try session.execute(
      .createSemanticSketch(
        name: "Second Sketch",
        plan: plan,
        geometryRole: .sketchProfile
      )
    )
    let firstSketch = try sketch(
      featureID: #require(first.primaryFeatureID),
      in: session.document
    )
    let secondSketch = try sketch(
      featureID: #require(second.primaryFeatureID),
      in: session.document
    )

    #expect(firstSketch.entityOrder.count == secondSketch.entityOrder.count)
    #expect(Set(firstSketch.entityOrder).isDisjoint(with: secondSketch.entityOrder))
  }

  @Test(.timeLimit(.minutes(1)))
  func semanticSketchRejectsInvalidReferencesKindsAndDuplicatesAtomically() throws {
    let line = SketchCreationEntity.line(
      start: point(0, 0),
      end: point(1, 0)
    )
    let circle = SketchCreationEntity.circle(
      center: point(2, 2),
      radius: length(1)
    )
    let invalidConstraints: [[SketchCreationConstraint]] = [
      [.parallel(0, 2)],
      [.horizontal(-1)],
      [.horizontal(1)],
      [.concentric(0, 1)],
      [.parallel(0, 0)],
      [
        .coincident(
          SketchCreationEndpointReference(entityIndex: 0, endpoint: .start),
          SketchCreationEndpointReference(entityIndex: 0, endpoint: .end)
        )
      ],
      [.vertical(0), .vertical(0)],
      [.parallel(0, 1), .parallel(1, 0)],
    ]

    for constraints in invalidConstraints {
      let session = EditorSession()
      let plan = SketchCreationPlan(
        plane: .xy,
        entities: [line, circle],
        constraints: constraints
      )
      #expect(throws: EditorError.self) {
        try session.execute(
          .createSemanticSketch(
            name: "Invalid Sketch",
            plan: plan,
            geometryRole: .sketchProfile
          )
        )
      }
      assertUnchangedEmptySession(session)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func semanticSketchRejectsEmptyAndDegenerateEntitiesAtomically() throws {
    let invalidEntityLists: [[SketchCreationEntity]] = [
      [],
      [.line(start: point(0, 0), end: point(0, 0))],
      [
        .line(
          start: point(0, 0),
          end: point(ModelingTolerance.standard.distance, 0)
        )
      ],
      [.circle(center: point(0, 0), radius: length(0))],
      [
        .circle(
          center: point(0, 0),
          radius: length(ModelingTolerance.standard.distance)
        )
      ],
    ]

    for entities in invalidEntityLists {
      let session = EditorSession()
      #expect(throws: EditorError.self) {
        try session.execute(
          .createSemanticSketch(
            name: "Invalid Sketch",
            plan: SketchCreationPlan(
              plane: .xy,
              entities: entities
            ),
            geometryRole: .sketchProfile
          )
        )
      }
      assertUnchangedEmptySession(session)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func semanticCreationCommandsRoundTripWithoutPersistentRequestIDs() throws {
    let commands: [EditorCommand] = [
      .createSemanticSketch(
        name: "Sketch",
        plan: completeRelationPlan(),
        geometryRole: .sketchProfile
      ),
      .createAnalyticSphere(
        name: "Sphere",
        center: Point3D(x: 1, y: 2, z: 3),
        radius: 4
      ),
    ]
    let data = try JSONEncoder().encode(commands)
    let decoded = try JSONDecoder().decode([EditorCommand].self, from: data)

    #expect(decoded == commands)
  }
}

@MainActor
private func assertUnchangedEmptySession(
  _ session: EditorSession,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(session.generation == DocumentGeneration(0), sourceLocation: sourceLocation)
  #expect(session.document.cadDocument.designGraph.order.isEmpty, sourceLocation: sourceLocation)
  #expect(session.document.productMetadata.sceneNodes.count == 1, sourceLocation: sourceLocation)
  #expect(session.commandStack.undoEntries.isEmpty, sourceLocation: sourceLocation)
}

private func completeRelationPlan() -> SketchCreationPlan {
  SketchCreationPlan(
    plane: .xy,
    entities: [
      .line(start: point(0, 0), end: point(1, 0)),
      .line(start: point(0, 1), end: point(1, 1)),
      .line(start: point(0, 0), end: point(0, 1)),
      .circle(center: point(2, 2), radius: length(1)),
      .circle(center: point(2, 2), radius: length(1)),
    ],
    constraints: [
      .coincident(
        SketchCreationEndpointReference(entityIndex: 0, endpoint: .start),
        SketchCreationEndpointReference(entityIndex: 2, endpoint: .start)
      ),
      .parallel(0, 1),
      .perpendicular(0, 2),
      .horizontal(0),
      .vertical(2),
      .equalLength(0, 1),
      .concentric(3, 4),
      .equalRadius(3, 4),
    ]
  )
}

private func sketch(
  featureID: FeatureID,
  in document: DesignDocument
) throws -> Sketch {
  let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
  guard case .sketch(let sketch) = feature.operation else {
    throw EditorError(
      code: .commandInvalid,
      message: "Expected a sketch feature."
    )
  }
  return sketch
}

private func point(_ x: Double, _ y: Double) -> SketchPoint {
  SketchPoint(x: length(x), y: length(y))
}

private func length(_ value: Double) -> CADExpression {
  .length(value, .meter)
}
